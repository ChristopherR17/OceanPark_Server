import 'game_layer.dart';
import 'game_list_group.dart';
import 'game_path.dart';
import 'game_path_binding.dart';
import 'game_zone.dart';
import 'game_zone_group.dart';
import 'game_sprite.dart';

class GameLevel {
  static const String defaultGroupId = '__main__';
  static const double defaultDepthSensitivity = 0.08;
  static const List<String> viewportColorPalette = <String>[
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
  ];
  static const String defaultViewportInitialColor = 'green';
  static const String defaultViewportPreviewColor = 'blue';

  final String name;
  final String description;
  final String gameplayData;
  final List<GameLayer> layers;
  final List<GameListGroup> layerGroups;
  final List<GameZone> zones;
  final List<GameZoneGroup> zoneGroups;
  final List<GameSprite> sprites;
  final List<GameListGroup> spriteGroups;
  final List<GameListGroup> pathGroups;
  final List<GamePath> paths;
  final List<GamePathBinding> pathBindings;
  String groupId;
  int viewportWidth;
  int viewportHeight;
  int viewportX;
  int viewportY;
  // 'letterbox', 'expand', 'stretch'
  String viewportAdaptation;
  String viewportInitialColor;
  String viewportPreviewColor;
  // Hex color for preview/runtime background (for example "#DCDCE1").
  String backgroundColorHex;
  double depthSensitivity;

  GameLevel({
    required this.name,
    required this.description,
    this.gameplayData = '',
    required this.layers,
    List<GameListGroup>? layerGroups,
    required this.zones,
    List<GameZoneGroup>? zoneGroups,
    required this.sprites,
    List<GameListGroup>? spriteGroups,
    List<GameListGroup>? pathGroups,
    List<GamePath>? paths,
    List<GamePathBinding>? pathBindings,
    this.viewportWidth = 320,
    this.viewportHeight = 180,
    this.viewportX = 0,
    this.viewportY = 0,
    this.viewportAdaptation = 'letterbox',
    String viewportInitialColor = defaultViewportInitialColor,
    String viewportPreviewColor = defaultViewportPreviewColor,
    this.backgroundColorHex = '#DCDCE1',
    double depthSensitivity = defaultDepthSensitivity,
    String? groupId,
  })  : layerGroups = layerGroups ?? <GameListGroup>[GameListGroup.main()],
        zoneGroups = zoneGroups ?? <GameZoneGroup>[GameZoneGroup.main()],
        spriteGroups = spriteGroups ?? <GameListGroup>[GameListGroup.main()],
        pathGroups = pathGroups ?? <GameListGroup>[GameListGroup.main()],
        paths = paths ?? <GamePath>[],
        pathBindings = pathBindings ?? <GamePathBinding>[],
        groupId = _normalizeGroupId(groupId),
        depthSensitivity = _normalizeDepthSensitivity(
          depthSensitivity,
        ),
        viewportInitialColor = _normalizeViewportColor(
          viewportInitialColor,
          defaultViewportInitialColor,
        ),
        viewportPreviewColor = _normalizeViewportColor(
          viewportPreviewColor,
          defaultViewportPreviewColor,
        );

