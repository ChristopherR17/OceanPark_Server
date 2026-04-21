import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

class EditorHeaderDeleteButton extends StatefulWidget {
  const EditorHeaderDeleteButton({
    super.key,
    required this.onDelete,
    this.title = 'Delete item',
    this.message = 'Delete this item? This cannot be undone.',
    this.confirmLabel = 'Delete',
    this.cancelLabel = 'Cancel',
  });

  final VoidCallback onDelete;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<EditorHeaderDeleteButton> createState() =>
      _EditorHeaderDeleteButtonState();
}

class _EditorHeaderDeleteButtonState extends State<EditorHeaderDeleteButton> {
  final GlobalKey _anchorKey = GlobalKey();

  void _showDeleteConfirmation() {
    if (_anchorKey.currentContext == null || Overlay.maybeOf(context) == null) {
      return;
    }
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
      child: _EditorHeaderDeletePopover(
        title: widget.title,
        message: widget.message,
        confirmLabel: widget.confirmLabel,
        cancelLabel: widget.cancelLabel,
        onConfirm: () {
          controller.close();
          widget.onDelete();
        },
        onCancel: controller.close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: _anchorKey,
      padding: EdgeInsets.zero,
      minimumSize: const Size(20, 20),
      onPressed: _showDeleteConfirmation,
      child: const Icon(
        CupertinoIcons.trash,
        size: 16,
        color: CupertinoColors.systemGrey,
      ),
    );
  }
}

class _EditorHeaderDeletePopover extends StatelessWidget {
  const _EditorHeaderDeletePopover({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final colorTokens = CDKThemeNotifier.colorTokensOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CDKText(title, role: CDKTextRole.title),
            SizedBox(height: spacing.xs),
            CDKText(
              message,
              role: CDKTextRole.caption,
              color: colorTokens.colorText.withValues(alpha: 0.75),
            ),
            SizedBox(height: spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CDKButton(
                  style: CDKButtonStyle.normal,
                  onPressed: onCancel,
                  child: Text(cancelLabel),
                ),
                SizedBox(width: spacing.xs),
                CDKButton(
                  style: CDKButtonStyle.destructive,
                  onPressed: onConfirm,
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
