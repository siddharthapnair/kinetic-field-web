import 'package:flutter/material.dart';
import 'package:kinetic_field/kinetic_field.dart';

@immutable
class PlayWorldDefinition {
  const PlayWorldDefinition({
    required this.scene,
    required this.label,
    required this.description,
    required this.prompt,
    required this.icon,
    required this.accent,
  });

  final KineticScene scene;
  final String label;
  final String description;
  final String prompt;
  final IconData icon;
  final Color accent;
}

const playWorlds = <PlayWorldDefinition>[
  PlayWorldDefinition(
    scene: KineticScene.bloom,
    label: 'Bloom',
    description: 'Grow flowers and release clouds of pollen.',
    prompt: 'Move your hands apart to open the flowers.',
    icon: Icons.local_florist_rounded,
    accent: Color(0xFFFF70B5),
  ),
  PlayWorldDefinition(
    scene: KineticScene.honeybees,
    label: 'Honeybees',
    description: 'Guide two gentle swarms through a meadow.',
    prompt: 'Guide each bee towards a flower.',
    icon: Icons.hive_rounded,
    accent: Color(0xFFFFD45A),
  ),
  PlayWorldDefinition(
    scene: KineticScene.fireflies,
    label: 'Fireflies',
    description: 'Gather lights and draw a constellation.',
    prompt: 'Hold still to place a star.',
    icon: Icons.auto_awesome_rounded,
    accent: Color(0xFFB9FF72),
  ),
  PlayWorldDefinition(
    scene: KineticScene.moonPond,
    label: 'Moon Pond',
    description: 'Guide luminous koi and settle the water.',
    prompt: 'Move slowly, then become still.',
    icon: Icons.water_rounded,
    accent: Color(0xFF68D8E8),
  ),
];

PlayWorldDefinition playWorldFor(KineticScene scene) {
  return playWorlds.firstWhere((world) => world.scene == scene);
}

String sceneSoundscapeId(KineticScene scene) => switch (scene) {
  KineticScene.bloom => 'bloom',
  KineticScene.honeybees => 'honeybees',
  KineticScene.fireflies => 'fireflies',
  KineticScene.moonPond => 'moonPond',
};
