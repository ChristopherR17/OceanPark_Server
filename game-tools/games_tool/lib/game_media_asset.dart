class GameMediaAsset {
  static const String defaultSelectionColorHex = '#FFCC00';
  static const String defaultGroupId = '__main__';

  String name;
  String fileName;
  String mediaType;
  int tileWidth;
  int tileHeight;
  String selectionColorHex;
  String groupId;

  GameMediaAsset({
    required String? name,
    required this.fileName,
    required this.mediaType,
    required this.tileWidth,
    required this.tileHeight,
    String? selectionColorHex,
    String? groupId,
  })  : name = _normalizeName(name, fileName),
        selectionColorHex = _normalizeSelectionColorHex(selectionColorHex),
        groupId = _normalizeGroupId(groupId);

  static const List<String> validTypes = [
    'image',
    'tileset',
    'spritesheet',
    'atlas',
  ];

  /// Whether this asset uses a tile/cell grid.
  bool get hasTileGrid =>
      mediaType == 'tileset' ||
      mediaType == 'spritesheet' ||
      mediaType == 'atlas';

  factory GameMediaAsset.fromJson(Map<String, dynamic> json) {
    final String parsedType =
        (json['mediaType'] as String? ?? 'image').trim().toLowerCase();
    final String normalizedType =
        validTypes.contains(parsedType) ? parsedType : 'image';

    return GameMediaAsset(
      name: json['name'] as String?,
      fileName: json['fileName'] as String,
      mediaType: normalizedType,
      tileWidth: (json['tileWidth'] as num?)?.toInt() ?? 32,
      tileHeight: (json['tileHeight'] as num?)?.toInt() ?? 32,
      selectionColorHex: json['selectionColorHex'] as String?,
      groupId: json['groupId'] as String? ?? defaultGroupId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': _normalizeName(name, fileName),
      'fileName': fileName,
      'mediaType': mediaType,
      'tileWidth': tileWidth,
      'tileHeight': tileHeight,
      'selectionColorHex': _normalizeSelectionColorHex(selectionColorHex),
      'groupId': _normalizeGroupId(groupId),
    };
  }

  static String _normalizeSelectionColorHex(String? raw) {
    if (raw == null) {
      return defaultSelectionColorHex;
    }
    final String cleaned = raw.trim().replaceFirst('#', '').toUpperCase();
    final RegExp sixHex = RegExp(r'^[0-9A-F]{6}$');
    if (!sixHex.hasMatch(cleaned)) {
      return defaultSelectionColorHex;
    }
    return '#$cleaned';
  }

  static String inferNameFromFileName(String fileName) {
    if (fileName.trim().isEmpty) {
      return 'Media';
    }
    final String segment = fileName.split(RegExp(r'[\\/]')).last;
    if (segment.trim().isEmpty) {
      return 'Media';
    }
    final int dotIndex = segment.lastIndexOf('.');
    final String noExtension =
        dotIndex > 0 ? segment.substring(0, dotIndex) : segment;
    final String trimmed = noExtension.trim();
    return trimmed.isEmpty ? segment.trim() : trimmed;
  }

  static String _normalizeName(String? rawName, String fileName) {
    final String trimmed = rawName?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return inferNameFromFileName(fileName);
  }

  static String _normalizeGroupId(String? rawGroupId) {
    final String trimmed = rawGroupId?.trim() ?? '';
    if (trimmed.isEmpty) {
      return defaultGroupId;
    }
    return trimmed;
  }
}
