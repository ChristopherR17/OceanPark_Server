class GameZoneGroup {
  static const String mainId = '__main__';
  static const String defaultMainName = 'Main';

  final String id;
  String name;
  bool collapsed;

  GameZoneGroup({
    required this.id,
    required this.name,
    this.collapsed = false,
  });

  bool get isMain => id == mainId;

  factory GameZoneGroup.main({String? name}) {
    return GameZoneGroup(
      id: mainId,
      name: (name ?? defaultMainName).trim().isEmpty
          ? defaultMainName
          : (name ?? defaultMainName).trim(),
      collapsed: false,
    );
  }

  factory GameZoneGroup.fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] as String?)?.trim() ?? '';
    final String name = (json['name'] as String?)?.trim() ?? '';
    return GameZoneGroup(
      id: id.isEmpty ? mainId : id,
      name: name.isEmpty ? defaultMainName : name,
      collapsed: (json['collapsed'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'collapsed': collapsed,
    };
  }

  @override
  String toString() {
    return 'GameZoneGroup(id: $id, name: $name, collapsed: $collapsed)';
  }
}
