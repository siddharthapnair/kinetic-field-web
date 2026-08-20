import 'package:flutter/widgets.dart';

import 'fullscreen_platform.dart';
import 'kinetic_field_app.dart';
import 'pose_source_platform.dart';

void main() {
  runApp(
    KineticFieldApp(
      poseSourceFactory: createPlatformPoseSource,
      fullscreenController: createPlatformFullscreenController(),
    ),
  );
}
