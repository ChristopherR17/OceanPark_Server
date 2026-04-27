class GameZoneType {
  final String name;
  final String color;

  const GameZoneType({
    required this.name,
    required this.color,
  });

  factory GameZoneType.fromJson(Map<String, dynamic> json) {
    return GameZoneType(
      name: json['name'] as String,
      color: json['color'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'color': color,
    };
  }
}
