import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:games_tool/widgets/editor_form_dialog_scaffold.dart';

void main() {
  Future<void> pumpScaffold(
    WidgetTester tester, {
    required bool liveEditMode,
    required String confirmLabel,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) async {
    await tester.pumpWidget(
      CDKApp(
        defaultAppearance: CDKThemeAppearance.system,
        defaultColor: 'systemBlue',
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EditorFormDialogScaffold(
            title: 'Title',
            description: 'Description',
            body: const SizedBox(width: 120, height: 40),
            confirmLabel: confirmLabel,
            confirmEnabled: true,
            onConfirm: onConfirm,
            onCancel: onCancel,
            liveEditMode: liveEditMode,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows confirm/cancel actions in add mode',
      (WidgetTester tester) async {
    int confirmCount = 0;
    int cancelCount = 0;

    await pumpScaffold(
      tester,
      liveEditMode: false,
      confirmLabel: 'Add',
      onConfirm: () {
        confirmCount += 1;
      },
      onCancel: () {
        cancelCount += 1;
      },
    );

    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(confirmCount, 1);
    expect(cancelCount, 1);
  });

  testWidgets('hides confirm/cancel actions in live edit mode',
      (WidgetTester tester) async {
    await pumpScaffold(
      tester,
      liveEditMode: true,
      confirmLabel: 'Save',
      onConfirm: () {},
      onCancel: () {},
    );

    expect(find.text('Save'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Title'), findsOneWidget);
  });
}
