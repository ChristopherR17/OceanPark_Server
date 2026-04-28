class GameSprite {
  static const String defaultGroupId = '__main__';

  String name;
  String gameplayData;
  String animationId;
  int x;
  int y;
  int spriteWidth;
  int spriteHeight;
  String imageFile;
  bool flipX;
  bool flipY;
  double depth;
  String groupId;

  GameSprite({
    required this.name,
    this.gameplayData = '',
    required this.animationId,
    required this.x,
    required this.y,
    required this.spriteWidth,
    required this.spriteHeight,
    required this.imageFile,
    this.flipX = false,
    this.flipY = false,
    this.depth = 0.0,
    String? groupId,
  }) : groupId = _normalizeGroupId(groupId);

  // Constructor de fàbrica per crear una instància des d'un Map (JSON)
  factory GameSprite.fromJson(Map<String, dynamic> json) {
    final dynamic rawName = json['name'];
    final dynamic rawType = json['type'];
    final dynamic rawGameplayData = json['gameplayData'];
    final String parsedName =
        rawName is String ? rawName : (rawType is String ? rawType : '');
    return GameSprite(
      name: parsedName,
      gameplayData: rawGameplayData is String
          ? rawGameplayData
          : (rawGameplayData?.toString() ?? ''),
      animationId: (json['animationId'] as String? ?? '').trim(),
      x: json['x'] as int,
      y: json['y'] as int,
      spriteWidth: json['width'] as int,
      spriteHeight: json['height'] as int,
      imageFile: json['imageFile'] as String,
      flipX: json['flipX'] as bool? ?? false,
      flipY: json['flipY'] as bool? ?? false,
      depth: (json['depth'] as num?)?.toDouble() ?? 0.0,
      groupId: json['groupId'] as String? ?? defaultGroupId,
    );
  }

  // Convertir l'objecte a JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gameplayData': gameplayData,
      'type': name,
      'animationId': animationId,
      'x': x,
      'y': y,
      'width': spriteWidth,
      'height': spriteHeight,
      'imageFile': imageFile,
      'flipX': flipX,
      'flipY': flipY,
      'depth': depth,
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

  @override
  String toString() {
    return 'GameItem(name: $name, gameplayData: $gameplayData, animationId: $animationId, x: $x, y: $y, width: $spriteWidth, height: $spriteHeight, imageFile: $imageFile, flipX: $flipX, flipY: $flipY, depth: $depth, groupId: $groupId)';
  }
}
