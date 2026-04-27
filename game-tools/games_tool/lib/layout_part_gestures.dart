part of 'layout.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Gesture handlers extracted from the build() GestureDetector closures.
extension _LayoutGestures on _LayoutState {
  Future<void> _handlePanStart(
      AppData appData, DragStartDetails details) async {
    if (!_isPointerDown) {
      return;
    }
    if (!_isDragGestureActive) {
      setState(() {
        _isDragGestureActive = true;
      });
    }
    appData.dragging = true;
    appData.dragStartDetails = details;
    if (appData.selectedSection == "levels") {
      // Levels section is preview-only: always pan.
    } else if (appData.selectedSection == "paths") {
      _didModifyPathDuringGesture = false;
      _isDraggingPathPoint = false;
      _draggingPathPointIndex = -1;
      final int hitPointIndex = LayoutUtils.pathPointIndexFromPosition(
        appData,
        details.localPosition,
      );
      if (hitPointIndex != -1) {
        appData.pushUndo();
        _isDraggingPathPoint = true;
        _draggingPathPointIndex = hitPointIndex;
      }
    } else if (appData.selectedSection == "viewport") {
      _isDraggingViewport = false;
      _isResizingViewport = false;
      LayoutUtils.ensureViewportPreviewInitialized(
        appData,
      );
      if (LayoutUtils.isPointInViewportResizeHandle(
          appData, details.localPosition)) {
        _isResizingViewport = true;
        LayoutUtils.startResizeViewportFromPosition(
          appData,
          details.localPosition,
        );
      } else if (LayoutUtils.isPointInViewportRect(
          appData, details.localPosition)) {
        _isDraggingViewport = true;
        LayoutUtils.startDragViewportFromPosition(
          appData,
          details.localPosition,
        );
      }
    } else if (appData.selectedSection == "layers") {
      _isDraggingLayer = false;
      _didModifyLayerDuringGesture = false;
      _layerDragOffsetsByIndex.clear();
      final int hitLayerIndex = LayoutUtils.selectLayerFromPosition(
        appData,
        details.localPosition,
      );
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      if (hitLayerIndex == -1) {
        if (!additiveSelection) {
          return;
        }
        _isMarqueeSelectingLayers = true;
        _marqueeSelectionAdditive = additiveSelection;
        _layersMarqueeStartLocal = details.localPosition;
        _layersMarqueeCurrentLocal = details.localPosition;
        _marqueeBaseLayerSelection = additiveSelection
            ? <int>{
                ..._selectedLayerIndices,
              }
            : <int>{};
        final bool selectionChanged = _applyMarqueeSelection(appData);
        setState(() {});
        if (selectionChanged) {
          appData.update();
        }
        return;
      }
      if (additiveSelection) {
        return;
      }
      bool selectionChanged = false;
      if (!_selectedLayerIndices.contains(hitLayerIndex)) {
        selectionChanged = _setLayerSelection(
          appData,
          <int>{hitLayerIndex},
          preferredPrimary: hitLayerIndex,
        );
      }
      if (_startDraggingSelectedLayers(
        appData,
        details.localPosition,
      )) {
        _isDraggingLayer = true;
      }
      if (selectionChanged) {
        appData.update();
      }
    } else if (appData.selectedSection == "tilemap") {
      _consumeTilemapTapUp = false;
      if (_isLayerSelectionModifierPressed()) {
        _isPaintingTilemap = false;
        _didModifyTilemapDuringGesture = false;
        return;
      }
      if (_hasMultipleLayersSelected(
        appData,
      )) {
        _isPaintingTilemap = false;
        _didModifyTilemapDuringGesture = false;
        return;
      }
      final bool useEraser = appData.tilemapEraserEnabled;
      final bool hasTileSelection =
          LayoutUtils.hasTilePatternSelection(appData);
      final bool startsInsideLayer =
          LayoutUtils.getTilemapCoords(appData, details.localPosition) != null;
      _isPaintingTilemap = startsInsideLayer && (useEraser || hasTileSelection);
      _didModifyTilemapDuringGesture = false;
      if (_isPaintingTilemap) {
        final bool changed = useEraser
            ? LayoutUtils.eraseTileAtTilemap(
                appData,
                details.localPosition,
                pushUndo: true,
              )
            : LayoutUtils.pasteSelectedTilePatternAtTilemap(
                appData,
                details.localPosition,
                pushUndo: true,
              );
        if (changed) {
          _didModifyTilemapDuringGesture = true;
          appData.update();
        }
      }
    } else if (appData.selectedSection == "zones") {
      _didModifyZoneDuringGesture = false;
      _isDraggingZone = false;
      _isResizingZone = false;
      _zoneDragOffsetsByIndex.clear();
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      final int selectedZone = appData.selectedZone;
      final bool startsOnResizeHandle = !additiveSelection &&
          _selectedZoneIndices.length == 1 &&
          selectedZone != -1 &&
          LayoutUtils.isPointInZoneResizeHandle(
            appData,
            selectedZone,
            details.localPosition,
          );
      if (startsOnResizeHandle) {
        _isResizingZone = true;
        LayoutUtils.startResizeZoneFromPosition(
          appData,
          details.localPosition,
        );
        layoutZonesKey.currentState?.updateForm(appData);
        return;
      }
      final int hitZone = LayoutUtils.zoneIndexFromPosition(
        appData,
        details.localPosition,
      );
      if (hitZone == -1) {
        if (!additiveSelection) {
          return;
        }
        _isMarqueeSelectingZones = true;
        _zoneMarqueeSelectionAdditive = additiveSelection;
        _zonesMarqueeStartLocal = details.localPosition;
        _zonesMarqueeCurrentLocal = details.localPosition;
        _marqueeBaseZoneSelection = additiveSelection
            ? <int>{
                ..._selectedZoneIndices,
              }
            : <int>{};
        final bool selectionChanged = _applyZoneMarqueeSelection(appData);
        setState(() {});
        if (selectionChanged) {
          appData.update();
          layoutZonesKey.currentState?.updateForm(appData);
        }
        return;
      }
      if (additiveSelection) {
        return;
      }
      bool selectionChanged = false;
      if (!_selectedZoneIndices.contains(hitZone)) {
        selectionChanged = _setZoneSelection(
          appData,
          <int>{hitZone},
          preferredPrimary: hitZone,
        );
      }
      if (_startDraggingSelectedZones(
        appData,
        details.localPosition,
      )) {
        _isDraggingZone = true;
      }
      if (selectionChanged) {
        appData.update();
        layoutZonesKey.currentState?.updateForm(appData);
      }
    } else if (appData.selectedSection == "sprites") {
      _didModifySpriteDuringGesture = false;
      _isDraggingSprite = false;
      _spriteDragOffsetsByIndex.clear();
      final int hitSpriteIndex = LayoutUtils.spriteIndexFromPosition(
        appData,
        details.localPosition,
      );
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      if (hitSpriteIndex == -1) {
        if (!additiveSelection) {
          return;
        }
        _isMarqueeSelectingSprites = true;
        _spriteMarqueeSelectionAdditive = additiveSelection;
        _spritesMarqueeStartLocal = details.localPosition;
        _spritesMarqueeCurrentLocal = details.localPosition;
        _marqueeBaseSpriteSelection = additiveSelection
            ? <int>{
                ..._selectedSpriteIndices,
              }
            : <int>{};
        final bool selectionChanged = _applySpriteMarqueeSelection(
          appData,
        );
        setState(() {});
        if (selectionChanged) {
          appData.update();
          layoutSpritesKey.currentState?.updateForm(appData);
        }
        return;
      }
      if (additiveSelection) {
        return;
      }
      bool selectionChanged = false;
      if (!_selectedSpriteIndices.contains(hitSpriteIndex)) {
        selectionChanged = _setSpriteSelection(
          appData,
          <int>{hitSpriteIndex},
          preferredPrimary: hitSpriteIndex,
        );
      }
      if (_startDraggingSelectedSprites(
        appData,
        details.localPosition,
      )) {
        _isDraggingSprite = true;
      }
      if (selectionChanged) {
        appData.update();
        layoutSpritesKey.currentState?.updateForm(appData);
      }
    } else if (appData.selectedSection == "animations") {
      _isSelectingAnimationFrames = false;
      _didModifyAnimationDuringGesture = false;
      _animationDragStartFrame = null;
      final int frame = await LayoutUtils.animationFrameIndexFromCanvas(
        appData,
        details.localPosition,
      );
      if (frame != -1) {
        _isSelectingAnimationFrames = true;
        _animationDragStartFrame = frame;
        final bool changed =
            await LayoutUtils.setAnimationSelectionFromEndpoints(
          appData: appData,
          startFrame: frame,
          endFrame: frame,
        );
        if (changed) {
          _didModifyAnimationDuringGesture = true;
          appData.update();
        }
      }
    } else if (appData.selectedSection == "animation_rigs") {
      _didModifyAnimationRigDuringGesture = false;
      _isDraggingAnimationRigAnchor = false;
      _isDraggingAnimationRigHitBox = false;
      _isResizingAnimationRigHitBox = false;
      _animationRigHitBoxDragOffset = Offset.zero;
      if (_selectedAnimationForRig(appData) == null) {
        return;
      }

      final bool anchorGrabbed = _animationRigAnchorHitFromLocalPosition(
        appData,
        details.localPosition,
      );
      if (anchorGrabbed) {
        final bool selectionChanged = appData.selectedAnimationHitBox != -1;
        appData.selectedAnimationHitBox = -1;
        appData.pushUndo();
        _isDraggingAnimationRigAnchor = true;
        if (selectionChanged) {
          appData.update();
          layoutAnimationRigsKey.currentState?.updateForm(appData);
        }
        return;
      }

      final int resizeHitBoxIndex =
          _animationRigResizeHitBoxIndexFromLocalPosition(
        appData,
        details.localPosition,
      );
      if (resizeHitBoxIndex != -1) {
        appData.selectedAnimationHitBox = resizeHitBoxIndex;
        appData.pushUndo();
        _isResizingAnimationRigHitBox = true;
        appData.update();
        layoutAnimationRigsKey.currentState?.updateForm(appData);
        return;
      }

      final int hitBoxIndex = _animationRigHitBoxIndexFromLocalPosition(
        appData,
        details.localPosition,
      );
      if (hitBoxIndex != -1) {
        appData.selectedAnimationHitBox = hitBoxIndex;
        final Size? frameSize = _animationRigFrameSize();
        final Offset? imageCoords = _animationRigImagePosition(
          appData,
          details.localPosition,
          requireInside: false,
        );
        if (frameSize != null && imageCoords != null) {
          final GameAnimation? animation = _selectedAnimationForRig(appData);
          if (animation != null) {
            final GameAnimationFrameRig activeRig = _activeAnimationRig(
              appData,
              animation,
              writeBack: true,
            );
            if (hitBoxIndex >= activeRig.hitBoxes.length) {
              return;
            }
            final Rect hitRect = _animationRigHitBoxRectImage(
              activeRig.hitBoxes[hitBoxIndex],
              frameSize,
            );
            _animationRigHitBoxDragOffset = imageCoords - hitRect.topLeft;
            appData.pushUndo();
            _isDraggingAnimationRigHitBox = true;
          }
        }
        appData.update();
        layoutAnimationRigsKey.currentState?.updateForm(appData);
        return;
      }
    }
  }

