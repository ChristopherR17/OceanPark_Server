part of 'layout.dart';

/// Animation-rig canvas overlay widgets (frame strip).
extension _LayoutAnimationRigUI on _LayoutState {
  int? _animationRigFrameFromGlobalPosition({
    required Offset globalPosition,
    required int animationStart,
    required int animationEnd,
    required double frameTileExtent,
    required double frameSpacing,
  }) {
    final BuildContext? rowContext =
        _animationRigFrameStripRowKey.currentContext;
    if (rowContext == null) {
      return null;
    }
    final RenderObject? renderObject = rowContext.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }
    final Offset localPosition = renderObject.globalToLocal(globalPosition);
    final int frameCount = animationEnd - animationStart + 1;
    if (frameCount <= 0) {
      return null;
    }
    final double step = frameTileExtent + frameSpacing;
    if (step <= 0) {
      return null;
    }
    int frameOffset = (localPosition.dx / step).floor();
    if (frameOffset < 0) {
      frameOffset = 0;
    } else if (frameOffset >= frameCount) {
      frameOffset = frameCount - 1;
    }
    return animationStart + frameOffset;
  }

  Widget _buildAnimationRigFrameStripOverlay(AppData appData) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    if (animation == null) {
      return const SizedBox.shrink();
    }
    final int animationStart =
        animation.startFrame < 0 ? 0 : animation.startFrame;
    final int animationEnd = animation.endFrame < animationStart
        ? animationStart
        : animation.endFrame;
    final List<int> selectedFrames = _animationRigSelectedFrames(
      appData,
      animation,
      writeBack: true,
    );
    final int activeFrame = _animationRigActiveFrame(
      appData,
      animation,
      writeBack: true,
    );
    final Set<int> selectedSet = selectedFrames.toSet();
    final int primarySelectedFrame =
        selectedFrames.isEmpty ? activeFrame : selectedFrames.first;
    final ui.Image? sourceImage = appData.imagesCache[animation.mediaFile];
    final mediaAsset = appData.mediaAssetByFileName(animation.mediaFile);
    final bool canDrawFramePreview = sourceImage != null &&
        mediaAsset != null &&
        mediaAsset.tileWidth > 0 &&
        mediaAsset.tileHeight > 0;
    final double frameWidth =
        canDrawFramePreview ? mediaAsset.tileWidth.toDouble() : 0.0;
    final double frameHeight =
        canDrawFramePreview ? mediaAsset.tileHeight.toDouble() : 0.0;
    final int columns = canDrawFramePreview
        ? ((sourceImage.width / mediaAsset.tileWidth).floor().clamp(1, 99999))
        : 1;
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    const Color selectionColor = Color(0xFFFF9800);
    const double frameTileExtent = 58.0;
    const double frameSpacing = 0.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Container(
          height: _LayoutState._animationRigFrameStripReservedHeight,
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          decoration: BoxDecoration(
            color: cdkColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border(
              top: BorderSide(
                color: cdkColors.colorTextSecondary.withValues(alpha: 0.30),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: Align(
                          alignment: Alignment.center,
                          child: Row(
                            key: _animationRigFrameStripRowKey,
                            mainAxisSize: MainAxisSize.min,
                            children: List<Widget>.generate(
                              animationEnd - animationStart + 1,
                              (index) {
                                final int frame = animationStart + index;
                                final bool inSelection =
                                    selectedSet.contains(frame);
                                final bool isPrimary =
                                    frame == primarySelectedFrame;
                                final Color borderColor = inSelection
                                    ? selectionColor
                                    : cdkColors.colorTextSecondary
                                        .withValues(alpha: 0.35);
                                return GestureDetector(
                                  onTap: () {
                                    final bool additiveSelection =
                                        _isAnimationRigFrameSelectionModifierPressed();
                                    if (!additiveSelection) {
                                      if (_setAnimationRigFrameSelectionFrames(
                                        appData,
                                        animation,
                                        frames: <int>[frame],
                                        setActiveToFirst: true,
                                      )) {
                                        appData.update();
                                        layoutAnimationRigsKey.currentState
                                            ?.updateForm(appData);
                                      }
                                      return;
                                    }
                                    final List<int> nextSelection =
                                        List<int>.from(selectedFrames);
                                    if (nextSelection.contains(frame)) {
                                      if (nextSelection.length > 1) {
                                        nextSelection.remove(frame);
                                      }
                                    } else {
                                      nextSelection.add(frame);
                                    }
                                    if (_setAnimationRigFrameSelectionFrames(
                                      appData,
                                      animation,
                                      frames: nextSelection,
                                      setActiveToFirst: true,
                                    )) {
                                      appData.update();
                                      layoutAnimationRigsKey.currentState
                                          ?.updateForm(appData);
                                    }
                                  },
                                  onPanStart: (details) {
                                    _isSelectingAnimationRigFramesFromStrip =
                                        true;
                                    _animationRigFrameStripDragAnchorFrame =
                                        _animationRigFrameFromGlobalPosition(
                                              globalPosition:
                                                  details.globalPosition,
                                              animationStart: animationStart,
                                              animationEnd: animationEnd,
                                              frameTileExtent: frameTileExtent,
                                              frameSpacing: frameSpacing,
                                            ) ??
                                            frame;
                                    _animationRigFrameStripDragAdditive =
                                        _isAnimationRigFrameSelectionModifierPressed();
                                    _animationRigFrameStripDragBaseSelection =
                                        _animationRigFrameStripDragAdditive
                                            ? List<int>.from(selectedFrames)
                                            : <int>[];
                                    final List<int> dragFrames = <int>[frame];
                                    final List<int> nextSelection =
                                        _animationRigFrameStripDragAdditive
                                            ? <int>[
                                                ..._animationRigFrameStripDragBaseSelection,
                                                ...dragFrames.where((item) =>
                                                    !_animationRigFrameStripDragBaseSelection
                                                        .contains(item)),
                                              ]
                                            : dragFrames;
                                    if (_setAnimationRigFrameSelectionFrames(
                                      appData,
                                      animation,
                                      frames: nextSelection,
                                      setActiveToFirst: true,
                                    )) {
                                      appData.update();
                                      layoutAnimationRigsKey.currentState
                                          ?.updateForm(appData);
                                    }
                                  },
                                  onPanUpdate: (details) {
                                    if (!_isSelectingAnimationRigFramesFromStrip ||
                                        _animationRigFrameStripDragAnchorFrame ==
                                            null) {
                                      return;
                                    }
                                    final int? hitFrame =
                                        _animationRigFrameFromGlobalPosition(
                                      globalPosition: details.globalPosition,
                                      animationStart: animationStart,
                                      animationEnd: animationEnd,
                                      frameTileExtent: frameTileExtent,
                                      frameSpacing: frameSpacing,
                                    );
                                    if (hitFrame == null) {
                                      return;
                                    }
                                    final int nextFrame = hitFrame;
                                    final int anchorFrame =
                                        _animationRigFrameStripDragAnchorFrame!;
                                    final List<int> dragFrames =
                                        anchorFrame <= nextFrame
                                            ? List<int>.generate(
                                                nextFrame - anchorFrame + 1,
                                                (int rangeIndex) =>
                                                    anchorFrame + rangeIndex,
                                                growable: false,
                                              )
                                            : List<int>.generate(
                                                anchorFrame - nextFrame + 1,
                                                (int rangeIndex) =>
                                                    anchorFrame - rangeIndex,
                                                growable: false,
                                              );
                                    final List<int> nextSelection =
                                        _animationRigFrameStripDragAdditive
                                            ? <int>[
                                                ..._animationRigFrameStripDragBaseSelection,
                                                ...dragFrames.where((item) =>
                                                    !_animationRigFrameStripDragBaseSelection
                                                        .contains(item)),
                                              ]
                                            : dragFrames;
                                    if (_setAnimationRigFrameSelectionFrames(
                                      appData,
                                      animation,
                                      frames: nextSelection,
                                      setActiveToFirst: true,
                                    )) {
                                      appData.update();
                                      layoutAnimationRigsKey.currentState
                                          ?.updateForm(appData);
                                    }
                                  },
                                  onPanEnd: (_) {
                                    _isSelectingAnimationRigFramesFromStrip =
                                        false;
                                    _animationRigFrameStripDragAnchorFrame =
                                        null;
                                    _animationRigFrameStripDragAdditive = false;
                                    _animationRigFrameStripDragBaseSelection =
                                        <int>[];
                                  },
                                  onPanCancel: () {
                                    _isSelectingAnimationRigFramesFromStrip =
                                        false;
                                    _animationRigFrameStripDragAnchorFrame =
                                        null;
                                    _animationRigFrameStripDragAdditive = false;
                                    _animationRigFrameStripDragBaseSelection =
                                        <int>[];
                                  },
                                  child: Container(
                                    width: frameTileExtent,
                                    height: frameTileExtent,
                                    decoration: BoxDecoration(
                                      color: cdkColors.background,
                                      borderRadius: BorderRadius.circular(1),
                                      border: Border.all(
                                        color: borderColor,
                                        width: isPrimary && inSelection
                                            ? 2.8
                                            : (inSelection ? 2.2 : 0.8),
                                      ),
                                    ),
                                    child: canDrawFramePreview
                                        ? CustomPaint(
                                            painter:
                                                _AnimationRigFramePreviewPainter(
                                              image: sourceImage,
                                              frameWidth: frameWidth,
                                              frameHeight: frameHeight,
                                              columns: columns,
                                              frameIndex: frame,
                                              drawCheckerboard: false,
                                            ),
                                          )
                                        : Center(
                                            child: CDKText(
                                              '$frame',
                                              role: CDKTextRole.caption,
                                            ),
                                          ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
