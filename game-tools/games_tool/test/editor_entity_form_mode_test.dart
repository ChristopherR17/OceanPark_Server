import 'package:flutter_test/flutter_test.dart';
import 'package:games_tool/widgets/editor_entity_form_mode.dart';
import 'package:games_tool/widgets/editor_live_edit_session.dart';

void main() {
  group('EditorEntityFormMode', () {
    test('add mode exposes Add label and disables live edit', () {
      const mode = EditorEntityFormMode.add;
      expect(mode.isAdd, isTrue);
      expect(mode.isEdit, isFalse);
      expect(mode.isLiveEdit, isFalse);
      expect(mode.confirmLabel, 'Add');
    });

    test('edit mode exposes Save label and enables live edit', () {
      const mode = EditorEntityFormMode.edit;
      expect(mode.isAdd, isFalse);
      expect(mode.isEdit, isTrue);
      expect(mode.isLiveEdit, isTrue);
      expect(mode.confirmLabel, 'Save');
    });
  });

  group('createEditorLiveEditSession', () {
    test('returns null in add mode', () {
      final session = createEditorLiveEditSession<int>(
        mode: EditorEntityFormMode.add,
        initialValue: 1,
        validate: (_) => null,
        areEqual: (a, b) => a == b,
        onPersist: (_) async {},
      );
      expect(session, isNull);
    });

    test('persists changes in edit mode', () async {
      final List<int> persisted = <int>[];
      final session = createEditorLiveEditSession<int>(
        mode: EditorEntityFormMode.edit,
        initialValue: 1,
        validate: (_) => null,
        areEqual: (a, b) => a == b,
        onPersist: (value) async {
          persisted.add(value);
        },
      );
      expect(session, isNotNull);

      session!.update(2);
      await session.flush();

      expect(persisted, <int>[2]);
      session.dispose();
    });
  });
}
