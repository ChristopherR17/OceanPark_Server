import 'package:flutter/widgets.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

class EditorFormDialogScaffold extends StatelessWidget {
  const EditorFormDialogScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.body,
    required this.confirmLabel,
    required this.confirmEnabled,
    required this.onConfirm,
    required this.onCancel,
    this.liveEditMode = false,
    this.onClose,
    this.closeLabel = 'Close',
    this.onDelete,
    this.deleteLabel = 'Delete',
    this.compactActionBar = false,
    this.liveEditBottomSpacing = true,
    this.minWidth = 360,
    this.maxWidth = 520,
    this.headerTrailing,
  });

  final String title;
  final String description;
  final Widget body;
  final String confirmLabel;
  final bool confirmEnabled;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool liveEditMode;
  final VoidCallback? onClose;
  final String closeLabel;
  final VoidCallback? onDelete;
  final String deleteLabel;
  final bool compactActionBar;
  final bool liveEditBottomSpacing;
  final double minWidth;
  final double maxWidth;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: CDKText(title, role: CDKTextRole.title)),
                  if (headerTrailing != null) ...[
                    SizedBox(width: spacing.sm),
                    headerTrailing!,
                  ],
                ],
              ),
              SizedBox(height: spacing.md),
              if (description.trim().isNotEmpty) ...[
                CDKText(description, role: CDKTextRole.body),
                SizedBox(height: spacing.md),
              ],
              body,
              SizedBox(
                height: liveEditMode && !liveEditBottomSpacing
                    ? 0
                    : spacing.lg + spacing.sm,
              ),
              if (liveEditMode)
                const SizedBox.shrink()
              else if (compactActionBar)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onDelete != null) ...[
                      CDKButton(
                        style: CDKButtonStyle.destructive,
                        onPressed: onDelete,
                        child: Text(deleteLabel),
                      ),
                      SizedBox(width: spacing.md),
                    ],
                    CDKButton(
                      style: CDKButtonStyle.normal,
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    SizedBox(width: spacing.md),
                    CDKButton(
                      style: CDKButtonStyle.action,
                      enabled: confirmEnabled,
                      onPressed: onConfirm,
                      child: Text(confirmLabel),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (onDelete != null)
                      CDKButton(
                        style: CDKButtonStyle.destructive,
                        onPressed: onDelete,
                        child: Text(deleteLabel),
                      )
                    else
                      const SizedBox.shrink(),
                    Row(
                      children: [
                        CDKButton(
                          style: CDKButtonStyle.normal,
                          onPressed: onCancel,
                          child: const Text('Cancel'),
                        ),
                        SizedBox(width: spacing.md),
                        CDKButton(
                          style: CDKButtonStyle.action,
                          enabled: confirmEnabled,
                          onPressed: onConfirm,
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
