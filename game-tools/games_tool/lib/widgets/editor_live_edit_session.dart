import 'edit_session.dart';
import 'editor_entity_form_mode.dart';

EditSession<T>? createEditorLiveEditSession<T>({
  required EditorEntityFormMode mode,
  required T initialValue,
  required String? Function(T value) validate,
  required bool Function(T a, T b) areEqual,
  required Future<void> Function(T value)? onPersist,
}) {
  if (!mode.isLiveEdit || onPersist == null) {
    return null;
  }
  return EditSession<T>(
    initialValue: initialValue,
    validate: validate,
    onPersist: onPersist,
    areEqual: areEqual,
  );
}

void queueEditorLiveEditUpdate<T>({
  required EditorEntityFormMode mode,
  required EditSession<T>? session,
  required T value,
}) {
  if (!mode.isLiveEdit) {
    return;
  }
  session?.update(value);
}
