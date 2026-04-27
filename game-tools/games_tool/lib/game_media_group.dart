class GameMediaGroup {
  static const String mainId = '__main__';
  static const String defaultMainName = 'Main';

  final String id;
  String name;
  bool collapsed;

  GameMediaGroup({
    required this.id,
    required this.name,
    this.collapsed = false,
  });

  factory GameMediaGroup.main({String? name}) {
    final String nextName = (name ?? defaultMainName).trim();
    return GameMediaGroup(
      id: mainId,
      name: nextName.isEmpty ? defaultMainName : nextName,
      collapsed: false,
    );
  }

  factory GameMediaGroup.fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] as String?)?.trim() ?? '';
    final String name = (json['name'] as String?)?.trim() ?? '';
    return GameMediaGroup(
      id: id.isEmpty ? mainId : id,
      name: name.isEmpty ? defaultMainName : name,
      collapsed: (json['collapsed'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'collapsed': collapsed,
    };
  }
}
