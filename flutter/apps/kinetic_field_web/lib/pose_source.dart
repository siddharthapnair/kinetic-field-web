import 'dart:async';

import 'package:kinetic_field/kinetic_field.dart';

enum PoseSourceFailure { denied, unavailable, failed }

class PoseSourceException implements Exception {
  const PoseSourceException(this.failure, this.message);

  final PoseSourceFailure failure;
  final String message;

  @override
  String toString() => message;
}

abstract interface class PoseSource {
  Stream<KineticInputFrame> get observations;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

typedef PoseSourceFactory = PoseSource Function();
typedef StartPoseBridge =
    Future<void> Function(
      void Function(KineticInputFrame frame) emit,
      void Function(PoseSourceException error) fail,
    );
typedef StopPoseBridge = Future<void> Function();

/// Adapts a platform bridge into the host's pose-source contract.
///
/// The web MoveNet integration only needs to supply [startBridge] and
/// [stopBridge]. Camera frames and model tensors stay outside Flutter and only
/// raw, versioned landmark frames cross this boundary.
class BridgePoseSource implements PoseSource {
  BridgePoseSource(this._startBridge, this._stopBridge);

  final StartPoseBridge _startBridge;
  final StopPoseBridge _stopBridge;
  final StreamController<KineticInputFrame> _observations =
      StreamController<KineticInputFrame>.broadcast(sync: true);

  bool _isActive = false;
  bool _isDisposed = false;
  Future<void>? _pendingStart;
  Future<void>? _pendingStop;
  int _operation = 0;

  @override
  Stream<KineticInputFrame> get observations => _observations.stream;

  @override
  Future<void> start() {
    if (_isDisposed) {
      return Future<void>.error(
        const PoseSourceException(
          PoseSourceFailure.failed,
          'The pose source has already been disposed.',
        ),
      );
    }
    if (_isActive) return Future<void>.value();
    final pendingStop = _pendingStop;
    if (pendingStop != null) {
      return pendingStop.then((_) => start());
    }
    final pendingStart = _pendingStart;
    if (pendingStart != null) return pendingStart;

    final operation = ++_operation;
    final startFuture = _performStart(operation);
    _pendingStart = startFuture;
    return startFuture.whenComplete(() {
      if (identical(_pendingStart, startFuture)) _pendingStart = null;
    });
  }

  Future<void> _performStart(int operation) async {
    PoseSourceException? bridgeFailure;
    await _startBridge(
      (frame) {
        if (!_isDisposed && operation == _operation && _isActive) {
          _observations.add(frame);
        }
      },
      (error) {
        if (_isDisposed || operation != _operation) return;
        bridgeFailure = error;
        _operation += 1;
        _isActive = false;
        _observations.addError(error, StackTrace.current);
      },
    );

    final failure = bridgeFailure;
    if (failure != null) throw failure;
    if (_isDisposed) {
      throw const PoseSourceException(
        PoseSourceFailure.failed,
        'The pose source was disposed while it was starting.',
      );
    }
    if (operation != _operation) {
      throw const PoseSourceException(
        PoseSourceFailure.failed,
        'The pose source was stopped while it was starting.',
      );
    }
    _isActive = true;
  }

  @override
  Future<void> stop() {
    final pendingStop = _pendingStop;
    if (pendingStop != null) return pendingStop;
    if (!_isActive && _pendingStart == null) return Future<void>.value();

    final stop = _performStop();
    _pendingStop = stop;
    return stop.whenComplete(() {
      if (identical(_pendingStop, stop)) _pendingStop = null;
    });
  }

  Future<void> _performStop() async {
    _operation += 1;
    _isActive = false;
    final pendingStart = _pendingStart;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        // Cancellation and bridge start failures still require bridge cleanup.
      }
    }
    await _stopBridge();
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _operation += 1;

    final pendingStop = _pendingStop;
    if (pendingStop != null) {
      await pendingStop;
      await _observations.close();
      return;
    }

    final pendingStart = _pendingStart;
    final shouldStop = _isActive || pendingStart != null;
    _isActive = false;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        // Disposal still stops a bridge whose start failed or was cancelled.
      }
    }
    if (shouldStop) await _stopBridge();
    await _observations.close();
  }
}

class UnavailablePoseSource implements PoseSource {
  const UnavailablePoseSource([
    this.message = 'The MoveNet camera bridge is not available.',
  ]);

  final String message;

  @override
  Stream<KineticInputFrame> get observations => const Stream.empty();

  @override
  Future<void> start() => Future<void>.error(
    PoseSourceException(PoseSourceFailure.unavailable, message),
  );

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
