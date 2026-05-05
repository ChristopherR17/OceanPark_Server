class GameLayer {
  static const String defaultGroupId = '__main__';

  final String name;
  final String gameplayData;
  final int x;
  final int y;
  final double depth;
  final String tilesSheetFile;
  final int tilesWidth;
  final int tilesHeight;
  final List<List<int>> tileMap;
  final bool visible;
  String groupId;

  GameLayer({
    required this.name,
    this.gameplayData = '',
    required this.x,
    required this.y,
    required this.depth,
    required this.tilesSheetFile,
    required this.tilesWidth,
    required this.tilesHeight,
    required this.tileMap,
    required this.visible,
    String? groupId,
  }) : groupId = _normalizeGroupId(groupId);

  // Constructor de fàbrica per crear una instància des d'un Map (JSON)
  factory GameLayer.fromJson(Map<String, dynamic> json) {
    final dynamic rawDepth = json['depth'];
    final dynamic rawGameplayData = json['gameplayData'];
    final double parsedDepth = rawDepth is num ? rawDepth.toDouble() : 0.0;
    return GameLayer(
      name: json['name'] as String,
      gameplayData: rawGameplayData is String
          ? rawGameplayData
          : (rawGameplayData?.toString() ?? ''),
      x: json['x'] as int,
      y: json['y'] as int,
      depth: parsedDepth,
      tilesSheetFile: json['tilesSheetFile'] as String,
      tilesWidth: json['tilesWidth'] as int,
      tilesHeight: json['tilesHeight'] as int,
      tileMap: (json['tileMap'] as List<dynamic>)
          .map((row) => List<int>.from(row))
          .toList(),
      visible: json['visible'] as bool,
      groupId: json['groupId'] as String? ?? defaultGroupId,
    );
  }

  // Convertir l'objecte a JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gameplayData': gameplayData,
      'x': x,
      'y': y,
      'depth': depth,
      'tilesSheetFile': tilesSheetFile,
      'tilesWidth': tilesWidth,
      'tilesHeight': tilesHeight,
      'tileMap': tileMap.map((row) => row.toList()).toList(),
      'visible': visible,
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
    return 'GameLayer(name: $name, gameplayData: $gameplayData, x: $x, y: $y, depth: $depth, tilesSheetFile: $tilesSheetFile, tilesWidth: $tilesWidth, tilesHeight: $tilesHeight, tileMap: $tileMap, visible: $visible, groupId: $groupId)';
  }
}
