import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kinetic_field/kinetic_field.dart';

void main() => runApp(const KineticFieldModuleApp());

/// Platform channel used by Android and iOS hosts to feed normalised motion.
const kineticFieldMotionChannel = MethodChannel(
  'ai.zeuron.kinetic_field/motion',
);

/// Minimal add-to-app entry point for native Android and iOS hosts.
///
/// Native applications can present this route as a full-screen Flutter view,
/// or depend on `kinetic_field` directly to place [KineticFieldView] inside a
/// larger Flutter surface.
class KineticFieldModuleApp extends StatefulWidget {
  const KineticFieldModuleApp({this.controller, super.key});

  /// Optional controller for Flutter-native composition and testing.
  final KineticFieldController? controller;

  @override
  State<KineticFieldModuleApp> createState() => _KineticFieldModuleAppState();
}

class _KineticFieldModuleAppState extends State<KineticFieldModuleApp> {
  late final KineticFieldController _controller;
  late final bool _ownsController;
  bool _calmApplied = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? KineticFieldController();
    kineticFieldMotionChannel.setMethodCallHandler(_handleNativeMotion);
  }

  Future<Object?> _handleNativeMotion(MethodCall call) async {
    switch (call.method) {
      case 'updateMotion':
        final arguments = call.arguments;
        if (arguments is! Map) {
          throw PlatformException(
            code: 'invalid_motion',
            message: 'updateMotion expects a map of normalised values.',
          );
        }
        _controller.updateMotion(
          MotionSample(
            x: _number(arguments, 'x', required: true),
            y: _number(arguments, 'y', required: true),
            vx: _number(arguments, 'vx'),
            vy: _number(arguments, 'vy'),
            energy: _number(arguments, 'energy'),
            confidence: _number(arguments, 'confidence', fallback: 1),
            timestamp: Duration(
              milliseconds: _number(arguments, 'timestampMs').round(),
            ),
          ),
        );
        return null;
      case 'resetMotion':
        _controller.resetMotion();
        return null;
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  double _number(
    Map<dynamic, dynamic> arguments,
    String key, {
    double fallback = 0,
    bool required = false,
  }) {
    final value = arguments[key];
    if (value is num) return value.toDouble();
    if (!required && value == null) return fallback;
    throw PlatformException(
      code: 'invalid_motion',
      message: '$key must be numeric.',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_calmApplied) {
      _calmApplied = true;
      _controller.updateSettings(_controller.settings.copyWith(calm: true));
    }
  }

  @override
  void dispose() {
    kineticFieldMotionChannel.setMethodCallHandler(null);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinetic Field',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF050810),
        body: KineticFieldView(
          controller: _controller,
          semanticLabel: 'A particle field shaped by pointer movement',
        ),
      ),
    );
  }
}
