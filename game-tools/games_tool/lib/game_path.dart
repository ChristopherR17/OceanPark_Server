class GamePathPoint {
  int x;
  int y;

  GamePathPoint({
    required this.x,
    required this.y,
  });

  factory GamePathPoint.fromJson(Map<String, dynamic> json) {
    return GamePathPoint(
      x: (json['x'] as num?)?.round() ?? 0,
      y: (json['y'] as num?)?.round() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
    };
  }
}

class GamePath {
  static const String defaultGroupId = '__main__';
  static const List<String> colorPalette = <String>[
    'red',
    'deepOrange',
    'orange',
    'amber',
    'yellow',
    'lime',
    'lightGreen',
    'green',
    'teal',
    'cyan',
    'lightBlue',
    'blue',
    'indigo',
    'purple',
    'pink',
  ];
  static const String defaultColor = 'purple';

  String id;
  String name;
  List<GamePathPoint> points;
  String groupId;
  String color;

  GamePath({
    required this.id,
    required this.name,
    required this.points,
    String? color,
    String? groupId,
  })  : color = _normalizeColor(color),
        groupId = _normalizeGroupId(groupId);

  factory GamePath.fromJson(Map<String, dynamic> json) {
    final List<GamePathPoint> parsedPoints =
        ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GamePathPoint.fromJson)
            .toList(growable: true);
    return GamePath(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      points: parsedPoints,
      color: json['color'] as String?,
      groupId: json['groupId'] as String? ?? defaultGroupId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.trim(),
      'name': name,
      'points': points.map((point) => point.toJson()).toList(growable: false),
      'color': _normalizeColor(color),
      'groupId': _normalizeGroupId(groupId),
    };
  }

  static String _normalizeGroupId(String? rawGroupId) {
    final String trimmed = rawGroupId?.trim() ?? '';
    if (trimmed.isEmpty) {
      return defaultGroupId;
    }
    return trimmed;
  }

  static String _normalizeColor(String? rawColor) {
    final String trimmed = rawColor?.trim() ?? '';
    if (colorPalette.contains(trimmed)) {
      return trimmed;
    }
    return defaultColor;
  }
}
