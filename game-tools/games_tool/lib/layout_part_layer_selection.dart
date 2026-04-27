part of 'layout.dart';

/// Layer selection, marquee, dragging, and deletion.
extension _LayoutLayerSelection on _LayoutState {
  bool _isLayerSelectionModifierPressed() {
    return _isPlatformShortcutModifierPressed();
  }

  Offset _depthProjectionImageOffsetForLayer(AppData appData, GameLayer layer) {
    return appData.imageOffset;
  }

  double _depthProjectionScaleForLayer(AppData appData, GameLayer layer) {
    final double depthProjection = LayoutUtils.depthProjectionFactorForDepth(
      layer.depth,
      sensitivity: LayoutUtils.depthSensitivityForSelectedLevel(appData),
    );
    final double baseScale =
        appData.scaleFactor.isFinite && appData.scaleFactor > 0
            ? appData.scaleFactor
            : 1.0;
    return baseScale * depthProjection;
  }

  int _firstLayerIndexInSelection(Set<int> selection) {
    if (selection.isEmpty) {
      return -1;
    }
    final List<int> sorted = selection.toList()..sort();
    return sorted.first;
  }

  Rect? get _layersMarqueeRect {
    if (!_isMarqueeSelectingLayers ||
        _layersMarqueeStartLocal == null ||
        _layersMarqueeCurrentLocal == null) {
      return null;
    }
    return Rect.fromPoints(
        _layersMarqueeStartLocal!, _layersMarqueeCurrentLocal!);
  }

  void _publishLayerSelectionToAppData(AppData appData) {
    final Set<int> next = Set<int>.from(_selectedLayerIndices);
    if (appData.selectedLayerIndices.length == next.length &&
        appData.selectedLayerIndices.containsAll(next)) {
      return;
    }
    appData.selectedLayerIndices = next;
  }

  Rect? _layerScreenRect(AppData appData, GameLayer layer) {
    if (!layer.visible ||
        layer.tileMap.isEmpty ||
        layer.tileMap.first.isEmpty ||
        layer.tilesWidth <= 0 ||
        layer.tilesHeight <= 0) {
      return null;
    }
    final int rows = layer.tileMap.length;
    final int cols = layer.tileMap.first.length;
    final Offset depthProjectionOffset =
        _depthProjectionImageOffsetForLayer(appData, layer);
    final double scale = _depthProjectionScaleForLayer(appData, layer);
    final double left = depthProjectionOffset.dx + layer.x * scale;
    final double top = depthProjectionOffset.dy + layer.y * scale;
    final double width = cols * layer.tilesWidth * scale;
    final double height = rows * layer.tilesHeight * scale;
    if (width <= 0 || height <= 0) {
      return null;
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  Set<int> _layerIndicesInMarqueeRect(AppData appData, Rect marqueeRect) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return <int>{};
    }
    final List<GameLayer> layers =
        appData.gameData.levels[appData.selectedLevel].layers;
    final Set<int> hits = <int>{};
    for (int i = 0; i < layers.length; i++) {
      final Rect? layerRect = _layerScreenRect(appData, layers[i]);
      if (layerRect == null) {
        continue;
      }
      if (marqueeRect.overlaps(layerRect)) {
        hits.add(i);
      }
    }
    return hits;
  }

  bool _applyMarqueeSelection(AppData appData) {
    final Rect? marqueeRect = _layersMarqueeRect;
    if (marqueeRect == null) {
      return false;
    }
    final Set<int> hitSelection =
        _layerIndicesInMarqueeRect(appData, marqueeRect);
    final Set<int> nextSelection = _marqueeSelectionAdditive
        ? <int>{..._marqueeBaseLayerSelection, ...hitSelection}
        : hitSelection;
    final int preferredPrimary = hitSelection.isEmpty
        ? appData.selectedLayer
        : _firstLayerIndexInSelection(hitSelection);
    return _setLayerSelection(
      appData,
      nextSelection,
      preferredPrimary: preferredPrimary,
    );
  }

