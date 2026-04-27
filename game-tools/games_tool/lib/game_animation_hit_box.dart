class GameAnimationHitBox {
  static const String defaultColor = 'green';
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
    'black',
    'white',
  ];

  final String id;
  final String name;
  final String color;
  final double x;
  final double y;
  final double width;
  final double height;

  const GameAnimationHitBox({
    required this.id,
    required this.name,
    required this.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory GameAnimationHitBox.fromJson(Map<String, dynamic> json) {
    final double parsedX = (json['x'] as num?)?.toDouble() ?? 0.25;
    final double parsedY = (json['y'] as num?)?.toDouble() ?? 0.25;
    final double parsedWidth =
        ((json['width'] as num?) ?? (json['w'] as num?) ?? 0.5).toDouble();
    final double parsedHeight =
        ((json['height'] as num?) ?? (json['h'] as num?) ?? 0.5).toDouble();
    return GameAnimationHitBox(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      color: _normalizeColor(json['color'] as String?),
      x: _normalizeComponent(parsedX),
      y: _normalizeComponent(parsedY),
      width: _normalizeDimension(parsedWidth),
      height: _normalizeDimension(parsedHeight),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': _normalizeColor(color),
      'x': _normalizeComponent(x),
      'y': _normalizeComponent(y),
      'width': _normalizeDimension(width),
      'height': _normalizeDimension(height),
    };
  }

  GameAnimationHitBox copyWith({
    String? id,
    String? name,
    String? color,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return GameAnimationHitBox(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  static String _normalizeColor(String? rawColor) {
    final String normalized = rawColor?.trim() ?? '';
    if (colorPalette.contains(normalized)) {
      return normalized;
    }
    return defaultColor;
  }

  static double _normalizeComponent(double value) {
    if (!value.isFinite) {
      return 0.0;
    }
    return value.clamp(0.0, 1.0);
  }

  static double _normalizeDimension(double value) {
    if (!value.isFinite) {
      return 0.01;
    }
    return value.clamp(0.01, 1.0);
  }
}
