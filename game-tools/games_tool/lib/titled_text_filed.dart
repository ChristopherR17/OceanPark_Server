import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

class TitledTextfield extends StatefulWidget {
  final String title;
  final TextEditingController? controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final TextStyle? textStyle;
  final TextStyle? placeholderStyle;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final bool autofocus;
  final TextAlign textAlign;
  final bool enabled;

  const TitledTextfield({
    super.key,
    required this.title,
    this.controller,
    this.placeholder,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.textStyle,
    this.placeholderStyle,
    this.padding,
    this.decoration,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.enabled = true,
  });

  @override
  TitledTextfieldState createState() => TitledTextfieldState();
}

class TitledTextfieldState extends State<TitledTextfield> {
  @override
  Widget build(BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: CDKText(
            widget.title,
            role: CDKTextRole.bodyStrong,
          ),
        ),
        CupertinoTextField(
          controller: widget.controller,
          placeholder: widget.placeholder,
          keyboardType: widget.keyboardType,
          obscureText: widget.obscureText,
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
          style: widget.textStyle ??
              typography.body.copyWith(color: cdkColors.colorText),
          placeholderStyle: widget.placeholderStyle ??
              typography.caption.copyWith(color: cdkColors.colorTextSecondary),
          padding: widget.padding ??
              const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          decoration: widget.decoration ??
              BoxDecoration(
                color: CDKThemeNotifier.colorTokensOf(context).background,
                borderRadius: BorderRadius.circular(4.0),
                border: Border.all(color: CDKTheme.grey200, width: 1),
              ),
          inputFormatters: widget.maxLength == null
              ? null
              : [LengthLimitingTextInputFormatter(widget.maxLength)],
          autofocus: widget.autofocus,
          textAlign: widget.textAlign,
          enabled: widget.enabled,
        ),
      ],
    );
  }
}