  Set<int> _validatedLayerSelection(AppData appData, Iterable<int> input) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return <int>{};
    }
    final int layerCount =
        appData.gameData.levels[appData.selectedLevel].layers.length;
    final Set<int> output = <int>{};
    for (final int index in input) {
      if (index >= 0 && index < layerCount) {
        output.add(index);
      }
    }
    return output;
  }

  Set<int> _selectedLayersForCurrentLevel(AppData appData) {
    return _validatedLayerSelection(appData, appData.selectedLayerIndices);
  }

  bool _hasMultipleLayersSelected(AppData appData) {
    return _selectedLayersForCurrentLevel(appData).length > 1;
  }

  bool _setLayerSelection(
    AppData appData,
    Set<int> nextSelection, {
    int? preferredPrimary,
  }) {
    final Set<int> validated = _validatedLayerSelection(appData, nextSelection);
    final int nextPrimary = validated.isEmpty
        ? -1
        : (preferredPrimary != null && validated.contains(preferredPrimary)
            ? preferredPrimary
            : _firstLayerIndexInSelection(validated));
    final bool sameSelection =
        validated.length == _selectedLayerIndices.length &&
            _selectedLayerIndices.containsAll(validated);
    final bool samePrimary = appData.selectedLayer == nextPrimary;
    if (sameSelection && samePrimary) {
      return false;
    }
    _selectedLayerIndices
      ..clear()
      ..addAll(validated);
    appData.selectedLayer = nextPrimary;
    _publishLayerSelectionToAppData(appData);
    return true;
  }

  void _syncLayerSelectionState(AppData appData) {
    if ((appData.selectedSection != 'layers' &&
            appData.selectedSection != 'tilemap') ||
        appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      _selectedLayerIndices.clear();
      _layerDragOffsetsByIndex.clear();
      _isMarqueeSelectingLayers = false;
      _layersMarqueeStartLocal = null;
      _layersMarqueeCurrentLocal = null;
      _marqueeBaseLayerSelection = <int>{};
      _layerSelectionLevelIndex = -1;
      _publishLayerSelectionToAppData(appData);
      return;
    }

    if (_layerSelectionLevelIndex != appData.selectedLevel) {
      _selectedLayerIndices.clear();
      _layerDragOffsetsByIndex.clear();
      _layerSelectionLevelIndex = appData.selectedLevel;
    }

    final Set<int> validated =
        _validatedLayerSelection(appData, appData.selectedLayerIndices);
    if (validated.length != _selectedLayerIndices.length ||
        !_selectedLayerIndices.containsAll(validated)) {
      _selectedLayerIndices
        ..clear()
        ..addAll(validated);
    }

    final bool selectedLayerValid = validated.contains(appData.selectedLayer);
    final bool appDataSelectionValid = appData.selectedLayer >= 0 &&
        appData.selectedLayer <
            appData.gameData.levels[appData.selectedLevel].layers.length;
    if (selectedLayerValid || !appDataSelectionValid) {
      _publishLayerSelectionToAppData(appData);
      return;
    }

    _selectedLayerIndices
      ..clear()
      ..add(appData.selectedLayer);
    _publishLayerSelectionToAppData(appData);
  }

  bool _startDraggingSelectedLayers(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final Set<int> selection = _validatedLayerSelection(
      appData,
      _selectedLayerIndices,
    );
    if (selection.isEmpty) {
      return false;
    }

    final Map<int, Offset> offsets = <int, Offset>{};
    for (final int layerIndex in selection) {
      final GameLayer layer = level.layers[layerIndex];
      if (!layer.visible) {
        continue;
      }
      final Offset worldPos = LayoutUtils.translateCoords(
        localPosition,
        _depthProjectionImageOffsetForLayer(appData, layer),
        _depthProjectionScaleForLayer(appData, layer),
      );
      offsets[layerIndex] =
          worldPos - Offset(layer.x.toDouble(), layer.y.toDouble());
    }
    if (offsets.isEmpty) {
      return false;
    }

    appData.pushUndo();
    _layerDragOffsetsByIndex
      ..clear()
      ..addAll(offsets);
    return true;
  }

  bool _dragSelectedLayers(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length ||
        _layerDragOffsetsByIndex.isEmpty) {
      return false;
    }
    final List<GameLayer> layers =
        appData.gameData.levels[appData.selectedLevel].layers;
    bool changed = false;

    for (final MapEntry<int, Offset> entry
        in _layerDragOffsetsByIndex.entries) {
      final int layerIndex = entry.key;
      if (layerIndex < 0 || layerIndex >= layers.length) {
        continue;
      }
      final GameLayer oldLayer = layers[layerIndex];
      final Offset worldPos = LayoutUtils.translateCoords(
        localPosition,
        _depthProjectionImageOffsetForLayer(appData, oldLayer),
        _depthProjectionScaleForLayer(appData, oldLayer),
      );
      final int newX = (worldPos.dx - entry.value.dx).round();
      final int newY = (worldPos.dy - entry.value.dy).round();
      if (newX == oldLayer.x && newY == oldLayer.y) {
        continue;
      }
      layers[layerIndex] = GameLayer(
        name: oldLayer.name,
        gameplayData: oldLayer.gameplayData,
        x: newX,
        y: newY,
        depth: oldLayer.depth,
        tilesSheetFile: oldLayer.tilesSheetFile,
        tilesWidth: oldLayer.tilesWidth,
        tilesHeight: oldLayer.tilesHeight,
        tileMap: oldLayer.tileMap,
        visible: oldLayer.visible,
        groupId: oldLayer.groupId,
      );
      changed = true;
    }

    return changed;
  }

  Future<void> _confirmAndDeleteSelectedLayers(AppData appData) async {
    if (!mounted ||
        appData.selectedSection != 'layers' ||
        appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }

    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final List<int> selected = _validatedLayerSelection(
      appData,
      _selectedLayerIndices,
    ).toList()
      ..sort();
    if (selected.isEmpty) {
      final int selectedLayer = appData.selectedLayer;
      if (selectedLayer < 0 || selectedLayer >= level.layers.length) {
        return;
      }
      selected.add(selectedLayer);
    }

    final String message;
    if (selected.length == 1) {
      final String rawName = level.layers[selected.first].name.trim();
      final String displayName =
          rawName.isEmpty ? 'Layer ${selected.first + 1}' : rawName;
      message = 'Delete "$displayName"? This cannot be undone.';
    } else {
      message =
          'Delete ${selected.length} selected layers? This cannot be undone.';
    }

    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: selected.length == 1 ? 'Delete layer' : 'Delete layers',
      message: message,
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );

    if (confirmed != true || !mounted) {
      return;
    }

    appData.pushUndo();
    for (int i = selected.length - 1; i >= 0; i--) {
      level.layers.removeAt(selected[i]);
    }
    _selectedLayerIndices.clear();
    _layerDragOffsetsByIndex.clear();
    _isMarqueeSelectingLayers = false;
    _layersMarqueeStartLocal = null;
    _layersMarqueeCurrentLocal = null;
    _marqueeBaseLayerSelection = <int>{};
    appData.selectedLayer = -1;
    _publishLayerSelectionToAppData(appData);
    appData.update();
    await _autoSaveIfPossible(appData);
  }
}
