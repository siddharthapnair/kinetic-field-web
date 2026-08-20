/// A platform-neutral, motion-responsive particle field for Flutter.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

part 'src/controller.dart';
part 'src/input/kinetic_input.dart';
part 'src/models.dart';
part 'src/process/motion_processor.dart';
part 'src/output/scene_strategy.dart';
part 'src/output/scene_renderer.dart';
part 'src/output/scenes/bloom_scene.dart';
part 'src/output/scenes/firefly_scene.dart';
part 'src/output/scenes/honeybee_scene.dart';
part 'src/output/scenes/moon_pond_scene.dart';
part 'src/painter.dart';
part 'src/view.dart';
