part of 'layout.dart';

/// Animation rig frame math, hit-box detection, and anchor logic.
extension _LayoutAnimationRigHelpers on _LayoutState {
  GameAnimation? _selectedAnimationForRig(AppData appData) {
    if (appData.selectedAnimation < 0 ||
        appData.selectedAnimation >= appData.gameData.animations.length) {
      return null;
    }
    return appData.gameData.animations[appData.selectedAnimation];
  }

  List<int> _animationRigSelectedFrames(
    AppData appData,
    GameAnimation animation, {
    bool writeBack = false,
  }) {
    final int totalFrames =
        (animation.endFrame < 0 ? 0 : animation.endFrame) + 1;
    return LayoutUtils.animationRigSelectedFrames(
      appData: appData,
      animation: animation,
      totalFrames: totalFrames,
      writeBack: writeBack,
    );
  }

  bool _isAnimationRigFrameSelectionModifierPressed() {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    return keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed;
  }

  bool _setAnimationRigFrameSelectionFrames(
    AppData appData,
    GameAnimation animation, {
    required Iterable<int> frames,
    bool setActiveToFirst = true,
  }) {
    final bool changed = LayoutUtils.setAnimationRigSelectedFrames(
      appData: appData,
      animation: animation,
      frames: frames,
      totalFrames: (animation.endFrame < 0 ? 0 : animation.endFrame) + 1,
      setActiveToFirst: setActiveToFirst,
    );
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    if (appData.selectedAnimationHitBox >= activeRig.hitBoxes.length) {
      appData.selectedAnimationHitBox = -1;
    }
    return changed;
  }

  int _animationRigActiveFrame(
    AppData appData,
    GameAnimation animation, {
    bool writeBack = false,
  }) {
    final List<int> selectedFrames = _animationRigSelectedFrames(
      appData,
      animation,
      writeBack: writeBack,
    );
    if (selectedFrames.isEmpty) {
      return animation.startFrame;
    }
    final int active = selectedFrames.first;
    if (writeBack && appData.animationRigActiveFrame != active) {
      appData.animationRigActiveFrame = active;
    }
    return active;
  }

  GameAnimationFrameRig _activeAnimationRig(
    AppData appData,
    GameAnimation animation, {
    bool writeBack = false,
  }) {
    final int frame = _animationRigActiveFrame(
      appData,
      animation,
      writeBack: writeBack,
    );
    return animation.rigForFrame(frame);
  }

  Size? _animationRigFrameSize() {
    final ui.Image? frameImage = _layerImage;
    if (frameImage == null) {
      return null;
    }
    return Size(
      frameImage.width.toDouble(),
      frameImage.height.toDouble(),
    );
  }

  Offset? _animationRigImagePosition(
    AppData appData,
    Offset localPosition, {
    bool requireInside = true,
  }) {
    final Size? frameSize = _animationRigFrameSize();
    if (frameSize == null) {
      return null;
    }
    final Offset imageCoords = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    if (!requireInside) {
      return imageCoords;
    }
    if (imageCoords.dx < 0 ||
        imageCoords.dy < 0 ||
        imageCoords.dx > frameSize.width ||
        imageCoords.dy > frameSize.height) {
      return null;
    }
    return imageCoords;
  }

  Rect _animationRigHitBoxRectImage(
    GameAnimationHitBox hitBox,
    Size frameSize,
  ) {
    return Rect.fromLTWH(
      hitBox.x.clamp(0.0, 1.0) * frameSize.width,
      hitBox.y.clamp(0.0, 1.0) * frameSize.height,
      hitBox.width.clamp(0.01, 1.0) * frameSize.width,
      hitBox.height.clamp(0.01, 1.0) * frameSize.height,
    );
  }

  double _animationRigResizeHandleSizeImage(AppData appData) {
    final double scale = appData.scaleFactor <= 0 ? 1.0 : appData.scaleFactor;
    return (14.0 / scale).clamp(6.0, 24.0);
  }

