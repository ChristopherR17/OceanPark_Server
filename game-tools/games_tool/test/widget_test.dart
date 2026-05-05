// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:games_tool/app.dart';
import 'package:games_tool/app_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App renders editor layout', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final appData = AppData()
      ..storageReady = true
      ..projectsPath = '/tmp/games_tool_test_projects';

    await tester.pumpWidget(
      CupertinoApp(
        home: ChangeNotifierProvider(
          create: (_) => appData,
          child: const CDKApp(
            defaultAppearance: CDKThemeAppearance.system,
            defaultColor: 'systemBlue',
            child: App(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.textContaining('No projects found'), findsOneWidget);
    expect(find.text('+ Project'), findsOneWidget);
    expect(find.text('Add Existing Project'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
