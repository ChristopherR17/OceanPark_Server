part of 'layout.dart';

/// Sprite selection helpers: marquee, validation, drag-move.
extension _LayoutSpriteSelection on _LayoutState {
  int _firstSpriteIndexInSelection(Set<int> selection) {
    if (selection.isEmpty) {
      return -1;
    }
    final List<int> sorted = selection.toList()..sort();
    return sorted.first;
  }

  Rect? get _spritesMarqueeRect {
    if (!_isMarqueeSelectingSprites ||
        _spritesMarqueeStartLocal == null ||
        _spritesMarqueeCurrentLocal == null) {
      return null;
    }
    return Rect.fromPoints(
      _spritesMarqueeStartLocal!,
      _spritesMarqueeCurrentLocal!,
    );
  }

  void _publishSpriteSelectionToAppData(AppData appData) {
    final Set<int> next = Set<int>.from(_selectedSpriteIndices);
    if (appData.selectedSpriteIndices.length == next.length &&
        appData.selectedSpriteIndices.containsAll(next)) {
      return;
    }
    appData.selectedSpriteIndices = next;
  }

  Set<int> _validatedSpriteSelection(AppData appData, Iterable<int> input) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return <int>{};
    }
    final int spriteCount =
        appData.gameData.levels[appData.selectedLevel].sprites.length;
    final Set<int> output = <int>{};
    for (final int index in input) {
      if (index >= 0 && index < spriteCount) {
        output.add(index);
      }
    }
    return output;
  }

  Rect? _spriteScreenRect(AppData appData, GameSprite sprite) {
    final Size frameSize = LayoutUtils.spriteFrameSize(appData, sprite);
    if (frameSize.width <= 0 || frameSize.height <= 0) {
      return null;
    }
    final Rect worldRect = LayoutUtils.spriteWorldRect(
      appData,
      sprite,
      frameSize: frameSize,
    );
    final double scale = appData.scaleFactor;
    return Rect.fromLTWH(
      appData.imageOffset.dx + worldRect.left * scale,
      appData.imageOffset.dy + worldRect.top * scale,
      frameSize.width * scale,
      frameSize.height * scale,
    );
  }

  Set<int> _spriteIndicesInMarqueeRect(AppData appData, Rect marqueeRect) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return <int>{};
    }
    final List<GameSprite> sprites =
        appData.gameData.levels[appData.selectedLevel].sprites;
    final Set<int> hits = <int>{};
    for (int i = 0; i < sprites.length; i++) {
      final Rect? spriteRect = _spriteScreenRect(appData, sprites[i]);
      if (spriteRect == null) {
        continue;
      }
      if (marqueeRect.overlaps(spriteRect)) {
        hits.add(i);
      }
    }
    return hits;
  }

  bool _applySpriteMarqueeSelection(AppData appData) {
    final Rect? marqueeRect = _spritesMarqueeRect;
    if (marqueeRect == null) {
      return false;
    }
    final Set<int> hitSelection =
        _spriteIndicesInMarqueeRect(appData, marqueeRect);
    final Set<int> nextSelection = _spriteMarqueeSelectionAdditive
        ? <int>{..._marqueeBaseSpriteSelection, ...hitSelection}
        : hitSelection;
    final int preferredPrimary = hitSelection.isEmpty
        ? appData.selectedSprite
        : _firstSpriteIndexInSelection(hitSelection);
    return _setSpriteSelection(
      appData,
      nextSelection,
      preferredPrimary: preferredPrimary,
    );
  }

  bool _setSpriteSelection(
    AppData appData,
    Set<int> nextSelection, {
    int? preferredPrimary,
  }) {
    final Set<int> validated =
        _validatedSpriteSelection(appData, nextSelection);
    final int nextPrimary = validated.isEmpty
        ? -1
        : (preferredPrimary != null && validated.contains(preferredPrimary)
            ? preferredPrimary
            : _firstSpriteIndexInSelection(validated));
    final bool sameSelection =
        validated.length == _selectedSpriteIndices.length &&
            _selectedSpriteIndices.containsAll(validated);
    final bool samePrimary = appData.selectedSprite == nextPrimary;
    if (sameSelection && samePrimary) {
      return false;
    }
    _selectedSpriteIndices
      ..clear()
      ..addAll(validated);
    appData.selectedSprite = nextPrimary;
    _publishSpriteSelectionToAppData(appData);
    return true;
  }

  void _syncSpriteSelectionState(AppData appData) {
    if (appData.selectedSection != 'sprites' ||
        appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      _selectedSpriteIndices.clear();
      _spriteDragOffsetsByIndex.clear();
      _isMarqueeSelectingSprites = false;
      _spriteMarqueeSelectionAdditive = false;
      _spritesMarqueeStartLocal = null;
      _spritesMarqueeCurrentLocal = null;
      _marqueeBaseSpriteSelection = <int>{};
      _spriteSelectionLevelIndex = -1;
      _publishSpriteSelectionToAppData(appData);
      return;
    }

    if (_spriteSelectionLevelIndex != appData.selectedLevel) {
      _selectedSpriteIndices.clear();
      _spriteDragOffsetsByIndex.clear();
      _spriteSelectionLevelIndex = appData.selectedLevel;
    }

    final Set<int> validated =
        _validatedSpriteSelection(appData, appData.selectedSpriteIndices);
    if (validated.length != _selectedSpriteIndices.length ||
        !_selectedSpriteIndices.containsAll(validated)) {
      _selectedSpriteIndices
        ..clear()
        ..addAll(validated);
    }

    final bool selectedSpriteValid = validated.contains(appData.selectedSprite);
    final bool appDataSelectionValid = appData.selectedSprite >= 0 &&
        appData.selectedSprite <
            appData.gameData.levels[appData.selectedLevel].sprites.length;
    if (selectedSpriteValid || !appDataSelectionValid) {
      _publishSpriteSelectionToAppData(appData);
      return;
    }

    _selectedSpriteIndices
      ..clear()
      ..add(appData.selectedSprite);
    _publishSpriteSelectionToAppData(appData);
  }

  bool _startDraggingSelectedSprites(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    final List<GameSprite> sprites =
        appData.gameData.levels[appData.selectedLevel].sprites;
    final Set<int> selection = _validatedSpriteSelection(
      appData,
      _selectedSpriteIndices,
    );
    if (selection.isEmpty) {
      return false;
    }

    final Offset worldPos = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final Map<int, Offset> offsets = <int, Offset>{};
    for (final int spriteIndex in selection) {
      if (spriteIndex < 0 || spriteIndex >= sprites.length) {
        continue;
      }
      final GameSprite sprite = sprites[spriteIndex];
      offsets[spriteIndex] =
          worldPos - Offset(sprite.x.toDouble(), sprite.y.toDouble());
    }
    if (offsets.isEmpty) {
      return false;
    }

    appData.pushUndo();
    _spriteDragOffsetsByIndex
      ..clear()
      ..addAll(offsets);
    return true;
  }

  bool _dragSelectedSprites(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length ||
        _spriteDragOffsetsByIndex.isEmpty) {
      return false;
    }
    final Offset worldPos = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final List<GameSprite> sprites =
        appData.gameData.levels[appData.selectedLevel].sprites;
    bool changed = false;
    for (final MapEntry<int, Offset> entry
        in _spriteDragOffsetsByIndex.entries) {
      final int spriteIndex = entry.key;
      if (spriteIndex < 0 || spriteIndex >= sprites.length) {
        continue;
      }
      final GameSprite sprite = sprites[spriteIndex];
      final int newX = (worldPos.dx - entry.value.dx).round();
      final int newY = (worldPos.dy - entry.value.dy).round();
      if (newX == sprite.x && newY == sprite.y) {
        continue;
      }
      sprite.x = newX;
      sprite.y = newY;
      changed = true;
    }
    return changed;
  }
}
