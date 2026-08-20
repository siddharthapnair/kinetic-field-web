import 'pose_source.dart';

PoseSourceFactory? _registeredFactory;

void registerMoveNetPoseSourceFactory(PoseSourceFactory factory) {
  _registeredFactory = factory;
}

PoseSource createPlatformPoseSource() =>
    _registeredFactory?.call() ?? const UnavailablePoseSource();