  int _animationRigHitBoxIndexFromLocalPosition(
    AppData appData,
    Offset localPosition,
  ) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    final Size? frameSize = _animationRigFrameSize();
    final Offset? imageCoords = _animationRigImagePosition(
      appData,
      localPosition,
      requireInside: false,
    );
    if (animation == null || frameSize == null || imageCoords == null) {
      return -1;
    }
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    for (int i = activeRig.hitBoxes.length - 1; i >= 0; i--) {
      final Rect rect = _animationRigHitBoxRectImage(
        activeRig.hitBoxes[i],
        frameSize,
      );
      if (rect.contains(imageCoords)) {
        return i;
      }
    }
    return -1;
  }

  int _animationRigResizeHitBoxIndexFromLocalPosition(
    AppData appData,
    Offset localPosition,
  ) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    final Size? frameSize = _animationRigFrameSize();
    final Offset? imageCoords = _animationRigImagePosition(
      appData,
      localPosition,
      requireInside: false,
    );
    if (animation == null || frameSize == null || imageCoords == null) {
      return -1;
    }
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    for (int i = activeRig.hitBoxes.length - 1; i >= 0; i--) {
      final Rect rect = _animationRigHitBoxRectImage(
        activeRig.hitBoxes[i],
        frameSize,
      );
      final double handleSize =
          _animationRigResizeHandleSizeImage(appData).clamp(
        0.0,
        rect.width < rect.height ? rect.width : rect.height,
      );
      if (handleSize <= 0) {
        continue;
      }
      final bool inBounds = imageCoords.dx >= rect.right - handleSize &&
          imageCoords.dx <= rect.right &&
          imageCoords.dy >= rect.bottom - handleSize &&
          imageCoords.dy <= rect.bottom;
      if (!inBounds) {
        continue;
      }
      if (imageCoords.dx + imageCoords.dy >=
          rect.right + rect.bottom - handleSize) {
        return i;
      }
    }
    return -1;
  }

  double _animationRigAnchorGrabRadiusImage(AppData appData) {
    final double scale = appData.scaleFactor <= 0 ? 1.0 : appData.scaleFactor;
    return (12.0 / scale).clamp(4.0, 24.0);
  }

  bool _animationRigAnchorHitFromLocalPosition(
    AppData appData,
    Offset localPosition,
  ) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    final Size? frameSize = _animationRigFrameSize();
    final Offset? imageCoords = _animationRigImagePosition(
      appData,
      localPosition,
      requireInside: false,
    );
    if (animation == null || frameSize == null || imageCoords == null) {
      return false;
    }
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    final Offset anchorCenter = Offset(
      activeRig.anchorX.clamp(0.0, 1.0) * frameSize.width,
      activeRig.anchorY.clamp(0.0, 1.0) * frameSize.height,
    );
    final double radius = _animationRigAnchorGrabRadiusImage(appData);
    return (imageCoords - anchorCenter).distance <= radius;
  }

  bool _setAnimationRigAnchorFromLocalPosition(
    AppData appData,
    Offset localPosition,
  ) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    final Size? frameSize = _animationRigFrameSize();
    final Offset? imageCoords = _animationRigImagePosition(
      appData,
      localPosition,
      requireInside: false,
    );
    if (animation == null || frameSize == null || imageCoords == null) {
      return false;
    }
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    final double nextAnchorX =
        (imageCoords.dx / frameSize.width).clamp(0.0, 1.0);
    final double nextAnchorY =
        (imageCoords.dy / frameSize.height).clamp(0.0, 1.0);
    final bool changedX = (activeRig.anchorX - nextAnchorX).abs() > 0.0005;
    final bool changedY = (activeRig.anchorY - nextAnchorY).abs() > 0.0005;
    if (!changedX && !changedY) {
      return false;
    }
    final GameAnimationFrameRig nextRig = activeRig.copyWith(
      anchorX: nextAnchorX,
      anchorY: nextAnchorY,
    );
    animation.setRigForFrames(
      _animationRigSelectedFrames(
        appData,
        animation,
        writeBack: true,
      ),
      nextRig,
    );
    return true;
  }

  bool _dragSelectedAnimationRigHitBox(
    AppData appData,
    Offset localPosition,
  ) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    final Size? frameSize = _animationRigFrameSize();
    final int selected = appData.selectedAnimationHitBox;
    final Offset? imageCoords = _animationRigImagePosition(
      appData,
      localPosition,
      requireInside: false,
    );
    if (animation == null ||
        frameSize == null ||
        imageCoords == null ||
        selected < 0) {
      return false;
    }
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    if (selected >= activeRig.hitBoxes.length) {
      return false;
    }
    final GameAnimationHitBox current = activeRig.hitBoxes[selected];
    final double rawX =
        (imageCoords.dx - _animationRigHitBoxDragOffset.dx) / frameSize.width;
    final double rawY =
        (imageCoords.dy - _animationRigHitBoxDragOffset.dy) / frameSize.height;
    final double nextX = rawX.clamp(0.0, (1.0 - current.width).clamp(0.0, 1.0));
    final double nextY =
        rawY.clamp(0.0, (1.0 - current.height).clamp(0.0, 1.0));
    final bool changedX = (current.x - nextX).abs() > 0.0005;
    final bool changedY = (current.y - nextY).abs() > 0.0005;
    if (!changedX && !changedY) {
      return false;
    }
    final List<GameAnimationHitBox> nextHitBoxes = activeRig.hitBoxes
        .map((item) => item.copyWith())
        .toList(growable: true);
    nextHitBoxes[selected] = current.copyWith(
      x: nextX,
      y: nextY,
    );
    final GameAnimationFrameRig nextRig =
        activeRig.copyWith(hitBoxes: nextHitBoxes);
    animation.setRigForFrames(
      _animationRigSelectedFrames(
        appData,
        animation,
        writeBack: true,
      ),
      nextRig,
    );
    return true;
  }

  bool _resizeSelectedAnimationRigHitBox(
    AppData appData,
    Offset localPosition,
  ) {
    final GameAnimation? animation = _selectedAnimationForRig(appData);
    final Size? frameSize = _animationRigFrameSize();
    final int selected = appData.selectedAnimationHitBox;
    final Offset? imageCoords = _animationRigImagePosition(
      appData,
      localPosition,
      requireInside: false,
    );
    if (animation == null ||
        frameSize == null ||
        imageCoords == null ||
        selected < 0) {
      return false;
    }
    final GameAnimationFrameRig activeRig = _activeAnimationRig(
      appData,
      animation,
      writeBack: true,
    );
    if (selected >= activeRig.hitBoxes.length) {
      return false;
    }
    final GameAnimationHitBox current = activeRig.hitBoxes[selected];
    final double rightNorm = (imageCoords.dx / frameSize.width).clamp(0.0, 1.0);
    final double bottomNorm =
        (imageCoords.dy / frameSize.height).clamp(0.0, 1.0);
    final double nextWidth =
        (rightNorm - current.x).clamp(0.01, 1.0 - current.x);
    final double nextHeight =
        (bottomNorm - current.y).clamp(0.01, 1.0 - current.y);
    final bool changedW = (current.width - nextWidth).abs() > 0.0005;
    final bool changedH = (current.height - nextHeight).abs() > 0.0005;
    if (!changedW && !changedH) {
      return false;
    }
    final List<GameAnimationHitBox> nextHitBoxes = activeRig.hitBoxes
        .map((item) => item.copyWith())
        .toList(growable: true);
    nextHitBoxes[selected] = current.copyWith(
      width: nextWidth,
      height: nextHeight,
    );
    final GameAnimationFrameRig nextRig =
        activeRig.copyWith(hitBoxes: nextHitBoxes);
    animation.setRigForFrames(
      _animationRigSelectedFrames(
        appData,
        animation,
        writeBack: true,
      ),
      nextRig,
    );
    return true;
  }
}
