import 'package:flutter/widgets.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

class EditorLabeledField extends StatelessWidget {
  const EditorLabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CDKText(
          label,
          role: CDKTextRole.caption,
          color: cdkColors.colorText,
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