  Future<void> _handlePanUpdate(
      AppData appData, DragUpdateDetails details) async {
    if (appData.selectedSection == "levels") {
      if (_isPointerDown) {
        appData.layersViewOffset += details.delta;
        appData.update();
      }
    } else if (appData.selectedSection == "paths") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isDraggingPathPoint && _draggingPathPointIndex >= 0) {
        final bool changed = LayoutUtils.dragSelectedPathPointFromCanvas(
          appData,
          pointIndex: _draggingPathPointIndex,
          localPosition: details.localPosition,
        );
        if (changed) {
          _didModifyPathDuringGesture = true;
          appData.update();
        }
      }
    } else if (appData.selectedSection == "viewport") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isResizingViewport) {
        LayoutUtils.resizeViewportFromCanvas(appData, details.localPosition);
        appData.update();
      } else if (_isDraggingViewport) {
        LayoutUtils.dragViewportFromCanvas(appData, details.localPosition);
        appData.update();
      }
    } else if (appData.selectedSection == "layers") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isMarqueeSelectingLayers) {
        _layersMarqueeCurrentLocal = details.localPosition;
        final bool selectionChanged = _applyMarqueeSelection(
          appData,
        );
        setState(() {});
        if (selectionChanged) {
          appData.update();
        }
      } else if (_isDraggingLayer) {
        final bool changed = _dragSelectedLayers(
          appData,
          details.localPosition,
        );
        if (changed) {
          _didModifyLayerDuringGesture = true;
          appData.update();
        }
      } else {
        // Arrow tool: no world navigation.
      }
    } else if (appData.selectedSection == "tilemap") {
      if (_hasMultipleLayersSelected(
        appData,
      )) {
        _isPaintingTilemap = false;
        return;
      }
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isPaintingTilemap) {
        final bool useEraser = appData.tilemapEraserEnabled;
        final bool isInsideLayer =
            LayoutUtils.getTilemapCoords(appData, details.localPosition) !=
                null;
        if (!isInsideLayer) {
          _isPaintingTilemap = false;
          return;
        }
        final bool changed = useEraser
            ? LayoutUtils.eraseTileAtTilemap(
                appData,
                details.localPosition,
                pushUndo: !_didModifyTilemapDuringGesture,
              )
            : LayoutUtils.pasteSelectedTilePatternAtTilemap(
                appData,
                details.localPosition,
                pushUndo: !_didModifyTilemapDuringGesture,
              );
        if (changed) {
          _didModifyTilemapDuringGesture = true;
          appData.update();
        }
      }
    } else if (appData.selectedSection == "zones") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isMarqueeSelectingZones) {
        _zonesMarqueeCurrentLocal = details.localPosition;
        final bool selectionChanged = _applyZoneMarqueeSelection(
          appData,
        );
        setState(() {});
        if (selectionChanged) {
          appData.update();
          layoutZonesKey.currentState?.updateForm(appData);
        }
      } else if (_isResizingZone && appData.selectedZone != -1) {
        LayoutUtils.resizeZoneFromCanvas(appData, details.localPosition);
        _didModifyZoneDuringGesture = true;
        appData.update();
        layoutZonesKey.currentState?.updateForm(appData);
      } else if (_isDraggingZone && _selectedZoneIndices.isNotEmpty) {
        final bool changed = _dragSelectedZones(
          appData,
          details.localPosition,
        );
        if (changed) {
          _didModifyZoneDuringGesture = true;
          appData.update();
          layoutZonesKey.currentState?.updateForm(appData);
        }
      } else {
        // Arrow tool: no world navigation.
      }
    } else if (appData.selectedSection == "sprites") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isMarqueeSelectingSprites) {
        _spritesMarqueeCurrentLocal = details.localPosition;
        final bool selectionChanged = _applySpriteMarqueeSelection(
          appData,
        );
        setState(() {});
        if (selectionChanged) {
          appData.update();
          layoutSpritesKey.currentState?.updateForm(appData);
        }
      } else if (_isDraggingSprite && _selectedSpriteIndices.isNotEmpty) {
        final bool changed = _dragSelectedSprites(
          appData,
          details.localPosition,
        );
        if (changed) {
          _didModifySpriteDuringGesture = true;
          appData.update();
          layoutSpritesKey.currentState?.updateForm(appData);
        }
      } else {
        // Arrow tool: no world navigation.
      }
    } else if (appData.selectedSection == "animations") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else if (_isSelectingAnimationFrames &&
          _animationDragStartFrame != null) {
        final int frame = await LayoutUtils.animationFrameIndexFromCanvas(
          appData,
          details.localPosition,
        );
        if (frame == -1) {
          return;
        }
        final bool changed =
            await LayoutUtils.setAnimationSelectionFromEndpoints(
          appData: appData,
          startFrame: _animationDragStartFrame!,
          endFrame: frame,
        );
        if (changed) {
          _didModifyAnimationDuringGesture = true;
          appData.update();
        }
      }
    } else if (appData.selectedSection == "animation_rigs") {
      if (!_isPointerDown) {
        // scroll-triggered pan — ignore
      } else {
        bool changed = false;
        if (_isResizingAnimationRigHitBox) {
          changed = _resizeSelectedAnimationRigHitBox(
            appData,
            details.localPosition,
          );
        } else if (_isDraggingAnimationRigHitBox) {
          changed = _dragSelectedAnimationRigHitBox(
            appData,
            details.localPosition,
          );
        } else if (_isDraggingAnimationRigAnchor) {
          changed = _setAnimationRigAnchorFromLocalPosition(
            appData,
            details.localPosition,
          );
        }
        if (changed) {
          _didModifyAnimationRigDuringGesture = true;
          appData.update();
          layoutAnimationRigsKey.currentState?.updateForm(appData);
        }
      }
    }
  }

  Future<void> _handlePanEnd(AppData appData, DragEndDetails details) async {
    if (_isDragGestureActive) {
      setState(() {
        _isDragGestureActive = false;
      });
    }
    if (appData.selectedSection == "viewport") {
      if (_isDraggingViewport || _isResizingViewport) {
        _isDraggingViewport = false;
        _isResizingViewport = false;
        LayoutUtils.endViewportDrag(appData);
        appData.update();
      }
    } else if (appData.selectedSection == "layers") {
      if (_isMarqueeSelectingLayers) {
        _isMarqueeSelectingLayers = false;
        _marqueeSelectionAdditive = false;
        _layersMarqueeStartLocal = null;
        _layersMarqueeCurrentLocal = null;
        _marqueeBaseLayerSelection = <int>{};
        setState(() {});
      }
      if (_isDraggingLayer) {
        _isDraggingLayer = false;
      }
      _layerDragOffsetsByIndex.clear();
      if (_didModifyLayerDuringGesture) {
        _didModifyLayerDuringGesture = false;
        unawaited(_autoSaveIfPossible(appData));
      }
    } else if (appData.selectedSection == "tilemap") {
      _isPaintingTilemap = false;
      if (_didModifyTilemapDuringGesture) {
        _didModifyTilemapDuringGesture = false;
        unawaited(_autoSaveIfPossible(appData));
      }
    } else if (appData.selectedSection == "paths") {
      _isDraggingPathPoint = false;
      _draggingPathPointIndex = -1;
      if (_didModifyPathDuringGesture) {
        _didModifyPathDuringGesture = false;
        unawaited(_autoSaveIfPossible(appData));
      }
    } else if (appData.selectedSection == "zones") {
      if (_isMarqueeSelectingZones) {
        _isMarqueeSelectingZones = false;
        _zoneMarqueeSelectionAdditive = false;
        _zonesMarqueeStartLocal = null;
        _zonesMarqueeCurrentLocal = null;
        _marqueeBaseZoneSelection = <int>{};
        setState(() {});
      }
      appData.zoneDragOffset = Offset.zero;
      if (_isDraggingZone) {
        _isDraggingZone = false;
      }
      _zoneDragOffsetsByIndex.clear();
      if (_isResizingZone) {
        _isResizingZone = false;
      }
      if (_didModifyZoneDuringGesture) {
        _didModifyZoneDuringGesture = false;
        unawaited(_autoSaveIfPossible(appData));
      }
    } else if (appData.selectedSection == "sprites") {
      if (_isMarqueeSelectingSprites) {
        _isMarqueeSelectingSprites = false;
        _spriteMarqueeSelectionAdditive = false;
        _spritesMarqueeStartLocal = null;
        _spritesMarqueeCurrentLocal = null;
        _marqueeBaseSpriteSelection = <int>{};
        setState(() {});
      }
      appData.spriteDragOffset = Offset.zero;
      if (_isDraggingSprite) {
        _isDraggingSprite = false;
      }
      _spriteDragOffsetsByIndex.clear();
      if (_didModifySpriteDuringGesture) {
        _didModifySpriteDuringGesture = false;
        unawaited(
          _autoSaveIfPossible(appData),
        );
      }
    } else if (appData.selectedSection == "animations") {
      _isSelectingAnimationFrames = false;
      _animationDragStartFrame = null;
      if (_didModifyAnimationDuringGesture) {
        final bool applied =
            await LayoutUtils.applyAnimationFrameSelectionToCurrentAnimation(
          appData,
          pushUndo: true,
        );
        _didModifyAnimationDuringGesture = false;
        if (applied) {
          appData.update();
          unawaited(
            _autoSaveIfPossible(appData),
          );
        }
      }
    } else if (appData.selectedSection == "animation_rigs") {
      _isDraggingAnimationRigAnchor = false;
      _isDraggingAnimationRigHitBox = false;
      _isResizingAnimationRigHitBox = false;
      _animationRigHitBoxDragOffset = Offset.zero;
      if (_didModifyAnimationRigDuringGesture) {
        _didModifyAnimationRigDuringGesture = false;
        unawaited(
          _autoSaveIfPossible(appData),
        );
      }
    }

    appData.dragging = false;
    appData.draggingTileIndex = -1;
  }

  void _handleTapDown(AppData appData, TapDownDetails details) {
    if (appData.selectedSection == "layers") {
      final int hitLayerIndex = LayoutUtils.selectLayerFromPosition(
        appData,
        details.localPosition,
      );
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      bool selectionChanged = false;
      if (additiveSelection) {
        if (hitLayerIndex != -1) {
          final Set<int> nextSelection = <int>{
            ..._selectedLayerIndices,
          };
          if (!nextSelection.remove(hitLayerIndex)) {
            nextSelection.add(hitLayerIndex);
          }
          selectionChanged = _setLayerSelection(
            appData,
            nextSelection,
            preferredPrimary: hitLayerIndex,
          );
        }
      } else if (hitLayerIndex == -1) {
        selectionChanged = _setLayerSelection(
          appData,
          <int>{},
        );
      } else {
        selectionChanged = _setLayerSelection(
          appData,
          <int>{hitLayerIndex},
          preferredPrimary: hitLayerIndex,
        );
      }
      if (selectionChanged) {
        appData.update();
      }
    } else if (appData.selectedSection == "tilemap") {
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      _consumeTilemapTapUp = false;
      if (!additiveSelection) {
        return;
      }
      _consumeTilemapTapUp = true;
      final int hitLayerIndex = LayoutUtils.selectLayerFromPosition(
        appData,
        details.localPosition,
      );
      if (hitLayerIndex == -1) {
        return;
      }
      final Set<int> nextSelection = <int>{
        ..._selectedLayerIndices,
      };
      if (!nextSelection.remove(hitLayerIndex)) {
        nextSelection.add(hitLayerIndex);
      }
      final bool selectionChanged = _setLayerSelection(
        appData,
        nextSelection,
        preferredPrimary: hitLayerIndex,
      );
      if (selectionChanged) {
        appData.update();
      }
    } else if (appData.selectedSection == "zones") {
      if (appData.selectedZone != -1 &&
          _selectedZoneIndices.length == 1 &&
          LayoutUtils.isPointInZoneResizeHandle(
            appData,
            appData.selectedZone,
            details.localPosition,
          )) {
        return;
      }
      final int hitZone = LayoutUtils.zoneIndexFromPosition(
        appData,
        details.localPosition,
      );
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      bool selectionChanged = false;
      if (additiveSelection) {
        if (hitZone != -1) {
          final Set<int> nextSelection = <int>{
            ..._selectedZoneIndices,
          };
          if (!nextSelection.remove(hitZone)) {
            nextSelection.add(hitZone);
          }
          selectionChanged = _setZoneSelection(
            appData,
            nextSelection,
            preferredPrimary: hitZone,
          );
        }
      } else if (hitZone == -1) {
        selectionChanged = _setZoneSelection(
          appData,
          <int>{},
        );
      } else {
        selectionChanged = _setZoneSelection(
          appData,
          <int>{hitZone},
          preferredPrimary: hitZone,
        );
      }
      if (selectionChanged) {
        appData.update();
        layoutZonesKey.currentState?.updateForm(appData);
      }
    } else if (appData.selectedSection == "sprites") {
      final int hitSpriteIndex = LayoutUtils.spriteIndexFromPosition(
        appData,
        details.localPosition,
      );
      final bool additiveSelection = _isLayerSelectionModifierPressed();
      bool selectionChanged = false;
      if (additiveSelection) {
        if (hitSpriteIndex != -1) {
          final Set<int> nextSelection = <int>{
            ..._selectedSpriteIndices,
          };
          if (!nextSelection.remove(hitSpriteIndex)) {
            nextSelection.add(hitSpriteIndex);
          }
          selectionChanged = _setSpriteSelection(
            appData,
            nextSelection,
            preferredPrimary: hitSpriteIndex,
          );
        }
      } else if (hitSpriteIndex == -1) {
        selectionChanged = _setSpriteSelection(
          appData,
          <int>{},
        );
      } else {
        selectionChanged = _setSpriteSelection(
          appData,
          <int>{hitSpriteIndex},
          preferredPrimary: hitSpriteIndex,
        );
      }
      if (selectionChanged) {
        appData.update();
        layoutSpritesKey.currentState?.updateForm(appData);
      }
    } else if (appData.selectedSection == "animations") {
      unawaited(() async {
        final int frame = await LayoutUtils.animationFrameIndexFromCanvas(
          appData,
          details.localPosition,
        );
        if (frame == -1) {
          if (LayoutUtils.hasAnimationFrameSelection(appData)) {
            LayoutUtils.clearAnimationFrameSelection(appData);
            appData.update();
          }
          return;
        }
        final bool singleFrameAlreadySelected =
            appData.animationSelectionStartFrame == frame &&
                appData.animationSelectionEndFrame == frame;
        if (singleFrameAlreadySelected) {
          LayoutUtils.clearAnimationFrameSelection(appData);
          appData.update();
          return;
        }
        final bool changed =
            await LayoutUtils.setAnimationSelectionFromEndpoints(
          appData: appData,
          startFrame: frame,
          endFrame: frame,
        );
        if (!changed) {
          return;
        }
        final bool applied =
            await LayoutUtils.applyAnimationFrameSelectionToCurrentAnimation(
          appData,
          pushUndo: true,
        );
        appData.update();
        if (applied) {
          await _autoSaveIfPossible(appData);
        }
      }());
    } else if (appData.selectedSection == "animation_rigs") {
      final bool anchorHit = _animationRigAnchorHitFromLocalPosition(
        appData,
        details.localPosition,
      );
      if (anchorHit) {
        if (appData.selectedAnimationHitBox != -1) {
          appData.selectedAnimationHitBox = -1;
          appData.update();
          layoutAnimationRigsKey.currentState?.updateForm(appData);
        }
        return;
      }
      final int hitBoxIndex = _animationRigHitBoxIndexFromLocalPosition(
        appData,
        details.localPosition,
      );
      if (hitBoxIndex != -1) {
        if (appData.selectedAnimationHitBox != hitBoxIndex) {
          appData.selectedAnimationHitBox = hitBoxIndex;
          appData.update();
          layoutAnimationRigsKey.currentState?.updateForm(appData);
        }
        return;
      }
      if (_selectedAnimationForRig(appData) == null) {
        return;
      }
      if (appData.selectedAnimationHitBox != -1) {
        appData.selectedAnimationHitBox = -1;
        appData.update();
        layoutAnimationRigsKey.currentState?.updateForm(appData);
      }
    }
  }

  void _handleTapUp(AppData appData, TapUpDetails details) {
    if (appData.selectedSection == "tilemap") {
      if (_consumeTilemapTapUp) {
        _consumeTilemapTapUp = false;
        return;
      }
      if (_isLayerSelectionModifierPressed()) {
        return;
      }
      if (_hasMultipleLayersSelected(
        appData,
      )) {
        return;
      }
      final bool changed = appData.tilemapEraserEnabled
          ? LayoutUtils.eraseTileAtTilemap(
              appData,
              details.localPosition,
              pushUndo: true,
            )
          : LayoutUtils.pasteSelectedTilePatternAtTilemap(
              appData,
              details.localPosition,
              pushUndo: true,
            );
      if (changed) {
        appData.update();
        unawaited(_autoSaveIfPossible(appData));
      }
    }
  }
}