  // Constructor de fàbrica per crear una instància des d'un Map (JSON)
  factory GameLevel.fromJson(Map<String, dynamic> json) {
    final dynamic rawGameplayData = json['gameplayData'];
    final List<GameListGroup> parsedLayerGroups =
        ((json['layerGroups'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GameListGroup.fromJson)
            .toList(growable: true);
    final bool hasMainLayerGroup =
        parsedLayerGroups.any((group) => group.id == GameListGroup.mainId);
    if (!hasMainLayerGroup) {
      parsedLayerGroups.insert(0, GameListGroup.main());
    }
    if (parsedLayerGroups.isEmpty) {
      parsedLayerGroups.add(GameListGroup.main());
    }

    final List<GameZoneGroup> parsedGroups =
        ((json['zoneGroups'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GameZoneGroup.fromJson)
            .toList(growable: true);
    final bool hasMainGroup =
        parsedGroups.any((group) => group.id == GameZoneGroup.mainId);
    if (!hasMainGroup) {
      parsedGroups.insert(0, GameZoneGroup.main());
    }
    if (parsedGroups.isEmpty) {
      parsedGroups.add(GameZoneGroup.main());
    }

    final List<GameListGroup> parsedSpriteGroups =
        ((json['spriteGroups'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GameListGroup.fromJson)
            .toList(growable: true);
    final bool hasMainSpriteGroup =
        parsedSpriteGroups.any((group) => group.id == GameListGroup.mainId);
    if (!hasMainSpriteGroup) {
      parsedSpriteGroups.insert(0, GameListGroup.main());
    }
    if (parsedSpriteGroups.isEmpty) {
      parsedSpriteGroups.add(GameListGroup.main());
    }
    final List<GameListGroup> parsedPathGroups =
        ((json['pathGroups'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GameListGroup.fromJson)
            .toList(growable: true);
    final bool hasMainPathGroup =
        parsedPathGroups.any((group) => group.id == GameListGroup.mainId);
    if (!hasMainPathGroup) {
      parsedPathGroups.insert(0, GameListGroup.main());
    }
    if (parsedPathGroups.isEmpty) {
      parsedPathGroups.add(GameListGroup.main());
    }

    final List<GameLayer> parsedLayers = (json['layers'] as List<dynamic>)
        .map((layer) => GameLayer.fromJson(layer))
        .toList(growable: true);
    final Set<String> knownLayerGroupIds =
        parsedLayerGroups.map((group) => group.id).toSet();
    for (final layer in parsedLayers) {
      final String trimmedGroupId = layer.groupId.trim();
      if (trimmedGroupId.isEmpty) {
        layer.groupId = GameListGroup.mainId;
        continue;
      }
      layer.groupId = trimmedGroupId;
      if (!knownLayerGroupIds.contains(trimmedGroupId)) {
        parsedLayerGroups.add(
          GameListGroup(
            id: trimmedGroupId,
            name: trimmedGroupId,
            collapsed: false,
          ),
        );
        knownLayerGroupIds.add(trimmedGroupId);
      }
    }

    final List<GameZone> parsedZones = (json['zones'] as List<dynamic>)
        .map((zone) => GameZone.fromJson(zone))
        .toList(growable: true);
    final Set<String> knownGroupIds = parsedGroups.map((g) => g.id).toSet();
    for (final zone in parsedZones) {
      final String trimmedGroupId = zone.groupId.trim();
      if (trimmedGroupId.isEmpty) {
        zone.groupId = GameZoneGroup.mainId;
        continue;
      }
      zone.groupId = trimmedGroupId;
      if (!knownGroupIds.contains(trimmedGroupId)) {
        parsedGroups.add(
          GameZoneGroup(
            id: trimmedGroupId,
            name: trimmedGroupId,
            collapsed: false,
          ),
        );
        knownGroupIds.add(trimmedGroupId);
      }
    }

    final List<GameSprite> parsedSprites = (json['sprites'] as List<dynamic>)
        .map((item) => GameSprite.fromJson(item))
        .toList(growable: true);
    final Set<String> knownSpriteGroupIds =
        parsedSpriteGroups.map((group) => group.id).toSet();
    for (final sprite in parsedSprites) {
      final String trimmedGroupId = sprite.groupId.trim();
      if (trimmedGroupId.isEmpty) {
        sprite.groupId = GameListGroup.mainId;
        continue;
      }
      sprite.groupId = trimmedGroupId;
      if (!knownSpriteGroupIds.contains(trimmedGroupId)) {
        parsedSpriteGroups.add(
          GameListGroup(
            id: trimmedGroupId,
            name: trimmedGroupId,
            collapsed: false,
          ),
        );
        knownSpriteGroupIds.add(trimmedGroupId);
      }
    }
    final List<GamePath> parsedPaths =
        ((json['paths'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GamePath.fromJson)
            .toList(growable: true);
    _normalizePathIds(parsedPaths);
    final Set<String> knownPathGroupIds =
        parsedPathGroups.map((group) => group.id).toSet();
    for (final path in parsedPaths) {
      final String trimmedGroupId = path.groupId.trim();
      if (trimmedGroupId.isEmpty) {
        path.groupId = GameListGroup.mainId;
        continue;
      }
      path.groupId = trimmedGroupId;
      if (!knownPathGroupIds.contains(trimmedGroupId)) {
        parsedPathGroups.add(
          GameListGroup(
            id: trimmedGroupId,
            name: trimmedGroupId,
            collapsed: false,
          ),
        );
        knownPathGroupIds.add(trimmedGroupId);
      }
    }
    final Set<String> pathIds = parsedPaths.map((path) => path.id).toSet();

    final List<GamePathBinding> parsedPathBindings =
        ((json['pathBindings'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GamePathBinding.fromJson)
            .where((binding) => pathIds.contains(binding.pathId))
            .toList(growable: true);
    _normalizePathBindingIds(parsedPathBindings);

    return GameLevel(
      name: json['name'] as String,
      description: json['description'] as String,
      gameplayData: rawGameplayData is String
          ? rawGameplayData
          : (rawGameplayData?.toString() ?? ''),
      layers: parsedLayers,
      layerGroups: parsedLayerGroups,
      zones: parsedZones,
      zoneGroups: parsedGroups,
      sprites: parsedSprites,
      spriteGroups: parsedSpriteGroups,
      pathGroups: parsedPathGroups,
      paths: parsedPaths,
      pathBindings: parsedPathBindings,
      groupId: json['groupId'] as String? ?? defaultGroupId,
      viewportWidth: (json['viewportWidth'] as int?) ?? 320,
      viewportHeight: (json['viewportHeight'] as int?) ?? 180,
      viewportX: (json['viewportX'] as int?) ?? 0,
      viewportY: (json['viewportY'] as int?) ?? 0,
      viewportAdaptation:
          (json['viewportAdaptation'] as String?) ?? 'letterbox',
      viewportInitialColor: _normalizeViewportColor(
        json['viewportInitialColor'] as String?,
        defaultViewportInitialColor,
      ),
      viewportPreviewColor: _normalizeViewportColor(
        json['viewportPreviewColor'] as String?,
        defaultViewportPreviewColor,
      ),
      backgroundColorHex: (json['backgroundColorHex'] as String?) ?? '#DCDCE1',
      depthSensitivity: (json['depthSensitivity'] as num?)?.toDouble() ??
          defaultDepthSensitivity,
    );
  }

  // Convertir l'objecte a JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'gameplayData': gameplayData,
      'layers': layers.map((layer) => layer.toJson()).toList(),
      'layerGroups': layerGroups.map((group) => group.toJson()).toList(),
      'zones': zones.map((zone) => zone.toJson()).toList(),
      'zoneGroups': zoneGroups.map((group) => group.toJson()).toList(),
      'sprites': sprites.map((item) => item.toJson()).toList(),
      'spriteGroups': spriteGroups.map((group) => group.toJson()).toList(),
      'pathGroups': pathGroups.map((group) => group.toJson()).toList(),
      'paths': paths.map((path) => path.toJson()).toList(),
      'pathBindings': pathBindings.map((binding) => binding.toJson()).toList(),
      'groupId': _normalizeGroupId(groupId),
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
      'viewportX': viewportX,
      'viewportY': viewportY,
      'viewportAdaptation': viewportAdaptation,
      'viewportInitialColor': _normalizeViewportColor(
        viewportInitialColor,
        defaultViewportInitialColor,
      ),
      'viewportPreviewColor': _normalizeViewportColor(
        viewportPreviewColor,
        defaultViewportPreviewColor,
      ),
      'backgroundColorHex': backgroundColorHex,
      'depthSensitivity': _normalizeDepthSensitivity(
        depthSensitivity,
      ),
    };
  }

  @override
  String toString() {
    return 'GameLevel(name: $name, description: $description, gameplayData: $gameplayData, layers: $layers, layerGroups: $layerGroups, zones: $zones, zoneGroups: $zoneGroups, sprites: $sprites, spriteGroups: $spriteGroups, pathGroups: $pathGroups, paths: $paths, pathBindings: $pathBindings, groupId: $groupId, viewport: ${viewportWidth}x$viewportHeight at ($viewportX,$viewportY) [$viewportAdaptation], background: $backgroundColorHex, depthSensitivity: $depthSensitivity)';
  }

  static String _normalizeGroupId(String? rawGroupId) {
    final String trimmed = rawGroupId?.trim() ?? '';
    if (trimmed.isEmpty) {
      return defaultGroupId;
    }
    return trimmed;
  }

  static String _normalizeViewportColor(String? rawColor, String fallback) {
    final String normalized = rawColor?.trim() ?? '';
    if (viewportColorPalette.contains(normalized)) {
      return normalized;
    }
    return fallback;
  }

  static double _normalizeDepthSensitivity(double raw) {
    if (!raw.isFinite) {
      return defaultDepthSensitivity;
    }
    if (raw < 0) {
      return 0;
    }
    return raw;
  }

  static void _normalizePathIds(List<GamePath> paths) {
    int pathIdCounter = 1;
    final Set<String> usedIds = <String>{};

    String nextPathId() {
      while (usedIds.contains('path_$pathIdCounter')) {
        pathIdCounter += 1;
      }
      final String id = 'path_$pathIdCounter';
      usedIds.add(id);
      pathIdCounter += 1;
      return id;
    }

    for (final GamePath path in paths) {
      final String raw = path.id.trim();
      if (raw.isEmpty || usedIds.contains(raw)) {
        path.id = nextPathId();
      } else {
        path.id = raw;
        usedIds.add(raw);
      }
      if (path.name.trim().isEmpty) {
        path.name = path.id;
      }
    }
  }

  static void _normalizePathBindingIds(List<GamePathBinding> bindings) {
    int bindingIdCounter = 1;
    final Set<String> usedIds = <String>{};

    String nextBindingId() {
      while (usedIds.contains('path_binding_$bindingIdCounter')) {
        bindingIdCounter += 1;
      }
      final String id = 'path_binding_$bindingIdCounter';
      usedIds.add(id);
      bindingIdCounter += 1;
      return id;
    }

    for (final GamePathBinding binding in bindings) {
      final String raw = binding.id.trim();
      if (raw.isEmpty || usedIds.contains(raw)) {
        binding.id = nextBindingId();
      } else {
        binding.id = raw;
        usedIds.add(raw);
      }
    }
  }
}
