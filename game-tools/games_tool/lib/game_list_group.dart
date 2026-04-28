class GameListGroup {
  static const String mainId = '__main__';
  static const String defaultMainName = 'Main';

  final String id;
  String name;
  bool collapsed;

  GameListGroup({
    required this.id,
    required this.name,
    this.collapsed = false,
  });

  factory GameListGroup.main({String? name}) {
    final String nextName = (name ?? defaultMainName).trim();
    return GameListGroup(
      id: mainId,
      name: nextName.isEmpty ? defaultMainName : nextName,
      collapsed: false,
    );
  }

  factory GameListGroup.fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] as String?)?.trim() ?? '';
    final String name = (json['name'] as String?)?.trim() ?? '';
    return GameListGroup(
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
