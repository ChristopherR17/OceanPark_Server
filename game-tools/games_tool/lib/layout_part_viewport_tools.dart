part of 'layout.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Viewport centering / framing helpers and canvas tool picker overlay.
extension _LayoutViewportTools on _LayoutState {
  void _queueInitialLayersViewportCenter(AppData appData, Size viewportSize) {
    if (appData.selectedSection != 'layers' &&
        appData.selectedSection != 'tilemap' &&
        appData.selectedSection != 'zones' &&
        appData.selectedSection != 'sprites' &&
        appData.selectedSection != 'paths') {
      return;
    }
    if (appData.layersViewScale != 1.0 ||
        appData.layersViewOffset != Offset.zero) {
      return;
    }
    if (_pendingLayersViewportCenter) return;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;

    _pendingLayersViewportCenter = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingLayersViewportCenter = false;
      if (!mounted) return;

      final latestAppData = Provider.of<AppData>(context, listen: false);
      if (latestAppData.selectedSection != 'layers' &&
          latestAppData.selectedSection != 'tilemap' &&
          latestAppData.selectedSection != 'zones' &&
          latestAppData.selectedSection != 'sprites' &&
          latestAppData.selectedSection != 'paths') {
        return;
      }
      if (latestAppData.layersViewScale != 1.0 ||
          latestAppData.layersViewOffset != Offset.zero) {
        return;
      }

      latestAppData.layersViewOffset = Offset(
        viewportSize.width / 2,
        viewportSize.height / 2,
      );
      latestAppData.update();
    });
  }

  void _fitLevelLayersToViewport(
    AppData appData,
    int levelIndex,
    Size viewportSize,
  ) {
    if (levelIndex < 0 || levelIndex >= appData.gameData.levels.length) {
      return;
    }
    final level = appData.gameData.levels[levelIndex];
    final double levelDepthSensitivity = level.depthSensitivity;

    Rect? worldBounds;
    for (final layer in level.layers) {
      final int rows = layer.tileMap.length;
      final int cols = rows == 0 ? 0 : layer.tileMap.first.length;
      if (rows <= 0 ||
          cols <= 0 ||
          layer.tilesWidth <= 0 ||
          layer.tilesHeight <= 0) {
        continue;
      }
      final double depthProjection = LayoutUtils.depthProjectionFactorForDepth(
        layer.depth,
        sensitivity: levelDepthSensitivity,
      );
      final Rect layerRect = Rect.fromLTWH(
        layer.x.toDouble() * depthProjection,
        layer.y.toDouble() * depthProjection,
        cols * layer.tilesWidth.toDouble() * depthProjection,
        rows * layer.tilesHeight.toDouble() * depthProjection,
      );
      worldBounds = worldBounds == null
          ? layerRect
          : worldBounds.expandToInclude(layerRect);
    }

    if (worldBounds == null ||
        worldBounds.width <= 0 ||
        worldBounds.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      appData.layersViewScale = 1.0;
      appData.layersViewOffset = Offset(
        viewportSize.width / 2,
        viewportSize.height / 2,
      );
      appData.update();
      return;
    }

    const double minScale = 0.05;
    const double maxScale = 20.0;
    const double framePaddingFactor = 0.9;
    final double scaleX =
        (viewportSize.width * framePaddingFactor) / worldBounds.width;
    final double scaleY =
        (viewportSize.height * framePaddingFactor) / worldBounds.height;
    final double fittedScale =
        (scaleX < scaleY ? scaleX : scaleY).clamp(minScale, maxScale);
    final Offset viewportCenter =
        Offset(viewportSize.width / 2, viewportSize.height / 2);
    final Offset targetOffset =
        viewportCenter - worldBounds.center * fittedScale;

    appData.layersViewScale = fittedScale;
    appData.layersViewOffset = targetOffset;
    appData.update();
  }

  void _queueSelectedLevelViewportFit(AppData appData, Size viewportSize) {
    if (appData.selectedSection != 'levels') {
      return;
    }
    final int levelIndex = appData.selectedLevel;
    if (levelIndex < 0 || levelIndex >= appData.gameData.levels.length) {
      _lastAutoFramedLevelIndex = null;
      return;
    }
    if (_lastAutoFramedLevelIndex == levelIndex) {
      return;
    }
    if (_pendingLevelsViewportFitLevelIndex == levelIndex) {
      return;
    }
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return;
    }

    _pendingLevelsViewportFitLevelIndex = levelIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingLevelsViewportFitLevelIndex == levelIndex) {
        _pendingLevelsViewportFitLevelIndex = null;
      }
      if (!mounted) {
        return;
      }
      final AppData latestAppData =
          Provider.of<AppData>(context, listen: false);
      if (latestAppData.selectedSection != 'levels') {
        return;
      }
      if (latestAppData.selectedLevel != levelIndex) {
        _queueSelectedLevelViewportFit(latestAppData, viewportSize);
        return;
      }

      _fitLevelLayersToViewport(latestAppData, levelIndex, viewportSize);
      _lastAutoFramedLevelIndex = levelIndex;
    });
  }

  MouseCursor _tilemapCursor(AppData appData) {
    if (appData.selectedSection != 'tilemap') {
      return SystemMouseCursors.basic;
    }
    if (_isDragGestureActive) {
      return SystemMouseCursors.basic;
    }
    if (appData.tilemapEraserEnabled && _isHoveringSelectedTilemapLayer) {
      return SystemMouseCursors.disappearing;
    }
    if (LayoutUtils.hasTilePatternSelection(appData) &&
        _isHoveringSelectedTilemapLayer) {
      return SystemMouseCursors.copy;
    }
    return SystemMouseCursors.basic;
  }

  Widget _buildWorldResetButton(AppData appData, Size viewportSize) {
    final bool canReset = _usesWorldViewportSection(appData.selectedSection) &&
        appData.selectedLevel >= 0 &&
        appData.selectedLevel < appData.gameData.levels.length;
    return CDKButton(
      style: CDKButtonStyle.normal,
      onPressed:
          canReset ? () => _resetWorldViewport(appData, viewportSize) : null,
      child: const Icon(CupertinoIcons.viewfinder),
    );
  }

  Widget _buildWorldTopControlsOverlay(AppData appData, Size viewportSize) {
    final bool showReset = _usesWorldViewportSection(appData.selectedSection);
    if (!showReset) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildWorldResetButton(appData, viewportSize),
          ],
        ),
      ),
    );
  }

  bool _usesWorldViewportSection(String section) {
    return section == 'levels' ||
        section == 'layers' ||
        section == 'tilemap' ||
        section == 'zones' ||
        section == 'sprites' ||
        section == 'paths' ||
        section == 'viewport';
  }

  void _resetWorldViewport(AppData appData, Size viewportSize) {
    if (!_usesWorldViewportSection(appData.selectedSection)) {
      return;
    }
    final int levelIndex = appData.selectedLevel;
    if (levelIndex < 0 || levelIndex >= appData.gameData.levels.length) {
      return;
    }
    _fitLevelLayersToViewport(appData, levelIndex, viewportSize);
    _lastAutoFramedLevelIndex = levelIndex;
  }
}
