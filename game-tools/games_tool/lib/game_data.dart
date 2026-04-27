import 'game_animation.dart';
import 'game_list_group.dart';
import 'game_level.dart';
import 'game_media_asset.dart';
import 'game_media_group.dart';
import 'game_zone_type.dart';

class GameData {
  final String name;
  final String description;
  final List<GameLevel> levels;
  final List<GameListGroup> levelGroups;
  final List<GameMediaAsset> mediaAssets;
  final List<GameMediaGroup> mediaGroups;
  final List<GameAnimation> animations;
  final List<GameListGroup> animationGroups;
  final List<GameZoneType> zoneTypes;

  GameData({
    required this.name,
    this.description = '',
    required this.levels,
    List<GameListGroup>? levelGroups,
    List<GameMediaAsset>? mediaAssets,
    List<GameMediaGroup>? mediaGroups,
    List<GameAnimation>? animations,
    List<GameListGroup>? animationGroups,
    List<GameZoneType>? zoneTypes,
  })  : levelGroups = levelGroups ?? <GameListGroup>[GameListGroup.main()],
        mediaAssets = mediaAssets ?? <GameMediaAsset>[],
        mediaGroups = mediaGroups ?? <GameMediaGroup>[GameMediaGroup.main()],
        animations = animations ?? <GameAnimation>[],
        animationGroups =
            animationGroups ?? <GameListGroup>[GameListGroup.main()],
        zoneTypes = zoneTypes ?? <GameZoneType>[];

