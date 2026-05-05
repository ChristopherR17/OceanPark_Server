import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'app_data.dart';
import 'game_animation.dart';
import 'game_layer.dart';
import 'game_level.dart';
import 'game_media_asset.dart';
import 'game_path.dart';
import 'game_sprite.dart';
import 'game_zone.dart';
import 'layout_sprites.dart';
import 'layout_zones.dart';

class LayoutUtils {
  static const double _minDepthProjectionFactor = 0.25;
  static const double _maxDepthProjectionFactor = 4.0;
  static const double _editorTicksPerSecond = 10.0;

  static Future<_AnimationGridInfo?> _selectedAnimationGridInfo(
      AppData appData) async {
    if (appData.selectedAnimation < 0 ||
        appData.selectedAnimation >= appData.gameData.animations.length) {
      return null;
    }
    final GameAnimation animation =
        appData.gameData.animations[appData.selectedAnimation];
    final GameMediaAsset? media =
        appData.mediaAssetByFileName(animation.mediaFile);
    if (media == null || media.tileWidth <= 0 || media.tileHeight <= 0) {
      return null;
    }
    final ui.Image image = await appData.getImage(animation.mediaFile);
    final int cols = math.max(1, (image.width / media.tileWidth).floor());
    final int rows = math.max(1, (image.height / media.tileHeight).floor());
    return _AnimationGridInfo(
      animation: animation,
      media: media,
      image: image,
      cols: cols,
      rows: rows,
      totalFrames: math.max(1, cols * rows),
    );
  }

  static bool hasAnimationFrameSelection(AppData appData) {
    return appData.animationSelectionStartFrame >= 0 &&
        appData.animationSelectionEndFrame >= 0;
  }

  static void clearAnimationFrameSelection(AppData appData) {
    appData.animationSelectionStartFrame = -1;
    appData.animationSelectionEndFrame = -1;
  }

  static Future<int> animationFrameIndexFromCanvas(
    AppData appData,
    Offset localPosition,
  ) async {
    final _AnimationGridInfo? gridInfo =
        await _selectedAnimationGridInfo(appData);
    if (gridInfo == null) {
      return -1;
    }
    final Offset imageCoords = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    if (imageCoords.dx < 0 ||
        imageCoords.dy < 0 ||
        imageCoords.dx >= gridInfo.image.width ||
        imageCoords.dy >= gridInfo.image.height) {
      return -1;
    }
    final int col = (imageCoords.dx / gridInfo.media.tileWidth).floor();
    final int row = (imageCoords.dy / gridInfo.media.tileHeight).floor();
    final int frame = row * gridInfo.cols + col;
    if (frame < 0 || frame >= gridInfo.totalFrames) {
      return -1;
    }
    return frame;
  }

  static Future<bool> setAnimationSelectionFromEndpoints({
    required AppData appData,
    required int startFrame,
    required int endFrame,
  }) async {
    final _AnimationGridInfo? gridInfo =
        await _selectedAnimationGridInfo(appData);
    if (gridInfo == null) {
      return false;
    }
    final int clampedStart = startFrame.clamp(0, gridInfo.totalFrames - 1);
    final int clampedEnd = endFrame.clamp(0, gridInfo.totalFrames - 1);
    final int nextStart = math.min(clampedStart, clampedEnd);
    final int nextEnd = math.max(clampedStart, clampedEnd);
    if (appData.animationSelectionStartFrame == nextStart &&
        appData.animationSelectionEndFrame == nextEnd) {
      return false;
    }
    appData.animationSelectionStartFrame = nextStart;
    appData.animationSelectionEndFrame = nextEnd;
    return true;
  }

  static Future<bool> applyAnimationFrameSelectionToCurrentAnimation(
    AppData appData, {
    bool pushUndo = false,
  }) async {
    if (!hasAnimationFrameSelection(appData)) {
      return false;
    }
    final _AnimationGridInfo? gridInfo =
        await _selectedAnimationGridInfo(appData);
    if (gridInfo == null) {
      return false;
    }
    final int nextStart =
        appData.animationSelectionStartFrame.clamp(0, gridInfo.totalFrames - 1);
    final int nextEnd = appData.animationSelectionEndFrame
        .clamp(nextStart, gridInfo.totalFrames - 1);
    if (gridInfo.animation.startFrame == nextStart &&
        gridInfo.animation.endFrame == nextEnd) {
      return false;
    }
    if (pushUndo) {
      appData.pushUndo();
    }
    gridInfo.animation.startFrame = nextStart;
    gridInfo.animation.endFrame = nextEnd;
    return true;
  }

  /// Maps depth displacement to a depthProjection factor.
  /// Negative depth => closer (moves faster), positive depth => farther (moves slower).
  static double depthProjectionFactorForDepth(
    double depth, {
    double sensitivity = GameLevel.defaultDepthSensitivity,
  }) {
    final double normalizedSensitivity = sensitivity.isFinite
        ? math.max(0.0, sensitivity)
        : GameLevel.defaultDepthSensitivity;
    final double factor = math.exp(-depth * normalizedSensitivity);
    return factor
        .clamp(_minDepthProjectionFactor, _maxDepthProjectionFactor)
        .toDouble();
  }

