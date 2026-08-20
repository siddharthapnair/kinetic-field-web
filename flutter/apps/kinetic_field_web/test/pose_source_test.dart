import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_field/kinetic_field.dart';
import 'package:kinetic_field_web/pose_source.dart';

void main() {
  test('bridge source starts and stops idempotently', () async {
    late void Function(KineticInputFrame) emit;
    var starts = 0;
    var stops = 0;
    final source = BridgePoseSource((callback, _) async {
      starts += 1;
      emit = callback;
    }, () async => stops += 1);

    await source.start();
    await source.start();
    expect(starts, 1);

    const frame = KineticInputFrame(
      sequence: 1,
      capturedAt: Duration(milliseconds: 14),
      receivedAt: Duration(milliseconds: 16),
      kind: KineticInputKind.pose,
      landmarks: <KineticLandmarkObservation>[
        KineticLandmarkObservation(
          id: KineticLandmarkId.leftWrist,
          x: 0.25,
          y: 0.4,
          confidence: 0.9,
        ),
      ],
    );
    final received = source.observations.first;
    emit(frame);
    expect(await received, same(frame));

    await source.stop();
    await source.stop();
    expect(stops, 1);

    await source.dispose();
    expect(source.start, throwsA(isA<PoseSourceException>()));
  });

  test('unavailable source reports a typed failure', () async {
    const source = UnavailablePoseSource('Bridge missing');
    expect(
      source.start,
      throwsA(
        isA<PoseSourceException>()
            .having(
              (error) => error.failure,
              'failure',
              PoseSourceFailure.unavailable,
            )
            .having((error) => error.message, 'message', 'Bridge missing'),
      ),
    );
  });

  test('dispose during start stops the bridge after it resolves', () async {
    final bridgeStarted = Completer<void>();
    var stops = 0;
    final source = BridgePoseSource(
      (_, _) => bridgeStarted.future,
      () async => stops += 1,
    );

    final starting = source.start();
    final disposing = source.dispose();
    bridgeStarted.complete();

    await expectLater(starting, throwsA(isA<PoseSourceException>()));
    await disposing;
    expect(stops, 1);
    expect(source.start, throwsA(isA<PoseSourceException>()));
  });

  test('failed start clears the pending operation for a retry', () async {
    var starts = 0;
    final source = BridgePoseSource((_, _) async {
      starts += 1;
      throw const PoseSourceException(PoseSourceFailure.failed, 'Model failed');
    }, () async {});

    await expectLater(source.start(), throwsA(isA<PoseSourceException>()));
    await expectLater(source.start(), throwsA(isA<PoseSourceException>()));
    expect(starts, 2);
    await source.dispose();
  });

  test('stop during a pending start prevents later activation', () async {
    final bridgeStarted = Completer<void>();
    var stops = 0;
    final source = BridgePoseSource(
      (_, _) => bridgeStarted.future,
      () async => stops += 1,
    );

    final starting = source.start();
    final startExpectation = expectLater(
      starting,
      throwsA(isA<PoseSourceException>()),
    );
    final stopping = source.stop();
    bridgeStarted.complete();

    await startExpectation;
    await stopping;
    expect(stops, 1);

    await source.start();
    await source.stop();
    expect(stops, 2);
    await source.dispose();
  });

  test(
    'post-start bridge failure is emitted and permits explicit restart',
    () async {
      late void Function(PoseSourceException) fail;
      final errors = <Object>[];
      var starts = 0;
      var stops = 0;
      final source = BridgePoseSource((_, onFailure) async {
        starts += 1;
        fail = onFailure;
      }, () async => stops += 1);
      final subscription = source.observations.listen(
        (_) {},
        onError: errors.add,
      );

      await source.start();
      const failure = PoseSourceException(
        PoseSourceFailure.failed,
        'Inference failed',
      );
      fail(failure);
      expect(errors, <Object>[failure]);

      await source.start();
      expect(starts, 2);
      await source.stop();
      expect(stops, 1);

      await subscription.cancel();
      await source.dispose();
    },
  );
}
