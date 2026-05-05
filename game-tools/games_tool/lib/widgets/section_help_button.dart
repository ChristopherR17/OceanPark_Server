import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

class SectionHelpButton extends StatefulWidget {
  const SectionHelpButton({super.key, required this.message});

  final String message;

  @override
  State<SectionHelpButton> createState() => _SectionHelpButtonState();
}

class _SectionHelpButtonState extends State<SectionHelpButton> {
  final GlobalKey _anchorKey = GlobalKey();

  void _showHelp() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final CDKDialogController controller = CDKDialogController();

    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _anchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: CDKText(
            widget.message,
            role: CDKTextRole.body,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: _anchorKey,
        onTap: _showHelp,
        child: Icon(
          CupertinoIcons.question_circle,
          size: 15,
          color: cdkColors.colorText.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