  static double depthSensitivityForSelectedLevel(AppData appData) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return GameLevel.defaultDepthSensitivity;
    }
    return appData.gameData.levels[appData.selectedLevel].depthSensitivity;
  }

  static Offset _depthProjectionImageOffsetForDepth(
      AppData appData, double depth) {
    return appData.imageOffset;
  }

  static double _depthProjectionScaleFactorForDepth(
      AppData appData, double depth) {
    final double depthProjection = depthProjectionFactorForDepth(
      depth,
      sensitivity: depthSensitivityForSelectedLevel(appData),
    );
    final double baseScale =
        appData.scaleFactor.isFinite && appData.scaleFactor > 0
            ? appData.scaleFactor
            : 1.0;
    return baseScale * depthProjection;
  }

  static Offset _depthProjectionImageOffsetForLayer(
      AppData appData, GameLayer layer) {
    return _depthProjectionImageOffsetForDepth(appData, layer.depth);
  }

  static double _depthProjectionScaleFactorForLayer(
      AppData appData, GameLayer layer) {
    return _depthProjectionScaleFactorForDepth(appData, layer.depth);
  }

  static Offset _depthProjectionImageOffsetForSprite(
    AppData appData,
    GameSprite sprite,
  ) {
    return _depthProjectionImageOffsetForDepth(appData, sprite.depth);
  }

  static double _depthProjectionScaleFactorForSprite(
    AppData appData,
    GameSprite sprite,
  ) {
    return _depthProjectionScaleFactorForDepth(appData, sprite.depth);
  }

  static Future<ui.Image> generateTilemapImage(
      AppData appData, int levelIndex, int layerIndex, bool drawGrid) async {
    final level = appData.gameData.levels[levelIndex];
    final layer = level.layers[layerIndex];

    int rows = layer.tileMap.length;
    int cols = rows == 0 ? 0 : layer.tileMap[0].length;
    double tileWidth = layer.tilesWidth.toDouble();
    double tileHeight = layer.tilesHeight.toDouble();
    double tilemapWidth = cols * tileWidth;
    double tilemapHeight = rows * tileHeight;

    if (rows == 0 || cols == 0) {
      return await drawCanvasImageEmpty(appData);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final ui.Image tilesetImage = await appData.getImage(layer.tilesSheetFile);

    // Obtenir el nombre de columnes al tileset
    int tilesetColumns = (tilesetImage.width / tileWidth).floor();

    // Dibuixar els tiles segons el `tileMap`
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        int tileIndex = layer.tileMap[row][col];

        if (tileIndex >= 0) {
          // Només dibuixar si el tileIndex és vàlid
          int tileRow = (tileIndex / tilesetColumns).floor();
          int tileCol = (tileIndex % tilesetColumns);

          double tileX = tileCol * tileWidth;
          double tileY = tileRow * tileHeight;

          // Posició al tilemap
          double destX = col * tileWidth;
          double destY = row * tileHeight;

          // Dibuixar el tile corresponent
          canvas.drawImageRect(
            tilesetImage,
            Rect.fromLTWH(tileX, tileY, tileWidth, tileHeight),
            Rect.fromLTWH(destX, destY, tileWidth, tileHeight),
            Paint(),
          );
        }
      }
    }

    if (drawGrid) {
      final textStyle = TextStyle(
        color: Colors.black,
        fontSize: 10,
      );
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
      );

      final gridPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      for (int row = 0; row <= rows; row++) {
        double y = row * tileHeight;
        canvas.drawLine(Offset(0, y), Offset(tilemapWidth, y), gridPaint);

        // Draw row number at the left
        if (row < rows) {
          textPainter.text = TextSpan(
            text: '$y',
            style: textStyle,
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(0, y));
        }
      }

      for (int col = 0; col <= cols; col++) {
        double x = col * tileWidth;
        canvas.drawLine(Offset(x, 0), Offset(x, tilemapHeight), gridPaint);

        // Draw column number at the top
        if (col < cols) {
          textPainter.text = TextSpan(
            text: '$x',
            style: textStyle,
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x, 0));
        }
      }
    }

    final picture = recorder.endRecording();
    return await picture.toImage(tilemapWidth.toInt(), tilemapHeight.toInt());
  }

  static Future<ui.Image> generateTilesetImage(
      AppData appData,
      String tilesetPath,
      double tileWidth,
      double tileHeight,
      bool drawGrid) async {
    final tilesheetImage = await appData.getImage(tilesetPath);

    double imageWidth = tilesheetImage.width.toDouble();
    double imageHeight = tilesheetImage.height.toDouble();

    int tilesetColumns = (imageWidth / tileWidth).floor();
    int tilesetRows = (imageHeight / tileHeight).floor();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImage(tilesheetImage, Offset.zero, Paint());

    if (drawGrid) {
      final gridPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      for (int row = 0; row <= tilesetRows; row++) {
        double y = row * tileHeight;
        canvas.drawLine(Offset(0, y), Offset(imageWidth, y), gridPaint);
      }

      for (int col = 0; col <= tilesetColumns; col++) {
        double x = col * tileWidth;
        canvas.drawLine(Offset(x, 0), Offset(x, imageHeight), gridPaint);
      }
    }

    if (appData.selectedTileIndex != -1) {
      int selectedIndex = appData.selectedTileIndex;
      int tileRow = (selectedIndex / tilesetColumns).floor();
      int tileCol = selectedIndex % tilesetColumns;
      final redRect = Rect.fromLTWH(
          tileCol * tileWidth, tileRow * tileHeight, tileWidth, tileHeight);
      final redPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(redRect, redPaint);
    }

    final picture = recorder.endRecording();
    final tilesetImage =
        await picture.toImage(imageWidth.toInt(), imageHeight.toInt());

    return tilesetImage;
  }

  /// Ensures all tileset images for the current level are loaded into [appData.imagesCache].
  static Future<void> preloadLayerImages(AppData appData) async {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    for (final layer in level.layers) {
      if (layer.tilesSheetFile.isNotEmpty) {
        try {
          await appData.getImage(layer.tilesSheetFile);
        } catch (_) {}
      }
    }
  }

  /// Ensures all sprite images for the current level are loaded into [appData.imagesCache].
  static Future<void> preloadSpriteImages(AppData appData) async {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    for (final sprite in level.sprites) {
      final String imageFile = spriteImageFile(appData, sprite);
      if (imageFile.isNotEmpty) {
        try {
          await appData.getImage(imageFile);
        } catch (_) {}
      }
    }
  }

  static GameAnimation? spriteAnimation(AppData appData, GameSprite sprite) {
    return appData.animationById(sprite.animationId);
  }

  static String spriteImageFile(AppData appData, GameSprite sprite) {
    final GameAnimation? animation = spriteAnimation(appData, sprite);
    final String fromAnimation = animation?.mediaFile.trim() ?? '';
    if (fromAnimation.isNotEmpty) {
      return fromAnimation;
    }
    return sprite.imageFile;
  }

  static GameMediaAsset? spriteMediaAsset(AppData appData, GameSprite sprite) {
    final String file = spriteImageFile(appData, sprite);
    if (file.trim().isEmpty) {
      return null;
    }
    return appData.mediaAssetByFileName(file);
  }

  static Size spriteFrameSize(AppData appData, GameSprite sprite) {
    final GameMediaAsset? media = spriteMediaAsset(appData, sprite);
    if (media != null && media.tileWidth > 0 && media.tileHeight > 0) {
      return Size(media.tileWidth.toDouble(), media.tileHeight.toDouble());
    }
    final double width =
        sprite.spriteWidth > 0 ? sprite.spriteWidth.toDouble() : 1.0;
    final double height =
        sprite.spriteHeight > 0 ? sprite.spriteHeight.toDouble() : 1.0;
    return Size(width, height);
  }

  static int _spriteTotalFramesForAnchorResolution(
    AppData appData,
    GameSprite sprite,
    Size frameSize,
  ) {
    final String imageFile = spriteImageFile(appData, sprite);
    final ui.Image? image = appData.imagesCache[imageFile];
    if (image != null) {
      return spriteTotalFramesFromImage(
        image: image,
        frameSize: frameSize,
      );
    }
    final GameAnimation? animation = spriteAnimation(appData, sprite);
    if (animation != null) {
      final int fallbackMaxFrame =
          math.max(animation.startFrame, animation.endFrame);
      return math.max(1, fallbackMaxFrame + 1);
    }
    return 1;
  }

  static Offset spriteAnchor(
    AppData appData,
    GameSprite sprite, {
    int? frameIndex,
    int? totalFrames,
    Size? frameSize,
  }) {
    final GameAnimation? animation = spriteAnimation(appData, sprite);
    if (animation == null) {
      return const Offset(
        GameAnimation.defaultAnchorX,
        GameAnimation.defaultAnchorY,
      );
    }
    final Size resolvedFrameSize =
        frameSize ?? spriteFrameSize(appData, sprite);
    final int resolvedTotalFrames = totalFrames ??
        _spriteTotalFramesForAnchorResolution(
          appData,
          sprite,
          resolvedFrameSize,
        );
    final int resolvedFrameIndex = frameIndex ??
        spriteFrameIndex(
          appData: appData,
          sprite: sprite,
          totalFrames: resolvedTotalFrames,
        );
    final GameAnimationFrameRig rig = animation.rigForFrame(resolvedFrameIndex);
    return Offset(
      rig.anchorX.clamp(0.0, 1.0),
      rig.anchorY.clamp(0.0, 1.0),
    );
  }

  static Rect spriteWorldRect(
    AppData appData,
    GameSprite sprite, {
    Size? frameSize,
    int? frameIndex,
    int? totalFrames,
  }) {
    final Size size = frameSize ?? spriteFrameSize(appData, sprite);
    final Offset anchor = spriteAnchor(
      appData,
      sprite,
      frameIndex: frameIndex,
      totalFrames: totalFrames,
      frameSize: size,
    );
    final double left = sprite.x.toDouble() - (size.width * anchor.dx);
    final double top = sprite.y.toDouble() - (size.height * anchor.dy);
    return Rect.fromLTWH(left, top, size.width, size.height);
  }

  static int spriteFrameIndex({
    required AppData appData,
    required GameSprite sprite,
    required int totalFrames,
  }) {
    final int safeTotal = math.max(1, totalFrames);
    final GameAnimation? animation = spriteAnimation(appData, sprite);
    if (animation == null) {
      return appData.frame % safeTotal;
    }

    final int start = animation.startFrame.clamp(0, safeTotal - 1);
    final int end = animation.endFrame.clamp(start, safeTotal - 1);
    final int span = math.max(1, end - start + 1);
    final int ticks =
        ((appData.frame / _editorTicksPerSecond) * animation.fps).floor();
    final int offset =
        animation.loop ? ticks % span : math.min(ticks, span - 1);
    return start + offset;
  }

  static int spriteFrameColumnsFromImage({
    required ui.Image image,
    required Size frameSize,
  }) {
    final double frameWidth = frameSize.width;
    if (frameWidth <= 0) {
      return 1;
    }
    return math.max(1, (image.width / frameWidth).floor());
  }

  static int spriteFrameRowsFromImage({
    required ui.Image image,
    required Size frameSize,
  }) {
    final double frameHeight = frameSize.height;
    if (frameHeight <= 0) {
      return 1;
    }
    return math.max(1, (image.height / frameHeight).floor());
  }

  static int spriteTotalFramesFromImage({
    required ui.Image image,
    required Size frameSize,
  }) {
    final int cols = spriteFrameColumnsFromImage(
      image: image,
      frameSize: frameSize,
    );
    final int rows = spriteFrameRowsFromImage(
      image: image,
      frameSize: frameSize,
    );
    return math.max(1, cols * rows);
  }

  static Rect spriteSourceRectForFrame({
    required ui.Image image,
    required Size frameSize,
    required int frameIndex,
  }) {
    final double frameWidth = frameSize.width;
    final double frameHeight = frameSize.height;
    if (frameWidth <= 0 || frameHeight <= 0) {
      return Rect.zero;
    }
    final int cols = spriteFrameColumnsFromImage(
      image: image,
      frameSize: frameSize,
    );
    final int totalFrames = spriteTotalFramesFromImage(
      image: image,
      frameSize: frameSize,
    );
    final int safeFrame = frameIndex.clamp(0, totalFrames - 1);
    final int col = safeFrame % cols;
    final int row = safeFrame ~/ cols;
    return Rect.fromLTWH(
      col * frameWidth,
      row * frameHeight,
      frameWidth,
      frameHeight,
    );
  }

  static int animationPlaybackFrameIndex({
    required AppData appData,
    required GameAnimation animation,
    required int totalFrames,
    bool forceLoop = false,
  }) {
    final int safeTotal = math.max(1, totalFrames);
    final int start = animation.startFrame.clamp(0, safeTotal - 1);
    final int end = animation.endFrame.clamp(start, safeTotal - 1);
    final int span = math.max(1, end - start + 1);
    final int ticks =
        ((appData.frame / _editorTicksPerSecond) * animation.fps).floor();
    final int offset = (forceLoop || animation.loop)
        ? ticks % span
        : math.min(ticks, span - 1);
    return start + offset;
  }

  static List<int> _framesInAnimationRange({
    required GameAnimation animation,
    required int totalFrames,
  }) {
    final int safeTotal = math.max(1, totalFrames);
    final int animationStart = animation.startFrame.clamp(0, safeTotal - 1);
    final int animationEnd =
        animation.endFrame.clamp(animationStart, safeTotal - 1);
    return List<int>.generate(
      animationEnd - animationStart + 1,
      (int index) => animationStart + index,
      growable: false,
    );
  }

  static List<int> _uniqueFramesInRange({
    required Iterable<int> frames,
    required int start,
    required int end,
  }) {
    final Set<int> seen = <int>{};
    final List<int> ordered = <int>[];
    for (final int frame in frames) {
      if (frame < start || frame > end) {
        continue;
      }
      if (seen.add(frame)) {
        ordered.add(frame);
      }
    }
    return ordered;
  }

  static bool _doubleNearEqual(double a, double b) {
    return (a - b).abs() <= 0.000001;
  }

  static bool _rigHitBoxEquivalent(dynamic a, dynamic b) {
    final double ax = (a.x as num).toDouble();
    final double ay = (a.y as num).toDouble();
    final double aw = (a.width as num).toDouble();
    final double ah = (a.height as num).toDouble();
    final double bx = (b.x as num).toDouble();
    final double by = (b.y as num).toDouble();
    final double bw = (b.width as num).toDouble();
    final double bh = (b.height as num).toDouble();
    return a.id == b.id &&
        a.name == b.name &&
        a.color == b.color &&
        _doubleNearEqual(ax, bx) &&
        _doubleNearEqual(ay, by) &&
        _doubleNearEqual(aw, bw) &&
        _doubleNearEqual(ah, bh);
  }

  static bool _rigEquivalent(
    GameAnimationFrameRig left,
    GameAnimationFrameRig right,
  ) {
    if (!_doubleNearEqual(left.anchorX, right.anchorX) ||
        !_doubleNearEqual(left.anchorY, right.anchorY) ||
        left.anchorColor != right.anchorColor ||
        left.hitBoxes.length != right.hitBoxes.length) {
      return false;
    }
    for (int i = 0; i < left.hitBoxes.length; i++) {
      if (!_rigHitBoxEquivalent(left.hitBoxes[i], right.hitBoxes[i])) {
        return false;
      }
    }
    return true;
  }

  static List<int> defaultAnimationRigSelectedFrames({
    required GameAnimation animation,
    required int totalFrames,
  }) {
    final List<int> frames = _framesInAnimationRange(
      animation: animation,
      totalFrames: totalFrames,
    );
    if (frames.isEmpty) {
      return const <int>[];
    }
    if (frames.length == 1) {
      return frames;
    }
    final GameAnimationFrameRig firstRig = animation.rigForFrame(frames.first);
    bool allFramesMatch = true;
    for (int i = 1; i < frames.length; i++) {
      final GameAnimationFrameRig nextRig = animation.rigForFrame(frames[i]);
      if (!_rigEquivalent(firstRig, nextRig)) {
        allFramesMatch = false;
        break;
      }
    }
    if (allFramesMatch) {
      return frames;
    }
    return <int>[frames.first];
  }

  static bool _intListEquals(List<int> a, List<int> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool setAnimationRigSelectedFrames({
    required AppData appData,
    required GameAnimation animation,
    required Iterable<int> frames,
    required int totalFrames,
    bool setActiveToFirst = true,
  }) {
    final List<int> validFrames = _framesInAnimationRange(
      animation: animation,
      totalFrames: totalFrames,
    );
    if (validFrames.isEmpty) {
      return false;
    }
    final int animationStart = validFrames.first;
    final int animationEnd = validFrames.last;
    List<int> nextFrames = _uniqueFramesInRange(
      frames: frames,
      start: animationStart,
      end: animationEnd,
    );
    if (nextFrames.isEmpty) {
      nextFrames = defaultAnimationRigSelectedFrames(
        animation: animation,
        totalFrames: totalFrames,
      );
      nextFrames = _uniqueFramesInRange(
        frames: nextFrames,
        start: animationStart,
        end: animationEnd,
      );
    }
    if (nextFrames.isEmpty) {
      nextFrames = <int>[animationStart];
    }
    int nextStart = nextFrames.first;
    int nextEnd = nextFrames.first;
    for (int i = 1; i < nextFrames.length; i++) {
      final int frame = nextFrames[i];
      if (frame < nextStart) {
        nextStart = frame;
      }
      if (frame > nextEnd) {
        nextEnd = frame;
      }
    }
    final int currentActive = appData.animationRigActiveFrame;
    final int nextActive = setActiveToFirst
        ? nextFrames.first
        : (nextFrames.contains(currentActive)
            ? currentActive
            : nextFrames.first);

    final bool changed = !_intListEquals(
          appData.animationRigSelectedFrames,
          nextFrames,
        ) ||
        appData.animationRigSelectionAnimationId != animation.id ||
        appData.animationRigSelectionStartFrame != nextStart ||
        appData.animationRigSelectionEndFrame != nextEnd ||
        appData.animationRigActiveFrame != nextActive;
    if (!changed) {
      return false;
    }
    appData.animationRigSelectedFrames = List<int>.from(
      nextFrames,
      growable: false,
    );
    appData.animationRigSelectionAnimationId = animation.id;
    appData.animationRigSelectionStartFrame = nextStart;
    appData.animationRigSelectionEndFrame = nextEnd;
    appData.animationRigActiveFrame = nextActive;
    return true;
  }

  static List<int> animationRigSelectedFrames({
    required AppData appData,
    required GameAnimation animation,
    required int totalFrames,
    bool writeBack = false,
  }) {
    final List<int> validFrames = _framesInAnimationRange(
      animation: animation,
      totalFrames: totalFrames,
    );
    if (validFrames.isEmpty) {
      return const <int>[];
    }
    final int animationStart = validFrames.first;
    final int animationEnd = validFrames.last;
    final bool sameAnimationSelection =
        appData.animationRigSelectionAnimationId == animation.id;

    List<int> selected = sameAnimationSelection
        ? _uniqueFramesInRange(
            frames: appData.animationRigSelectedFrames,
            start: animationStart,
            end: animationEnd,
          )
        : <int>[];
    if (selected.isEmpty && sameAnimationSelection) {
      final int selectedStart = appData.animationRigSelectionStartFrame;
      final int selectedEnd = appData.animationRigSelectionEndFrame;
      if (selectedStart >= 0 && selectedEnd >= 0) {
        final int rangeStart = math
            .min(selectedStart, selectedEnd)
            .clamp(animationStart, animationEnd);
        final int rangeEnd = math
            .max(selectedStart, selectedEnd)
            .clamp(animationStart, animationEnd);
        selected = List<int>.generate(
          rangeEnd - rangeStart + 1,
          (int index) => rangeStart + index,
          growable: false,
        );
      }
    }
    if (selected.isEmpty) {
      selected = defaultAnimationRigSelectedFrames(
        animation: animation,
        totalFrames: totalFrames,
      );
      selected = _uniqueFramesInRange(
        frames: selected,
        start: animationStart,
        end: animationEnd,
      );
    }
    if (selected.isEmpty) {
      selected = <int>[animationStart];
    }
    if (writeBack) {
      setAnimationRigSelectedFrames(
        appData: appData,
        animation: animation,
        frames: selected,
        totalFrames: totalFrames,
        setActiveToFirst: false,
      );
    }
    return List<int>.from(
      selected,
      growable: false,
    );
  }

  static int animationRigPlaybackFrameIndex({
    required AppData appData,
    required GameAnimation animation,
    required int totalFrames,
  }) {
    final List<int> selectedFrames = animationRigSelectedFrames(
      appData: appData,
      animation: animation,
      totalFrames: totalFrames,
      writeBack: true,
    );
    if (selectedFrames.isEmpty) {
      final List<int> validFrames = _framesInAnimationRange(
        animation: animation,
        totalFrames: totalFrames,
      );
      return validFrames.isEmpty ? 0 : validFrames.first;
    }
    return selectedFrames.first;
  }

  static Future<ui.Image> drawCanvasImageEmpty(AppData appData) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Cal dibuixar algo perquè "recorder" no falli
    canvas.drawRect(
        Rect.fromLTWH(0, 0, 10, 10), Paint()..color = Colors.transparent);

    final picture = recorder.endRecording();
    return await picture.toImage(10, 10);
  }

  static Future<ui.Image> drawCanvasImageLayers(
      AppData appData, bool drawGrid) async {
    if (appData.selectedLevel == -1) {
      return await drawCanvasImageEmpty(appData);
    }

    final level = appData.gameData.levels[appData.selectedLevel];
    final recorder = ui.PictureRecorder();
    final imgCanvas = Canvas(recorder);

    int imageWidth = 10;
    int imageHeight = 10;

    // Draw level layers (painter order): last list item first, first item last.
    for (int layerIndex = level.layers.length - 1;
        layerIndex >= 0;
        layerIndex--) {
      final layer = level.layers[layerIndex];
      if (layer.visible == false) {
        continue;
      }
      final tilemapImage = await generateTilemapImage(
          appData, appData.selectedLevel, layerIndex, drawGrid);

      imgCanvas.drawImage(tilemapImage,
          Offset(layer.x.toDouble(), layer.y.toDouble()), Paint());

      imageWidth = imageWidth > (layer.x + tilemapImage.width)
          ? imageWidth
          : (layer.x + tilemapImage.width);
      imageHeight = imageHeight > (layer.y + tilemapImage.height)
          ? imageHeight
          : (layer.y + tilemapImage.height);
    }

    // Draw level zones
    for (int cntZone = 0; cntZone < level.zones.length; cntZone = cntZone + 1) {
      final zone = level.zones[cntZone];
      final zoneX = zone.x.toDouble();
      final zoneY = zone.y.toDouble();
      final zoneWidth = zone.width.toDouble();
      final zoneHeight = zone.height.toDouble();
      imgCanvas.drawRect(Rect.fromLTWH(zoneX, zoneY, zoneWidth, zoneHeight),
          Paint()..color = getColorFromName(zone.color).withAlpha(100));
      if (appData.selectedSection == "zones" &&
          cntZone == appData.selectedZone) {
        drawSelectedRect(
          imgCanvas,
          Rect.fromLTWH(zoneX, zoneY, zoneWidth, zoneHeight),
          getColorFromName(zone.color),
        );
      }
    }

    // Draw sprites
    for (int cntSprite = 0;
        cntSprite < level.sprites.length;
        cntSprite = cntSprite + 1) {
      final sprite = level.sprites[cntSprite];
      final String imageFile = spriteImageFile(appData, sprite);
      if (imageFile.isEmpty) {
        continue;
      }
      final spriteImage = await appData.getImage(imageFile);
      final Size frameSize = spriteFrameSize(appData, sprite);
      final double spriteWidth = frameSize.width;
      final double spriteHeight = frameSize.height;
      final int frames = spriteTotalFramesFromImage(
        image: spriteImage,
        frameSize: frameSize,
      );
      final int frameIndex = spriteFrameIndex(
        appData: appData,
        sprite: sprite,
        totalFrames: frames,
      );
      final Rect worldRect = spriteWorldRect(
        appData,
        sprite,
        frameSize: frameSize,
        frameIndex: frameIndex,
        totalFrames: frames,
      );
      final double spriteX = worldRect.left;
      final double spriteY = worldRect.top;

      final Rect srcRect = spriteSourceRectForFrame(
        image: spriteImage,
        frameSize: frameSize,
        frameIndex: frameIndex,
      );
      final Rect dstRect =
          Rect.fromLTWH(spriteX, spriteY, spriteWidth, spriteHeight);
      if (sprite.flipX || sprite.flipY) {
        final double centerX = dstRect.center.dx;
        final double centerY = dstRect.center.dy;
        imgCanvas.save();
        imgCanvas.translate(centerX, centerY);
        imgCanvas.scale(
          sprite.flipX ? -1.0 : 1.0,
          sprite.flipY ? -1.0 : 1.0,
        );
        imgCanvas.translate(-centerX, -centerY);
        imgCanvas.drawImageRect(spriteImage, srcRect, dstRect, Paint());
        imgCanvas.restore();
      } else {
        imgCanvas.drawImageRect(spriteImage, srcRect, dstRect, Paint());
      }
      if (appData.selectedSection == "sprites" &&
          cntSprite == appData.selectedSprite) {
        drawSelectedRect(
            imgCanvas,
            Rect.fromLTWH(spriteX, spriteY, spriteWidth, spriteHeight),
            Colors.blue);
      }
    }

    // Draw selected layer border (if in "layers")
    if (appData.selectedLayer != -1 && appData.selectedSection == "layers") {
      final layer = level.layers[appData.selectedLayer];
      final selectedX = (layer.x + 1).toDouble();
      final selectedY = (layer.y + 1).toDouble();
      final selectedWidth =
          (layer.tileMap[0].length * layer.tilesWidth - 2).toDouble();
      final selectedHeight =
          (layer.tileMap.length * layer.tilesHeight - 2).toDouble();
      drawSelectedRect(
        imgCanvas,
        Rect.fromLTWH(selectedX, selectedY, selectedWidth, selectedHeight),
        Colors.blue,
      );
    }

    final picture = recorder.endRecording();
    return await picture.toImage(imageWidth, imageHeight);
  }

  static Future<ui.Image> drawCanvasImageTilemap(AppData appData) async {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) {
      return await drawCanvasImageEmpty(appData);
    }

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];

    await appData.getImage(layer.tilesSheetFile);

    // Main canvas renders only the tilemap; tileset is handled in right sidebar.
    final ui.Image tilemapImage = await generateTilemapImage(
      appData,
      appData.selectedLevel,
      appData.selectedLayer,
      true,
    );
    appData.tilemapOffset = Offset.zero;
    appData.tilemapScaleFactor = 1.0;
    return tilemapImage;
  }

  static Future<ui.Image> drawCanvasImageMedia(AppData appData) async {
    if (appData.selectedMedia < 0 ||
        appData.selectedMedia >= appData.gameData.mediaAssets.length) {
      return await drawCanvasImageEmpty(appData);
    }

    final asset = appData.gameData.mediaAssets[appData.selectedMedia];
    final ui.Image image = await appData.getImage(asset.fileName);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    if (asset.hasTileGrid && asset.tileWidth > 0 && asset.tileHeight > 0) {
      final Paint gridPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      for (int x = 0; x <= image.width; x += asset.tileWidth) {
        canvas.drawLine(
          Offset(x.toDouble(), 0),
          Offset(x.toDouble(), image.height.toDouble()),
          gridPaint,
        );
      }

      for (int y = 0; y <= image.height; y += asset.tileHeight) {
        canvas.drawLine(
          Offset(0, y.toDouble()),
          Offset(image.width.toDouble(), y.toDouble()),
          gridPaint,
        );
      }
    }

    final picture = recorder.endRecording();
    return await picture.toImage(image.width, image.height);
  }

  static Future<ui.Image> drawCanvasImageAnimations(AppData appData) async {
    if (appData.selectedAnimation < 0 ||
        appData.selectedAnimation >= appData.gameData.animations.length) {
      return await drawCanvasImageEmpty(appData);
    }

    final GameAnimation animation =
        appData.gameData.animations[appData.selectedAnimation];
    if (animation.mediaFile.trim().isEmpty) {
      return await drawCanvasImageEmpty(appData);
    }

    ui.Image image;
    try {
      image = await appData.getImage(animation.mediaFile);
    } catch (_) {
      return await drawCanvasImageEmpty(appData);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    final _AnimationGridInfo? gridInfo =
        await _selectedAnimationGridInfo(appData);
    if (gridInfo != null) {
      final double tileWidth = gridInfo.media.tileWidth.toDouble();
      final double tileHeight = gridInfo.media.tileHeight.toDouble();
      final int cols = gridInfo.cols;
      final int start = animation.startFrame.clamp(0, gridInfo.totalFrames - 1);
      final int end = animation.endFrame.clamp(start, gridInfo.totalFrames - 1);

      final Paint gridPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      for (int x = 0; x <= image.width; x += gridInfo.media.tileWidth) {
        canvas.drawLine(
          Offset(x.toDouble(), 0),
          Offset(x.toDouble(), image.height.toDouble()),
          gridPaint,
        );
      }
      for (int y = 0; y <= image.height; y += gridInfo.media.tileHeight) {
        canvas.drawLine(
          Offset(0, y.toDouble()),
          Offset(image.width.toDouble(), y.toDouble()),
          gridPaint,
        );
      }

      final Paint rangeFill = Paint()
        ..color = Colors.orange.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      final Paint rangeStroke = Paint()
        ..color = Colors.orange
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      for (int frame = start; frame <= end; frame++) {
        final int row = frame ~/ cols;
        final int col = frame % cols;
        final Rect rect = Rect.fromLTWH(
            col * tileWidth, row * tileHeight, tileWidth, tileHeight);
        canvas.drawRect(rect, rangeFill);
        canvas.drawRect(rect, rangeStroke);
      }

      if (hasAnimationFrameSelection(appData)) {
        final int selectedStart = appData.animationSelectionStartFrame
            .clamp(0, gridInfo.totalFrames - 1);
        final int selectedEnd = appData.animationSelectionEndFrame
            .clamp(selectedStart, gridInfo.totalFrames - 1);
        final Paint selectedStroke = Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        for (int frame = selectedStart; frame <= selectedEnd; frame++) {
          final int row = frame ~/ cols;
          final int col = frame % cols;
          final Rect rect = Rect.fromLTWH(
            col * tileWidth,
            row * tileHeight,
            tileWidth,
            tileHeight,
          );
          canvas.drawRect(rect, selectedStroke);
        }
      }
    }

    final picture = recorder.endRecording();
    return await picture.toImage(image.width, image.height);
  }

  static Future<ui.Image> drawCanvasImageAnimationRig(AppData appData) async {
    final _AnimationGridInfo? gridInfo =
        await _selectedAnimationGridInfo(appData);
    if (gridInfo == null) {
      appData.animationRigActiveFrame = -1;
      return await drawCanvasImageEmpty(appData);
    }

    final int frameIndex = animationRigPlaybackFrameIndex(
      appData: appData,
      animation: gridInfo.animation,
      totalFrames: gridInfo.totalFrames,
    );
    appData.animationRigActiveFrame = frameIndex;
    final int row = frameIndex ~/ gridInfo.cols;
    final int col = frameIndex % gridInfo.cols;
    final double frameWidth = gridInfo.media.tileWidth.toDouble();
    final double frameHeight = gridInfo.media.tileHeight.toDouble();
    final Rect src = Rect.fromLTWH(
      col * frameWidth,
      row * frameHeight,
      frameWidth,
      frameHeight,
    );
    if (src.right > gridInfo.image.width ||
        src.bottom > gridInfo.image.height) {
      return await drawCanvasImageEmpty(appData);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      gridInfo.image,
      src,
      Rect.fromLTWH(0, 0, frameWidth, frameHeight),
      Paint()..filterQuality = FilterQuality.none,
    );
    final picture = recorder.endRecording();
    return await picture.toImage(frameWidth.ceil(), frameHeight.ceil());
  }

  static Offset translateCoords(
      Offset coords, Offset offset, double scaleFactor) {
    return Offset(
      (coords.dx - offset.dx) / scaleFactor,
      (coords.dy - offset.dy) / scaleFactor,
    );
  }

  static double pathPointHandleRadiusWorld(
    AppData appData, {
    double screenRadius = 8.0,
  }) {
    final double scale = appData.scaleFactor <= 0 ? 1.0 : appData.scaleFactor;
    return (screenRadius / scale).clamp(4.0 / scale, 20.0 / scale);
  }

  static int pathPointIndexFromPosition(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return -1;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    if (appData.selectedPath < 0 ||
        appData.selectedPath >= level.paths.length) {
      return -1;
    }
    final GamePath path = level.paths[appData.selectedPath];
    if (path.points.isEmpty) {
      return -1;
    }
    final Offset worldCoords = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final double hitRadius = pathPointHandleRadiusWorld(
      appData,
      screenRadius: 12.0,
    );
    final double hitRadiusSquared = hitRadius * hitRadius;
    for (int i = path.points.length - 1; i >= 0; i--) {
      final GamePathPoint point = path.points[i];
      final double dx = worldCoords.dx - point.x.toDouble();
      final double dy = worldCoords.dy - point.y.toDouble();
      if ((dx * dx) + (dy * dy) <= hitRadiusSquared) {
        return i;
      }
    }
    return -1;
  }

  static bool dragSelectedPathPointFromCanvas(
    AppData appData, {
    required int pointIndex,
    required Offset localPosition,
  }) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    if (appData.selectedPath < 0 ||
        appData.selectedPath >= level.paths.length) {
      return false;
    }
    final GamePath path = level.paths[appData.selectedPath];
    if (pointIndex < 0 || pointIndex >= path.points.length) {
      return false;
    }
    final Offset worldCoords = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final int nextX = worldCoords.dx.round();
    final int nextY = worldCoords.dy.round();
    final GamePathPoint point = path.points[pointIndex];
    if (point.x == nextX && point.y == nextY) {
      return false;
    }
    point.x = nextX;
    point.y = nextY;
    return true;
  }

  static Future<int> tileIndexFromTilesetCoords(
      Offset coords, AppData appData, GameLayer layer) async {
    final tilesheetImage = await appData.getImage(layer.tilesSheetFile);

    double imageWidth = tilesheetImage.width.toDouble();
    double imageHeight = tilesheetImage.height.toDouble();

    // Si està fora dels límits del tileset, retornem -1
    if (coords.dx < 0 ||
        coords.dy < 0 ||
        coords.dx >= imageWidth ||
        coords.dy >= imageHeight) {
      return -1;
    }

    // Calcular la columna i la fila del tile
    int col = (coords.dx / layer.tilesWidth).floor();
    int row = (coords.dy / layer.tilesHeight).floor();

    int tilesetColumns = (imageWidth / layer.tilesWidth).floor();

    // Retornar l'índex del tile dins del tileset
    return row * tilesetColumns + col;
  }

  static Future<void> selectTileIndexFromTileset(
      AppData appData, Offset localPosition) async {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) {
      return;
    }

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];

    if (layer.tilesWidth <= 0 || layer.tilesHeight <= 0) {
      return;
    }

    // Convertir de coordenades de canvas a coordenades d'imatge
    Offset imageCoords = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);

    // Convertir de coordenades d'imatge a coordenades del tileset
    Offset tilesetCoords = translateCoords(
        imageCoords, appData.tilesetOffset, appData.tilesetScaleFactor);

    int index = await tileIndexFromTilesetCoords(tilesetCoords, appData, layer);

    if (index != -1) {
      if (index != appData.selectedTileIndex) {
        appData.selectedTileIndex = index;
      } else {
        appData.selectedTileIndex = -1;
      }
    }
  }

  static Future<void> dragTileIndexFromTileset(
      AppData appData, Offset localPosition) async {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) {
      return;
    }

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];

    if (layer.tilesWidth <= 0 || layer.tilesHeight <= 0) {
      return;
    }

    // Convertir de coordenades de canvas a coordenades d'imatge
    Offset imageCoords = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);

    // Convertir de coordenades d'imatge a coordenades del tileset
    Offset tilesetCoords = translateCoords(
        imageCoords, appData.tilesetOffset, appData.tilesetScaleFactor);

    appData.draggingTileIndex =
        await tileIndexFromTilesetCoords(tilesetCoords, appData, layer);
    appData.draggingOffset = localPosition;
  }

  static int zoneIndexFromPosition(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1) {
      return -1;
    }
    final Offset levelCoords = LayoutUtils.translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);
    final zones = appData.gameData.levels[appData.selectedLevel].zones;
    for (int i = zones.length - 1; i >= 0; i--) {
      final zone = zones[i];
      final rect = Rect.fromLTWH(zone.x.toDouble(), zone.y.toDouble(),
          zone.width.toDouble(), zone.height.toDouble());
      if (rect.contains(levelCoords)) {
        return i;
      }
    }
    return -1;
  }

  static double zoneResizeHandleSizeWorld(AppData appData) {
    final double scale = appData.scaleFactor <= 0 ? 1.0 : appData.scaleFactor;
    return (14.0 / scale).clamp(6.0, 24.0);
  }

  static bool isPointInZoneResizeHandle(
      AppData appData, int zoneIndex, Offset localPosition) {
    if (appData.selectedLevel == -1) {
      return false;
    }
    final zones = appData.gameData.levels[appData.selectedLevel].zones;
    if (zoneIndex < 0 || zoneIndex >= zones.length) {
      return false;
    }
    final zone = zones[zoneIndex];
    final double right = zone.x.toDouble() + zone.width.toDouble();
    final double bottom = zone.y.toDouble() + zone.height.toDouble();
    final Offset levelCoords = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final double maxHandle = math.min(
      zone.width.toDouble().abs(),
      zone.height.toDouble().abs(),
    );
    final double handleSize =
        math.min(zoneResizeHandleSizeWorld(appData), maxHandle);
    if (handleSize <= 0) {
      return false;
    }
    final bool inBounds = levelCoords.dx >= right - handleSize &&
        levelCoords.dx <= right &&
        levelCoords.dy >= bottom - handleSize &&
        levelCoords.dy <= bottom;
    if (!inBounds) {
      return false;
    }
    return levelCoords.dx + levelCoords.dy >= right + bottom - handleSize;
  }

  static void selectZoneFromPosition(AppData appData, Offset localPosition,
      GlobalKey<LayoutZonesState> layoutZonesKey) {
    final int hitIndex = zoneIndexFromPosition(appData, localPosition);
    if (hitIndex == -1) {
      layoutZonesKey.currentState?.selectZone(appData, -1, false);
      return;
    }
    // Canvas clicks should select the hit zone directly. Deselect only on
    // empty-space clicks.
    layoutZonesKey.currentState?.selectZone(appData, hitIndex, false);
  }

  static void startDragZoneFromPosition(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1) {
      appData.zoneDragOffset = Offset.zero;
      return;
    }
    final int hitIndex = zoneIndexFromPosition(appData, localPosition);
    if (hitIndex == -1) {
      appData.zoneDragOffset = Offset.zero;
      return;
    }
    final Offset levelCoords = LayoutUtils.translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);
    final zone = appData.gameData.levels[appData.selectedLevel].zones[hitIndex];
    appData.pushUndo();
    appData.zoneDragOffset =
        levelCoords - Offset(zone.x.toDouble(), zone.y.toDouble());
  }

  static void startResizeZoneFromPosition(
      AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedZone == -1) {
      appData.zoneDragOffset = Offset.zero;
      return;
    }
    final zones = appData.gameData.levels[appData.selectedLevel].zones;
    if (appData.selectedZone < 0 || appData.selectedZone >= zones.length) {
      appData.zoneDragOffset = Offset.zero;
      return;
    }
    final Offset levelCoords = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final zone = zones[appData.selectedZone];
    final Offset zoneBottomRight = Offset(
      zone.x.toDouble() + zone.width.toDouble(),
      zone.y.toDouble() + zone.height.toDouble(),
    );
    appData.pushUndo();
    appData.zoneDragOffset = levelCoords - zoneBottomRight;
  }

  static void dragZoneFromCanvas(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedZone == -1) return;
    Offset levelCoords = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);
    GameZone zone = appData
        .gameData.levels[appData.selectedLevel].zones[appData.selectedZone];
    zone.x = (levelCoords.dx - appData.zoneDragOffset.dx).toInt();
    zone.y = (levelCoords.dy - appData.zoneDragOffset.dy).toInt();
  }

  static void resizeZoneFromCanvas(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedZone == -1) return;
    final zones = appData.gameData.levels[appData.selectedLevel].zones;
    if (appData.selectedZone < 0 || appData.selectedZone >= zones.length) {
      return;
    }
    final Offset levelCoords = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final GameZone zone = zones[appData.selectedZone];
    final Offset bottomRight = levelCoords - appData.zoneDragOffset;
    zone.width = math.max(1, (bottomRight.dx - zone.x.toDouble()).round());
    zone.height = math.max(1, (bottomRight.dy - zone.y.toDouble()).round());
  }

  static int spriteIndexFromPosition(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1) {
      return -1;
    }
    final sprites = appData.gameData.levels[appData.selectedLevel].sprites;
    for (int i = sprites.length - 1; i >= 0; i--) {
      final sprite = sprites[i];
      final Offset levelCoords = LayoutUtils.translateCoords(
        localPosition,
        _depthProjectionImageOffsetForSprite(appData, sprite),
        _depthProjectionScaleFactorForSprite(appData, sprite),
      );
      final Size frameSize = spriteFrameSize(appData, sprite);
      final Rect rect = spriteWorldRect(
        appData,
        sprite,
        frameSize: frameSize,
      );
      if (rect.contains(levelCoords)) {
        return i;
      }
    }
    return -1;
  }

  static bool hitTestSelectedSprite(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedSprite == -1) {
      return false;
    }
    final sprites = appData.gameData.levels[appData.selectedLevel].sprites;
    if (appData.selectedSprite < 0 ||
        appData.selectedSprite >= sprites.length) {
      return false;
    }
    return spriteIndexFromPosition(appData, localPosition) ==
        appData.selectedSprite;
  }

  static void selectSpriteFromPosition(
    AppData appData,
    Offset localPosition,
    GlobalKey<LayoutSpritesState> layoutSpritesKey,
  ) {
    final int hitIndex = spriteIndexFromPosition(appData, localPosition);
    if (hitIndex == -1) {
      layoutSpritesKey.currentState?.selectSprite(appData, -1, false);
      return;
    }
    // Canvas clicks should select the hit sprite directly. Deselect only on
    // empty-space clicks.
    layoutSpritesKey.currentState?.selectSprite(appData, hitIndex, false);
  }

  static void startDragSpriteFromPosition(
      AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedSprite == -1) {
      appData.spriteDragOffset = Offset.zero;
      return;
    }
    final sprites = appData.gameData.levels[appData.selectedLevel].sprites;
    if (appData.selectedSprite < 0 ||
        appData.selectedSprite >= sprites.length) {
      appData.spriteDragOffset = Offset.zero;
      return;
    }
    final Offset levelCoords = LayoutUtils.translateCoords(
      localPosition,
      _depthProjectionImageOffsetForSprite(
          appData, sprites[appData.selectedSprite]),
      _depthProjectionScaleFactorForSprite(
          appData, sprites[appData.selectedSprite]),
    );
    final sprite = sprites[appData.selectedSprite];
    appData.pushUndo();
    appData.spriteDragOffset =
        levelCoords - Offset(sprite.x.toDouble(), sprite.y.toDouble());
  }

  static void dragSpriteFromCanvas(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedSprite == -1) return;
    final GameSprite sprite = appData
        .gameData.levels[appData.selectedLevel].sprites[appData.selectedSprite];
    final Offset levelCoords = translateCoords(
      localPosition,
      _depthProjectionImageOffsetForSprite(appData, sprite),
      _depthProjectionScaleFactorForSprite(appData, sprite),
    );
    sprite.x = (levelCoords.dx - appData.spriteDragOffset.dx).toInt();
    sprite.y = (levelCoords.dy - appData.spriteDragOffset.dy).toInt();
  }

  // ── Viewport drag ────────────────────────────────────────────────────────

  /// Ensures the ephemeral preview viewport is synced to the selected level.
  static void ensureViewportPreviewInitialized(
    AppData appData, {
    bool force = false,
  }) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      appData.viewportPreviewLevel = -1;
      appData.viewportIsDragging = false;
      appData.viewportIsResizing = false;
      appData.viewportDragOffset = Offset.zero;
      appData.viewportResizeOffset = Offset.zero;
      return;
    }
    if (!force && appData.viewportPreviewLevel == appData.selectedLevel) {
      return;
    }
    final level = appData.gameData.levels[appData.selectedLevel];
    appData.viewportPreviewX = level.viewportX;
    appData.viewportPreviewY = level.viewportY;
    appData.viewportPreviewWidth = level.viewportWidth;
    appData.viewportPreviewHeight = level.viewportHeight;
    appData.viewportPreviewLevel = appData.selectedLevel;
    appData.viewportIsDragging = false;
    appData.viewportIsResizing = false;
    appData.viewportDragOffset = Offset.zero;
    appData.viewportResizeOffset = Offset.zero;
  }

  /// Returns true if [localPosition] (screen space) is inside the viewport rect.
  static bool isPointInViewportRect(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    ensureViewportPreviewInitialized(appData);
    final Offset world = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);
    final Rect rect = Rect.fromLTWH(
      appData.viewportPreviewX.toDouble(),
      appData.viewportPreviewY.toDouble(),
      appData.viewportPreviewWidth.toDouble(),
      appData.viewportPreviewHeight.toDouble(),
    );
    return rect.contains(world);
  }

  static double viewportResizeHandleSizeWorld(AppData appData) {
    final double scale = appData.scaleFactor <= 0 ? 1.0 : appData.scaleFactor;
    return 14.0 / scale;
  }

  static bool isPointInViewportResizeHandle(
      AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    ensureViewportPreviewInitialized(appData);
    final Offset world = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final double width = appData.viewportPreviewWidth.toDouble();
    final double height = appData.viewportPreviewHeight.toDouble();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final double right = appData.viewportPreviewX.toDouble() + width;
    final double bottom = appData.viewportPreviewY.toDouble() + height;
    final double maxHandleSize = width < height ? width : height;
    final double handleSize =
        viewportResizeHandleSizeWorld(appData).clamp(0, maxHandleSize);
    if (handleSize <= 0) {
      return false;
    }
    final bool inBounds = world.dx >= right - handleSize &&
        world.dx <= right &&
        world.dy >= bottom - handleSize &&
        world.dy <= bottom;
    if (!inBounds) {
      return false;
    }
    return world.dx + world.dy >= right + bottom - handleSize;
  }

  /// Initialises a viewport drag. Records offset from viewport top-left to
  /// the grab point so the rect doesn't jump.
  static void startDragViewportFromPosition(
      AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1) return;
    ensureViewportPreviewInitialized(appData);
    final Offset world = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);
    appData.viewportDragOffset = world -
        Offset(
          appData.viewportPreviewX.toDouble(),
          appData.viewportPreviewY.toDouble(),
        );
    appData.viewportIsDragging = true;
    appData.viewportIsResizing = false;
  }

  static void startResizeViewportFromPosition(
      AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    ensureViewportPreviewInitialized(appData);
    final Offset world = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final Offset previewCorner = Offset(
      appData.viewportPreviewX + appData.viewportPreviewWidth.toDouble(),
      appData.viewportPreviewY + appData.viewportPreviewHeight.toDouble(),
    );
    appData.viewportResizeOffset = previewCorner - world;
    appData.viewportIsResizing = true;
    appData.viewportIsDragging = false;
  }

  /// Updates the live drag position. Does NOT modify level.viewportX/Y.
  static void dragViewportFromCanvas(AppData appData, Offset localPosition) {
    if (!appData.viewportIsDragging) return;
    final Offset world = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);
    appData.viewportPreviewX =
        (world.dx - appData.viewportDragOffset.dx).round();
    appData.viewportPreviewY =
        (world.dy - appData.viewportDragOffset.dy).round();
  }

  static void resizeViewportFromCanvas(AppData appData, Offset localPosition) {
    if (!appData.viewportIsResizing) return;
    final Offset world = translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final Offset corner = world + appData.viewportResizeOffset;
    final int width = (corner.dx - appData.viewportPreviewX).round();
    final int height = (corner.dy - appData.viewportPreviewY).round();
    appData.viewportPreviewWidth = width.clamp(1, 99999);
    appData.viewportPreviewHeight = height.clamp(1, 99999);
  }

  /// Clears drag-only state while keeping preview position.
  static void endViewportDrag(AppData appData) {
    if (!appData.viewportIsDragging && !appData.viewportIsResizing) return;
    appData.viewportIsDragging = false;
    appData.viewportIsResizing = false;
    appData.viewportDragOffset = Offset.zero;
    appData.viewportResizeOffset = Offset.zero;
  }

  /// Hit-tests visible layers (topmost first) and returns the index of the first
  /// layer whose bounds contain [localPosition], or -1 if none.
  static int selectLayerFromPosition(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1) return -1;
    final layers = appData.gameData.levels[appData.selectedLevel].layers;
    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.visible) continue;
      if (layer.tileMap.isEmpty || layer.tileMap.first.isEmpty) continue;
      final Offset worldPos = translateCoords(
        localPosition,
        _depthProjectionImageOffsetForLayer(appData, layer),
        _depthProjectionScaleFactorForLayer(appData, layer),
      );
      final double w =
          (layer.tileMap.first.length * layer.tilesWidth).toDouble();
      final double h = (layer.tileMap.length * layer.tilesHeight).toDouble();
      final Rect bounds =
          Rect.fromLTWH(layer.x.toDouble(), layer.y.toDouble(), w, h);
      if (bounds.contains(worldPos)) return i;
    }
    return -1;
  }

  /// Returns true if [localPosition] (screen coords) hits the selected layer's bounds.
  static bool hitTestSelectedLayer(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) {
      return false;
    }
    final layer = appData
        .gameData.levels[appData.selectedLevel].layers[appData.selectedLayer];
    if (!layer.visible) return false;
    if (layer.tileMap.isEmpty || layer.tileMap.first.isEmpty) return false;
    final Offset worldPos = translateCoords(
      localPosition,
      _depthProjectionImageOffsetForLayer(appData, layer),
      _depthProjectionScaleFactorForLayer(appData, layer),
    );
    final double w = (layer.tileMap.first.length * layer.tilesWidth).toDouble();
    final double h = (layer.tileMap.length * layer.tilesHeight).toDouble();
    final Rect bounds =
        Rect.fromLTWH(layer.x.toDouble(), layer.y.toDouble(), w, h);
    return bounds.contains(worldPos);
  }

  /// Start dragging the selected layer: record cursor offset relative to layer origin.
  static void startDragLayerFromPosition(
      AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) return;
    final layer = appData
        .gameData.levels[appData.selectedLevel].layers[appData.selectedLayer];
    final Offset worldPos = translateCoords(
      localPosition,
      _depthProjectionImageOffsetForLayer(appData, layer),
      _depthProjectionScaleFactorForLayer(appData, layer),
    );
    appData.pushUndo();
    appData.layerDragOffset =
        worldPos - Offset(layer.x.toDouble(), layer.y.toDouble());
  }

  /// Move the selected layer to follow the cursor.
  static void dragLayerFromCanvas(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) return;
    final layers = appData.gameData.levels[appData.selectedLevel].layers;
    final GameLayer old = layers[appData.selectedLayer];
    final Offset worldPos = translateCoords(
      localPosition,
      _depthProjectionImageOffsetForLayer(appData, old),
      _depthProjectionScaleFactorForLayer(appData, old),
    );
    final int newX = (worldPos.dx - appData.layerDragOffset.dx).round();
    final int newY = (worldPos.dy - appData.layerDragOffset.dy).round();
    layers[appData.selectedLayer] = GameLayer(
      name: old.name,
      gameplayData: old.gameplayData,
      x: newX,
      y: newY,
      depth: old.depth,
      tilesSheetFile: old.tilesSheetFile,
      tilesWidth: old.tilesWidth,
      tilesHeight: old.tilesHeight,
      tileMap: old.tileMap,
      visible: old.visible,
      groupId: old.groupId,
    );
  }

  static Offset? getTilemapCoords(AppData appData, Offset localPosition) {
    if (appData.selectedLevel == -1 || appData.selectedLayer == -1) {
      return null;
    }

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];
    if (layer.tileMap.isEmpty || layer.tileMap.first.isEmpty) {
      return null;
    }

    if (layer.tilesWidth <= 0 || layer.tilesHeight <= 0) {
      return null;
    }

    if (appData.selectedSection == "tilemap") {
      final Offset worldCoords = translateCoords(
        localPosition,
        _depthProjectionImageOffsetForLayer(appData, layer),
        _depthProjectionScaleFactorForLayer(appData, layer),
      );
      final double localX = worldCoords.dx - layer.x;
      final double localY = worldCoords.dy - layer.y;

      final double tilemapWidth =
          layer.tilesWidth * layer.tileMap[0].length.toDouble();
      final double tilemapHeight =
          layer.tilesHeight * layer.tileMap.length.toDouble();
      if (localX < 0 ||
          localY < 0 ||
          localX >= tilemapWidth ||
          localY >= tilemapHeight) {
        return null;
      }

      final int col = (localX / layer.tilesWidth).floor();
      final int row = (localY / layer.tilesHeight).floor();
      return Offset(row.toDouble(), col.toDouble());
    }

    // Convertir de coordenades de canvas a coordenades d'imatge
    Offset imageCoords = translateCoords(
        localPosition, appData.imageOffset, appData.scaleFactor);

    // Convertir de coordenades d'imatge a coordenades del tilemap
    Offset tilemapCoords = translateCoords(
        imageCoords, appData.tilemapOffset, appData.tilemapScaleFactor);

    double tilemapWidth = layer.tilesWidth * layer.tileMap[0].length.toDouble();
    double tilemapHeight = layer.tilesHeight * layer.tileMap.length.toDouble();

    // Verificar si està fora dels límits del tilemap
    if (tilemapCoords.dx < 0 ||
        tilemapCoords.dy < 0 ||
        tilemapCoords.dx >= tilemapWidth ||
        tilemapCoords.dy >= tilemapHeight) {
      return null;
    }

    // Calcular la fila i columna al tilemap
    int col = (tilemapCoords.dx / layer.tilesWidth).floor();
    int row = (tilemapCoords.dy / layer.tilesHeight).floor();

    return Offset(row.toDouble(), col.toDouble());
  }

  static void dropTileIndexFromTileset(AppData appData, Offset localPosition) {
    Offset? tileCoords = getTilemapCoords(appData, localPosition);
    if (tileCoords == null) return;

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];

    int row = tileCoords.dx.toInt();
    int col = tileCoords.dy.toInt();

    appData.pushUndo();
    layer.tileMap[row][col] = appData.draggingTileIndex;
  }

  static bool hasTilePatternSelection(AppData appData) {
    return appData.selectedTilePattern.isNotEmpty;
  }

  static bool pasteSelectedTilePatternAtTilemap(
    AppData appData,
    Offset localPosition, {
    bool pushUndo = false,
  }) {
    final Offset? tileCoords = getTilemapCoords(appData, localPosition);
    if (tileCoords == null) return false;
    if (!hasTilePatternSelection(appData)) return false;

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];
    final int startRow = tileCoords.dx.toInt();
    final int startCol = tileCoords.dy.toInt();
    final List<List<int>> pattern = appData.selectedTilePattern;

    bool changed = false;
    bool pushed = false;
    for (int row = 0; row < pattern.length; row++) {
      final int destRow = startRow + row;
      if (destRow < 0 || destRow >= layer.tileMap.length) continue;
      final List<int> patternRow = pattern[row];
      for (int col = 0; col < patternRow.length; col++) {
        final int destCol = startCol + col;
        if (destCol < 0 || destCol >= layer.tileMap[destRow].length) continue;
        final int index = patternRow[col];
        if (index < 0) continue;
        if (layer.tileMap[destRow][destCol] == index) continue;
        if (pushUndo && !pushed) {
          appData.pushUndo();
          pushed = true;
        }
        layer.tileMap[destRow][destCol] = index;
        changed = true;
      }
    }

    return changed;
  }

  static bool eraseTileAtTilemap(
    AppData appData,
    Offset localPosition, {
    bool pushUndo = false,
  }) {
    final Offset? tileCoords = getTilemapCoords(appData, localPosition);
    if (tileCoords == null) return false;

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];
    final int row = tileCoords.dx.toInt();
    final int col = tileCoords.dy.toInt();

    if (layer.tileMap[row][col] == -1) {
      return false;
    }
    if (pushUndo) {
      appData.pushUndo();
    }
    layer.tileMap[row][col] = -1;
    return true;
  }

  static void setSelectedTileIndexFromTileset(
      AppData appData, Offset localPosition) {
    Offset? tileCoords = getTilemapCoords(appData, localPosition);
    if (tileCoords == null) return;

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];

    int row = tileCoords.dx.toInt();
    int col = tileCoords.dy.toInt();

    int index = appData.selectedTileIndex;

    appData.pushUndo();
    if (layer.tileMap[row][col] != index) {
      layer.tileMap[row][col] = index;
    } else {
      layer.tileMap[row][col] = -1;
    }
  }

  static void removeTileIndexFromTileset(
      AppData appData, Offset localPosition) {
    Offset? tileCoords = getTilemapCoords(appData, localPosition);
    if (tileCoords == null) return;

    final level = appData.gameData.levels[appData.selectedLevel];
    final layer = level.layers[appData.selectedLayer];

    int row = tileCoords.dx.toInt();
    int col = tileCoords.dy.toInt();

    appData.pushUndo();
    layer.tileMap[row][col] = -1;
  }

  static Color getColorFromName(String colorName) {
    switch (colorName) {
      case "blue":
        return Colors.blue;
      case "blueAccent":
        return Colors.blueAccent;
      case "green":
        return Colors.green;
      case "greenAccent":
        return Colors.greenAccent;
      case "yellow":
        return Colors.yellow;
      case "yellowAccent":
        return Colors.yellowAccent;
      case "orange":
        return Colors.orange;
      case "orangeAccent":
        return Colors.orangeAccent;
      case "red":
        return Colors.red;
      case "redAccent":
        return Colors.redAccent;
      case "deepPurple":
        return Colors.deepPurple;
      case "purpleAccent":
        return Colors.purpleAccent;
      case "purple":
        return Colors.purple;
      case "pink":
        return Colors.pink;
      case "pinkAccent":
        return Colors.pinkAccent;
      case "indigo":
        return Colors.indigo;
      case "teal":
        return Colors.teal;
      case "tealAccent":
        return Colors.tealAccent;
      case "cyan":
        return Colors.cyan;
      case "cyanAccent":
        return Colors.cyanAccent;
      case "lightBlue":
        return Colors.lightBlue;
      case "lightGreen":
        return Colors.lightGreen;
      case "lime":
        return Colors.lime;
      case "amber":
        return Colors.amber;
      case "deepOrange":
        return Colors.deepOrange;
      case "brown":
        return Colors.brown;
      case "blueGrey":
        return Colors.blueGrey;
      case "grey":
        return Colors.grey;
      case "white":
        return Colors.white;
      default:
        return Colors.black;
    }
  }

  static void drawSelectedRect(Canvas cnv, Rect rect, Color color) {
    cnv.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}

class _AnimationGridInfo {
  const _AnimationGridInfo({
    required this.animation,
    required this.media,
    required this.image,
    required this.cols,
    required this.rows,
    required this.totalFrames,
  });

  final GameAnimation animation;
  final GameMediaAsset media;
  final ui.Image image;
  final int cols;
  final int rows;
  final int totalFrames;
}
