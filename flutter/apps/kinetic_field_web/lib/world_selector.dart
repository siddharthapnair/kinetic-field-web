import 'package:flutter/material.dart';
import 'package:kinetic_field/kinetic_field.dart';

import 'play_world.dart';

class WorldSelector extends StatelessWidget {
  const WorldSelector({
    required this.selected,
    required this.onSelected,
    required this.compact,
    this.showDescriptions = false,
    super.key,
  });

  final KineticScene selected;
  final ValueChanged<KineticScene> onSelected;
  final bool compact;
  final bool showDescriptions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Choose a Kinetic Field play world',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: showDescriptions ? 760 : 620),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: compact ? 2 : 4,
            mainAxisExtent: showDescriptions ? 112 : 64,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: playWorlds.length,
          itemBuilder: (context, index) {
            final world = playWorlds[index];
            final isSelected = world.scene == selected;
            return Semantics(
              button: true,
              selected: isSelected,
              label:
                  '${world.label}, ${isSelected ? 'selected, ' : ''}${index + 1} of ${playWorlds.length}',
              child: Material(
                color: isSelected
                    ? world.accent.withValues(alpha: 0.14)
                    : const Color(0xFF101722),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected
                        ? world.accent.withValues(alpha: 0.72)
                        : const Color(0xFF8293A1).withValues(alpha: 0.30),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(world.scene),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: showDescriptions ? 12 : 9,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: showDescriptions
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          mainAxisSize: showDescriptions
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          children: <Widget>[
                            Icon(world.icon, color: world.accent, size: 21),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                world.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFF1F5F7),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (showDescriptions) ...<Widget>[
                          const SizedBox(height: 7),
                          Text(
                            world.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA7B5C1),
                              fontSize: 11,
                              height: 1.28,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