  // Constructor de fàbrica per crear una instància des d'un Map (JSON)
  factory GameData.fromJson(Map<String, dynamic> json) {
    final List<GameLevel> levels = (json['levels'] as List<dynamic>)
        .map((level) => GameLevel.fromJson(level))
        .toList();
    final List<GameListGroup> levelGroups =
        ((json['levelGroups'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GameListGroup.fromJson)
            .toList(growable: true);
    if (levelGroups
        .where((group) => group.id == GameListGroup.mainId)
        .isEmpty) {
      levelGroups.insert(0, GameListGroup.main());
    }
    if (levelGroups.isEmpty) {
      levelGroups.add(GameListGroup.main());
    }
    final Set<String> knownLevelGroupIds =
        levelGroups.map((group) => group.id).toSet();
    for (final level in levels) {
      final String groupId = level.groupId.trim();
      level.groupId = groupId.isEmpty ? GameListGroup.mainId : groupId;
      if (!knownLevelGroupIds.contains(level.groupId)) {
        levelGroups.add(
          GameListGroup(
            id: level.groupId,
            name: level.groupId,
          ),
        );
        knownLevelGroupIds.add(level.groupId);
      }
    }
    final List<GameMediaAsset> mediaAssets =
        ((json['mediaAssets'] as List<dynamic>?) ?? [])
            .map((item) => GameMediaAsset.fromJson(item))
            .toList(growable: true);
    final List<GameMediaGroup> mediaGroups =
        ((json['mediaGroups'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GameMediaGroup.fromJson)
            .toList(growable: true);
    if (mediaGroups
        .where((group) => group.id == GameMediaGroup.mainId)
        .isEmpty) {
      mediaGroups.insert(0, GameMediaGroup.main());
    }
    if (mediaGroups.isEmpty) {
      mediaGroups.add(GameMediaGroup.main());
    }
    final Set<String> knownMediaGroupIds =
        mediaGroups.map((group) => group.id).toSet();
    for (final asset in mediaAssets) {
      final String groupId = asset.groupId.trim();
      asset.groupId = groupId.isEmpty ? GameMediaGroup.mainId : groupId;
      if (!knownMediaGroupIds.contains(asset.groupId)) {
        mediaGroups.add(
          GameMediaGroup(
            id: asset.groupId,
            name: asset.groupId,
          ),
        );
        knownMediaGroupIds.add(asset.groupId);
      }
    }
    final List<GameAnimation> animations =
        ((json['animations'] as List<dynamic>?) ?? [])
            .map((item) => GameAnimation.fromJson(item))
            .toList(growable: true);
    final List<GameListGroup> animationGroups =
        ((json['animationGroups'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GameListGroup.fromJson)
            .toList(growable: true);
    if (animationGroups
        .where((group) => group.id == GameListGroup.mainId)
        .isEmpty) {
      animationGroups.insert(0, GameListGroup.main());
    }
    if (animationGroups.isEmpty) {
      animationGroups.add(GameListGroup.main());
    }
    final Set<String> knownAnimationGroupIds =
        animationGroups.map((group) => group.id).toSet();
    for (final animation in animations) {
      final String groupId = animation.groupId.trim();
      animation.groupId = groupId.isEmpty ? GameListGroup.mainId : groupId;
      if (!knownAnimationGroupIds.contains(animation.groupId)) {
        animationGroups.add(
          GameListGroup(
            id: animation.groupId,
            name: animation.groupId,
          ),
        );
        knownAnimationGroupIds.add(animation.groupId);
      }
    }
    final List<GameZoneType> zoneTypes =
        ((json['zoneTypes'] as List<dynamic>?) ?? [])
            .map((item) => GameZoneType.fromJson(item))
            .toList();
    _normalizeAnimationsAndSpriteBindings(
      levels: levels,
      mediaAssets: mediaAssets,
      animations: animations,
    );
    return GameData(
      name: json['name'] as String,
      description: (json['description'] as String?)?.trim() ?? '',
      levels: levels,
      levelGroups: levelGroups,
      mediaAssets: mediaAssets,
      mediaGroups: mediaGroups,
      animations: animations,
      animationGroups: animationGroups,
      zoneTypes:
          zoneTypes.isNotEmpty ? zoneTypes : _inferZoneTypesFromLevels(levels),
    );
  }

  static void _normalizeAnimationsAndSpriteBindings({
    required List<GameLevel> levels,
    required List<GameMediaAsset> mediaAssets,
    required List<GameAnimation> animations,
  }) {
    int idCounter = 1;
    final Set<String> usedIds = {};

    String nextId() {
      while (usedIds.contains('anim_$idCounter')) {
        idCounter += 1;
      }
      final String id = 'anim_$idCounter';
      usedIds.add(id);
      idCounter += 1;
      return id;
    }

    for (final animation in animations) {
      String id = animation.id.trim();
      if (id.isEmpty || usedIds.contains(id)) {
        id = nextId();
      } else {
        usedIds.add(id);
      }
      animation.id = id;
      if (animation.name.trim().isEmpty) {
        animation.name =
            GameMediaAsset.inferNameFromFileName(animation.mediaFile);
      }
      if (animation.startFrame < 0) {
        animation.startFrame = 0;
      }
      if (animation.endFrame < animation.startFrame) {
        animation.endFrame = animation.startFrame;
      }
      if (animation.fps <= 0) {
        animation.fps = 12.0;
      }
    }

    GameAnimation? animationByMediaFile(String fileName) {
      for (final animation in animations) {
        if (animation.mediaFile == fileName) {
          return animation;
        }
      }
      return null;
    }

    GameMediaAsset? mediaByFileName(String fileName) {
      for (final asset in mediaAssets) {
        if (asset.fileName == fileName) {
          return asset;
        }
      }
      return null;
    }

    bool hasAnySprite = false;
    for (final level in levels) {
      if (level.sprites.isNotEmpty) {
        hasAnySprite = true;
        break;
      }
    }

    if (animations.isEmpty && hasAnySprite) {
      final Set<String> knownMedia = {};
      for (final level in levels) {
        for (final sprite in level.sprites) {
          final String file = sprite.imageFile.trim();
          if (file.isEmpty || knownMedia.contains(file)) {
            continue;
          }
          knownMedia.add(file);
          animations.add(
            GameAnimation(
              id: nextId(),
              name: GameMediaAsset.inferNameFromFileName(file),
              mediaFile: file,
              startFrame: 0,
              endFrame: 0,
              fps: 12.0,
              loop: true,
            ),
          );
        }
      }
    }

    final Map<String, GameAnimation> byIdAfter = {
      for (final animation in animations) animation.id: animation
    };

    for (final level in levels) {
      for (final sprite in level.sprites) {
        GameAnimation? animation = byIdAfter[sprite.animationId];
        animation ??= animationByMediaFile(sprite.imageFile);
        if (animation == null && sprite.imageFile.trim().isNotEmpty) {
          animation = GameAnimation(
            id: nextId(),
            name: GameMediaAsset.inferNameFromFileName(sprite.imageFile),
            mediaFile: sprite.imageFile,
            startFrame: 0,
            endFrame: 0,
            fps: 12.0,
            loop: true,
          );
          animations.add(animation);
          byIdAfter[animation.id] = animation;
        }
        if (animation != null) {
          sprite.animationId = animation.id;
          sprite.imageFile = animation.mediaFile;
          final GameMediaAsset? asset = mediaByFileName(animation.mediaFile);
          if (asset != null && asset.tileWidth > 0 && asset.tileHeight > 0) {
            sprite.spriteWidth = asset.tileWidth;
            sprite.spriteHeight = asset.tileHeight;
          }
        }
      }
    }
  }

  static List<GameZoneType> _inferZoneTypesFromLevels(List<GameLevel> levels) {
    final Map<String, String> byName = {};
    for (final level in levels) {
      for (final zone in level.zones) {
        final String name = zone.type.trim();
        if (name.isEmpty) {
          continue;
        }
        byName.putIfAbsent(name, () => zone.color);
      }
    }
    if (byName.isEmpty) {
      return const [
        GameZoneType(name: 'Default', color: 'blue'),
      ];
    }
    return byName.entries
        .map((entry) => GameZoneType(name: entry.key, color: entry.value))
        .toList(growable: false);
  }

  // Convertir l'objecte a JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'levels': levels.map((level) => level.toJson()).toList(),
      'levelGroups': levelGroups.map((group) => group.toJson()).toList(),
      'mediaAssets': mediaAssets.map((asset) => asset.toJson()).toList(),
      'mediaGroups': mediaGroups.map((group) => group.toJson()).toList(),
      'animations': animations.map((animation) => animation.toJson()).toList(),
      'animationGroups':
          animationGroups.map((group) => group.toJson()).toList(),
      'zoneTypes': zoneTypes.map((type) => type.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'Game(name: $name, description: $description, levels: $levels, levelGroups: $levelGroups, mediaAssets: $mediaAssets, mediaGroups: $mediaGroups, animations: $animations, animationGroups: $animationGroups, zoneTypes: $zoneTypes)';
  }
}
