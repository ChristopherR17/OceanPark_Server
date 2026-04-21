enum EditorEntityFormMode {
  add,
  edit,
}

extension EditorEntityFormModeX on EditorEntityFormMode {
  bool get isAdd => this == EditorEntityFormMode.add;

  bool get isEdit => this == EditorEntityFormMode.edit;

  bool get isLiveEdit => isEdit;

  String get confirmLabel => isAdd ? 'Add' : 'Save';
}
