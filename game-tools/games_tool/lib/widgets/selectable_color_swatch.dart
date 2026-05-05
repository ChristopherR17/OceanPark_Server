import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

class SelectableColorSwatch extends StatelessWidget {
  const SelectableColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.swatchSize = 20,
    this.selectionGap = 1.5,
    this.selectionStroke = 2,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double swatchSize;
  final double selectionGap;
  final double selectionStroke;

  @override
  Widget build(BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final double slotSize = swatchSize + (selectionGap + selectionStroke) * 2;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: slotSize,
        height: slotSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selected)
              Container(
                width: slotSize,
                height: slotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cdkColors.accent,
                    width: selectionStroke,
                  ),
                ),
              ),
            Container(
              width: swatchSize,
              height: swatchSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
