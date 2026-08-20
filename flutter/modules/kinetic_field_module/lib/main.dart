import 'package:flutter/material.dart';
import 'package:kinetic_field/kinetic_field.dart';

import 'native_input_channel.dart';

void main() => runApp(const KineticFieldModuleApp());

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
  late final NativeKineticFieldInputChannel _nativeInput;
  bool _calmApplied = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? KineticFieldController();
    _nativeInput = NativeKineticFieldInputChannel(controller: _controller)
      ..attach();
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
    _nativeInput.detach();
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
