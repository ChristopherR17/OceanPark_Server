import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerPanZoomEndEvent,
        PointerPanZoomStartEvent,
        PointerPanZoomUpdateEvent,
        PointerScaleEvent,
        PointerScrollEvent,
        PointerUpEvent,
        kSecondaryMouseButton;
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        KeyUpEvent,
        LogicalKeyboardKey;
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'canvas_painter.dart';
import 'game_animation.dart';
import 'game_animation_hit_box.dart';
import 'game_layer.dart';
import 'game_level.dart';
import 'game_list_group.dart';
import 'game_media_asset.dart';
import 'game_media_group.dart';
import 'game_path.dart';
import 'game_path_binding.dart';
import 'game_sprite.dart';
import 'game_zone.dart';
import 'game_zone_group.dart';
import 'layout_animation_rigs.dart';
import 'layout_animations.dart';
import 'layout_layers.dart';
import 'layout_levels.dart';
import 'layout_media.dart';
import 'layout_paths.dart';
import 'layout_projects.dart';
import 'layout_projects_main.dart';
import 'layout_sprites.dart';
import 'layout_tilemaps.dart';
import 'layout_zones.dart';
import 'layout_viewport.dart';
import 'layout_utils.dart';

part 'layout_painters.dart';
part 'layout_part_navigation.dart';
part 'layout_part_animation_rig_helpers.dart';
part 'layout_part_layer_selection.dart';
part 'layout_part_zone_selection.dart';
part 'layout_part_sprite_selection.dart';
part 'layout_part_viewport_tools.dart';
part 'layout_part_animation_rig_ui.dart';
part 'layout_part_gestures.dart';
part 'layout_part_clipboard.dart';

class Layout extends StatefulWidget {
  const Layout({super.key, required this.title});

  final String title;

  @override
  State<Layout> createState() => _LayoutState();
}

class _LayoutState extends State<Layout> {
  static const double _animationRigFrameStripReservedHeight = 74.0;
  static const double _editToolbarExpandedWidth = 275.0;
  static const double _rightToolbarWidth = 275.0;
  static const double _trackpadInertiaDecayPerSecond = 7.5;
  static const double _trackpadInertiaMinStartSpeed = 600.0;
  static const double _trackpadInertiaStopSpeed = 30.0;
  final ScrollController _editToolbarScrollController = ScrollController();

  // Clau del layout escollit
  final GlobalKey<LayoutSpritesState> layoutSpritesKey =
      GlobalKey<LayoutSpritesState>();
  final GlobalKey<LayoutZonesState> layoutZonesKey =
      GlobalKey<LayoutZonesState>();
  final GlobalKey<LayoutViewportState> layoutViewportKey =
      GlobalKey<LayoutViewportState>();
  final GlobalKey<LayoutLayersState> layoutLayersKey =
      GlobalKey<LayoutLayersState>();
  final GlobalKey<LayoutLevelsState> layoutLevelsKey =
      GlobalKey<LayoutLevelsState>();
  final GlobalKey<LayoutPathsState> layoutPathsKey =
      GlobalKey<LayoutPathsState>();
  final GlobalKey<LayoutAnimationRigsState> layoutAnimationRigsKey =
      GlobalKey<LayoutAnimationRigsState>();
  final GlobalKey _layoutAnimationsKey = GlobalKey();
  final GlobalKey _layoutMediaKey = GlobalKey();
  final GlobalKey _animationRigFrameStripRowKey = GlobalKey();

  // ignore: unused_field
  Timer? _timer;
  ui.Image? _layerImage;
  bool _isDraggingLayer = false;
  bool _isDraggingViewport = false;
  bool _isResizingViewport = false;
  bool _isDraggingZone = false;
  bool _isResizingZone = false;
  bool _isDraggingSprite = false;
  bool _isDraggingPathPoint = false;
  bool _isSelectingAnimationFrames = false;
  bool _isPaintingTilemap = false;
  bool _consumeTilemapTapUp = false;
  bool _didModifyZoneDuringGesture = false;
  bool _didModifySpriteDuringGesture = false;
  bool _didModifyPathDuringGesture = false;
  bool _didModifyLayerDuringGesture = false;
  bool _didModifyAnimationDuringGesture = false;
  bool _didModifyAnimationRigDuringGesture = false;
  bool _didModifyTilemapDuringGesture = false;
  int? _animationDragStartFrame;
  bool _isDraggingAnimationRigAnchor = false;
  bool _isDraggingAnimationRigHitBox = false;
  bool _isResizingAnimationRigHitBox = false;
  int _draggingPathPointIndex = -1;
  bool _isSelectingAnimationRigFramesFromStrip = false;
  bool _animationRigFrameStripDragAdditive = false;
  int? _animationRigFrameStripDragAnchorFrame;
  List<int> _animationRigFrameStripDragBaseSelection = <int>[];
  Offset _animationRigHitBoxDragOffset = Offset.zero;
  int _drawCanvasRequestId = 0;
  bool _isPointerDown = false;
  double _lastTrackpadScale = 1.0;
  Duration? _lastTrackpadPanTimeStamp;
  Offset _trackpadPanVelocity = Offset.zero;
  Ticker? _trackpadInertiaTicker;
  Duration? _trackpadInertiaLastElapsed;
  int? _secondaryMousePanPointer;
  bool _isHoveringSelectedTilemapLayer = false;
  bool _isDragGestureActive = false;
  bool _pendingLayersViewportCenter = false;
  int? _pendingLevelsViewportFitLevelIndex;
  int? _lastAutoFramedLevelIndex;
  bool _selectionModifierControlPressed = false;
  bool _selectionModifierMetaPressed = false;
  final Set<int> _selectedLayerIndices = <int>{};
  final Map<int, Offset> _layerDragOffsetsByIndex = <int, Offset>{};
  int _layerSelectionLevelIndex = -1;
  bool _isMarqueeSelectingLayers = false;
  bool _marqueeSelectionAdditive = false;
  Offset? _layersMarqueeStartLocal;
  Offset? _layersMarqueeCurrentLocal;
  Set<int> _marqueeBaseLayerSelection = <int>{};
  final Set<int> _selectedZoneIndices = <int>{};
  final Map<int, Offset> _zoneDragOffsetsByIndex = <int, Offset>{};
  int _zoneSelectionLevelIndex = -1;
  bool _isMarqueeSelectingZones = false;
  bool _zoneMarqueeSelectionAdditive = false;
  Offset? _zonesMarqueeStartLocal;
  Offset? _zonesMarqueeCurrentLocal;
  Set<int> _marqueeBaseZoneSelection = <int>{};
  final Set<int> _selectedSpriteIndices = <int>{};
  final Map<int, Offset> _spriteDragOffsetsByIndex = <int, Offset>{};
  int _spriteSelectionLevelIndex = -1;
  bool _isMarqueeSelectingSprites = false;
  bool _spriteMarqueeSelectionAdditive = false;
  Offset? _spritesMarqueeStartLocal;
  Offset? _spritesMarqueeCurrentLocal;
  Set<int> _marqueeBaseSpriteSelection = <int>{};
  _EditorClipboardPayload? _clipboardPayload;
  String _clipboardStatusMessage = '';
  bool _clipboardStatusIsError = false;
  bool _clipboardStatusIsWarning = false;
  Timer? _clipboardStatusTimer;
  final FocusNode _focusNode = FocusNode();
  List<String> sections = [
    'projects',
    'media',
    'animations',
    'animation_rigs',
    'levels',
    'layers',
    'tilemap',
    'zones',
    'sprites',
    'paths',
    'viewport',
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _refreshSelectionModifierState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appData = Provider.of<AppData>(context, listen: false);
      appData.selectedSection = 'projects';
      _focusNode.requestFocus();
    });

    _startFrameTimer();
  }

  void _startFrameTimer() {
    _timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      final appData = Provider.of<AppData>(context, listen: false);
      appData.frame++;
      if (appData.frame > 4096) {
        appData.frame = 0;
      }
      if (appData.selectedSection != 'animation_rigs') {
        appData.update();
      }
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    setState(fn);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _trackpadInertiaTicker?.dispose();
    try {
      final appData = Provider.of<AppData>(context, listen: false);
      unawaited(appData.flushPendingAutosave());
    } catch (_) {}
    _timer?.cancel();
    _clipboardStatusTimer?.cancel();
    _editToolbarScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    _updateSelectionModifierStateFromEvent(event);
    if (event is! KeyDownEvent || !mounted) {
      return false;
    }
    final bool meta = HardwareKeyboard.instance.isMetaPressed;
    final bool ctrl = HardwareKeyboard.instance.isControlPressed;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    final bool isCopy = event.logicalKey == LogicalKeyboardKey.keyC;
    final bool isPaste = event.logicalKey == LogicalKeyboardKey.keyV;
    final bool isUndoRedo = event.logicalKey == LogicalKeyboardKey.keyZ;
    if ((meta || ctrl) &&
        !shift &&
        isCopy &&
        (!_isTextInputFocused() || !_shouldDeferCopyShortcutToTextField())) {
      try {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        _handleCopyShortcut(appData);
        return true;
      } catch (_) {
        return false;
      }
    }
    if ((meta || ctrl) && !shift && isPaste) {
      try {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        if (!_isTextInputFocused() ||
            !_shouldDeferPasteShortcutToTextField(appData)) {
          unawaited(_handlePasteShortcut(appData));
          return true;
        }
      } catch (_) {
        return false;
      }
    }
    if ((meta || ctrl) && isUndoRedo) {
      try {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        if (shift) {
          appData.redo();
        } else {
          appData.undo();
        }
        return true;
      } catch (_) {
        return false;
      }
    }
    final bool isDeleteKey = event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (isDeleteKey && !_isTextInputFocused()) {
      try {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        switch (appData.selectedSection) {
          case 'layers':
            unawaited(_confirmAndDeleteSelectedLayers(appData));
            return true;
          case 'levels':
            final LayoutLevelsState? state = layoutLevelsKey.currentState;
            if (state == null) {
              return false;
            }
            unawaited(state.confirmAndDeleteSelectedLevelFromKeyboard(appData));
            return true;
          case 'zones':
            final LayoutZonesState? state = layoutZonesKey.currentState;
            if (state == null) {
              return false;
            }
            unawaited(state.confirmAndDeleteSelectedZoneFromKeyboard(appData));
            return true;
          case 'sprites':
            final LayoutSpritesState? state = layoutSpritesKey.currentState;
            if (state == null) {
              return false;
            }
            unawaited(
              state.confirmAndDeleteSelectedSpriteFromKeyboard(appData),
            );
            return true;
          case 'paths':
            final LayoutPathsState? state = layoutPathsKey.currentState;
            if (state == null) {
              return false;
            }
            unawaited(state.confirmAndDeleteSelectedPathFromKeyboard(appData));
            return true;
          case 'animations':
            final dynamic state = _layoutAnimationsKey.currentState;
            if (state == null) {
              return false;
            }
            unawaited(
              (state as dynamic)
                  .confirmAndDeleteSelectedAnimationFromKeyboard(appData),
            );
            return true;
          case 'media':
            final dynamic state = _layoutMediaKey.currentState;
            if (state == null) {
              return false;
            }
            unawaited(
              (state as dynamic).confirmAndDeleteSelectedMediaFromKeyboard(
                appData,
              ),
            );
            return true;
          default:
            return false;
        }
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  void _updateSelectionModifierStateFromEvent(KeyEvent event) {
    final bool? pressed = switch (event) {
      KeyDownEvent() => true,
      KeyRepeatEvent() => true,
      KeyUpEvent() => false,
      _ => null,
    };
    if (pressed == null) {
      return;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (_isControlModifierKey(key)) {
      _selectionModifierControlPressed = pressed;
    }
    if (_isMetaModifierKey(key)) {
      _selectionModifierMetaPressed = pressed;
    }
  }

  bool _isControlModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight;
  }

  bool _isMetaModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.superKey;
  }

  bool _isPlatformShortcutModifierPressed() {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _selectionModifierMetaPressed || keyboard.isMetaPressed;
    }
    return _selectionModifierControlPressed || keyboard.isControlPressed;
  }

  void _refreshSelectionModifierState() {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final Set<LogicalKeyboardKey> pressed = keyboard.logicalKeysPressed;
    _selectionModifierControlPressed = keyboard.isControlPressed ||
        pressed.contains(LogicalKeyboardKey.control) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    _selectionModifierMetaPressed = keyboard.isMetaPressed ||
        pressed.contains(LogicalKeyboardKey.meta) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.superKey);
  }

  Future<void> _drawCanvasImage(AppData appData) async {
    final int requestId = ++_drawCanvasRequestId;
    ui.Image image;
    switch (appData.selectedSection) {
      case 'projects':
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'levels':
        // Levels section renders in world space via CanvasPainter.
        await LayoutUtils.preloadLayerImages(appData);
        await LayoutUtils.preloadSpriteImages(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'layers':
        // Layers section renders directly in world space via CanvasPainter.
        // Preload tileset and sprite images for the preview.
        await LayoutUtils.preloadLayerImages(appData);
        await LayoutUtils.preloadSpriteImages(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'tilemap':
        // Tilemap section now renders in world space via CanvasPainter.
        await LayoutUtils.preloadLayerImages(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'zones':
        // Zones section reuses the world viewport rendering from layers.
        await LayoutUtils.preloadLayerImages(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'sprites':
        await LayoutUtils.preloadLayerImages(appData);
        await LayoutUtils.preloadSpriteImages(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'paths':
        await LayoutUtils.preloadLayerImages(appData);
        await LayoutUtils.preloadSpriteImages(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'viewport':
        // Viewport section renders in world space via CanvasPainter.
        await LayoutUtils.preloadLayerImages(appData);
        await LayoutUtils.preloadSpriteImages(appData);
        LayoutUtils.ensureViewportPreviewInitialized(appData);
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
      case 'animations':
        image = await LayoutUtils.drawCanvasImageAnimations(appData);
      case 'animation_rigs':
        image = await LayoutUtils.drawCanvasImageAnimationRig(appData);
      case 'media':
        image = await LayoutUtils.drawCanvasImageMedia(appData);
      default:
        image = await LayoutUtils.drawCanvasImageEmpty(appData);
    }

    if (!mounted || requestId != _drawCanvasRequestId) {
      return;
    }
    setState(() {
      _layerImage = image;
    });
  }

  void _applyLayersZoom(AppData appData, Offset cursor, double scrollDy) {
    if (scrollDy == 0) return;
    const double zoomSensitivity = 0.01;
    const double minScale = 0.05;
    const double maxScale = 20.0;
    final double oldScale = appData.layersViewScale;
    final double newScale = (oldScale * (1.0 - scrollDy * zoomSensitivity))
        .clamp(minScale, maxScale);
    appData.layersViewOffset =
        cursor + (appData.layersViewOffset - cursor) * (newScale / oldScale);
    appData.layersViewScale = newScale;
    appData.update();
  }

  void _applyLayersPinchZoom(
      AppData appData, Offset cursor, double scaleDelta) {
    if (scaleDelta <= 0 || (scaleDelta - 1.0).abs() < 0.0001) {
      return;
    }
    const double minScale = 0.05;
    const double maxScale = 20.0;
    final double oldScale = appData.layersViewScale;
    final double newScale = (oldScale * scaleDelta).clamp(minScale, maxScale);
    appData.layersViewOffset =
        cursor + (appData.layersViewOffset - cursor) * (newScale / oldScale);
    appData.layersViewScale = newScale;
    appData.update();
  }

  void _panWorldViewport(AppData appData, Offset delta) {
    if (delta == Offset.zero ||
        !_usesWorldViewportSection(appData.selectedSection)) {
      return;
    }
    appData.layersViewOffset += delta;
    appData.update();
  }

  Offset _scaleOffset(Offset offset, double factor) {
    return Offset(offset.dx * factor, offset.dy * factor);
  }

  void _stopTrackpadInertia({bool resetVelocity = true}) {
    _trackpadInertiaTicker?.stop();
    _trackpadInertiaLastElapsed = null;
    if (resetVelocity) {
      _trackpadPanVelocity = Offset.zero;
      _lastTrackpadPanTimeStamp = null;
    }
  }

  void _recordTrackpadPanVelocitySample(PointerPanZoomUpdateEvent event) {
    if (event.panDelta == Offset.zero) {
      return;
    }
    final Duration? previousTimeStamp = _lastTrackpadPanTimeStamp;
    _lastTrackpadPanTimeStamp = event.timeStamp;
    if (previousTimeStamp == null) {
      return;
    }
    final int deltaMicros =
        event.timeStamp.inMicroseconds - previousTimeStamp.inMicroseconds;
    if (deltaMicros <= 0) {
      return;
    }
    final double dtSeconds = deltaMicros / Duration.microsecondsPerSecond;
    final Offset sampleVelocity = Offset(
      event.panDelta.dx / dtSeconds,
      event.panDelta.dy / dtSeconds,
    );
    final bool hadVelocity = _trackpadPanVelocity != Offset.zero;
    _trackpadPanVelocity = Offset.lerp(
          _trackpadPanVelocity,
          sampleVelocity,
          hadVelocity ? 0.35 : 1.0,
        ) ??
        sampleVelocity;
  }

  void _startTrackpadInertia(AppData appData) {
    if (_trackpadPanVelocity.distance < _trackpadInertiaMinStartSpeed) {
      _stopTrackpadInertia();
      return;
    }
    _trackpadInertiaTicker ??= Ticker((Duration elapsed) {
      if (!mounted) {
        _stopTrackpadInertia();
        return;
      }
      if (_trackpadInertiaLastElapsed == null) {
        _trackpadInertiaLastElapsed = elapsed;
        return;
      }
      final int elapsedMicros =
          elapsed.inMicroseconds - _trackpadInertiaLastElapsed!.inMicroseconds;
      _trackpadInertiaLastElapsed = elapsed;
      if (elapsedMicros <= 0) {
        return;
      }
      final double dtSeconds = elapsedMicros / Duration.microsecondsPerSecond;
      _panWorldViewport(appData, _scaleOffset(_trackpadPanVelocity, dtSeconds));
      final double decay =
          math.exp(-_trackpadInertiaDecayPerSecond * dtSeconds);
      _trackpadPanVelocity = _scaleOffset(_trackpadPanVelocity, decay);
      if (_trackpadPanVelocity.distance < _trackpadInertiaStopSpeed) {
        _stopTrackpadInertia();
      }
    });
    _trackpadInertiaLastElapsed = null;
    _trackpadInertiaTicker!.start();
  }

  void _handlePointerDownForViewportPan(
    AppData appData,
    PointerDownEvent event,
  ) {
    _stopTrackpadInertia();
    if (event.kind != ui.PointerDeviceKind.mouse ||
        !_usesWorldViewportSection(appData.selectedSection) ||
        (event.buttons & kSecondaryMouseButton) == 0) {
      return;
    }
    _secondaryMousePanPointer = event.pointer;
  }

  void _handlePointerMoveForViewportPan(
    AppData appData,
    PointerMoveEvent event,
  ) {
    if (_secondaryMousePanPointer != event.pointer ||
        event.kind != ui.PointerDeviceKind.mouse ||
        (event.buttons & kSecondaryMouseButton) == 0) {
      return;
    }
    _panWorldViewport(appData, event.delta);
  }

  void _handlePointerUpForViewportPan(PointerUpEvent event) {
    if (_secondaryMousePanPointer == event.pointer) {
      _secondaryMousePanPointer = null;
    }
  }

  void _handlePointerCancelForViewportPan(PointerCancelEvent event) {
    if (_secondaryMousePanPointer == event.pointer) {
      _secondaryMousePanPointer = null;
    }
  }

  void _handleTrackpadPanZoomUpdate(
    AppData appData,
    PointerPanZoomUpdateEvent event,
  ) {
    if (!_usesWorldViewportSection(appData.selectedSection)) {
      return;
    }
    final double scaleDelta = event.scale / _lastTrackpadScale;
    _lastTrackpadScale = event.scale;
    final bool hasPinchScale = (scaleDelta - 1.0).abs() >= 0.0001;

    if (event.panDelta != Offset.zero) {
      _recordTrackpadPanVelocitySample(event);
      _panWorldViewport(appData, event.panDelta);
    }
    if (!hasPinchScale) {
      return;
    }
    _applyLayersPinchZoom(appData, event.localPosition, scaleDelta);
  }

  void _handleTrackpadScaleSignal(
    AppData appData,
    PointerScaleEvent event,
  ) {
    if (!_usesWorldViewportSection(appData.selectedSection)) {
      return;
    }
    _stopTrackpadInertia();
    _applyLayersPinchZoom(appData, event.localPosition, event.scale);
  }

  Future<void> _autoSaveIfPossible(AppData appData) async {
    if (appData.selectedProject == null) {
      return;
    }
    appData.queueAutosave();
  }

  bool _showEditToolbarForSelection(AppData appData) {
    switch (appData.selectedSection) {
      case 'projects':
        return false;
      case 'media':
        return appData.selectedMedia >= 0 &&
            appData.selectedMedia < appData.gameData.mediaAssets.length;
      case 'animations':
      case 'animation_rigs':
        return appData.selectedAnimation >= 0 &&
            appData.selectedAnimation < appData.gameData.animations.length;
      case 'levels':
        return appData.selectedLevel >= 0 &&
            appData.selectedLevel < appData.gameData.levels.length;
      case 'layers':
        if (appData.selectedLevel < 0 ||
            appData.selectedLevel >= appData.gameData.levels.length) {
          return false;
        }
        final int layerCount =
            appData.gameData.levels[appData.selectedLevel].layers.length;
        final Set<int> selected = appData.selectedLayerIndices
            .where((index) => index >= 0 && index < layerCount)
            .toSet();
        if (selected.isEmpty &&
            appData.selectedLayer >= 0 &&
            appData.selectedLayer < layerCount) {
          selected.add(appData.selectedLayer);
        }
        return selected.length == 1;
      case 'tilemap':
      case 'viewport':
        return false;
      case 'zones':
        if (appData.selectedLevel < 0 ||
            appData.selectedLevel >= appData.gameData.levels.length) {
          return false;
        }
        final int zoneCount =
            appData.gameData.levels[appData.selectedLevel].zones.length;
        final Set<int> selected = appData.selectedZoneIndices
            .where((index) => index >= 0 && index < zoneCount)
            .toSet();
        if (selected.isEmpty &&
            appData.selectedZone >= 0 &&
            appData.selectedZone < zoneCount) {
          selected.add(appData.selectedZone);
        }
        return selected.length == 1;
      case 'sprites':
        if (appData.selectedLevel < 0 ||
            appData.selectedLevel >= appData.gameData.levels.length) {
          return false;
        }
        final int spriteCount =
            appData.gameData.levels[appData.selectedLevel].sprites.length;
        final Set<int> selected = appData.selectedSpriteIndices
            .where((index) => index >= 0 && index < spriteCount)
            .toSet();
        if (selected.isEmpty &&
            appData.selectedSprite >= 0 &&
            appData.selectedSprite < spriteCount) {
          selected.add(appData.selectedSprite);
        }
        return selected.length == 1;
      case 'paths':
        if (appData.selectedLevel < 0 ||
            appData.selectedLevel >= appData.gameData.levels.length) {
          return false;
        }
        final int pathCount =
            appData.gameData.levels[appData.selectedLevel].paths.length;
        return appData.selectedPath >= 0 && appData.selectedPath < pathCount;
      default:
        return false;
    }
  }

  Widget _buildEditToolbarContent(AppData appData) {
    switch (appData.selectedSection) {
      case 'media':
        final int index = appData.selectedMedia;
        if (index < 0 || index >= appData.gameData.mediaAssets.length) {
          return const SizedBox.shrink();
        }
        final GameMediaAsset asset = appData.gameData.mediaAssets[index];
        return MediaInlineEditPanel(
          key: ValueKey('media-inline-editor-${asset.fileName}-$index'),
          mediaIndex: index,
        );
      case 'animations':
        final int index = appData.selectedAnimation;
        if (index < 0 || index >= appData.gameData.animations.length) {
          return const SizedBox.shrink();
        }
        final GameAnimation animation = appData.gameData.animations[index];
        return AnimationInlineEditPanel(
          key: ValueKey('animation-inline-editor-${animation.id}-$index'),
          animationIndex: index,
        );
      case 'animation_rigs':
        final LayoutAnimationRigsState? state =
            layoutAnimationRigsKey.currentState;
        if (state == null) {
          return const SizedBox.shrink();
        }
        return state.buildEditToolbarContent(appData);
      case 'levels':
        final LayoutLevelsState? state = layoutLevelsKey.currentState;
        if (state == null) {
          return const SizedBox.shrink();
        }
        return state.buildEditToolbarContent(appData);
      case 'layers':
      case 'tilemap':
        final LayoutLayersState? state = layoutLayersKey.currentState;
        if (state == null) {
          return const SizedBox.shrink();
        }
        return state.buildEditToolbarContent(appData);
      case 'zones':
        final LayoutZonesState? state = layoutZonesKey.currentState;
        if (state == null) {
          return const SizedBox.shrink();
        }
        return state.buildEditToolbarContent(appData);
      case 'sprites':
        final LayoutSpritesState? state = layoutSpritesKey.currentState;
        if (state == null) {
          return const SizedBox.shrink();
        }
        return state.buildEditToolbarContent(appData);
      case 'paths':
        final LayoutPathsState? state = layoutPathsKey.currentState;
        if (state == null) {
          return const SizedBox.shrink();
        }
        return state.buildEditToolbarContent(appData);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appData = Provider.of<AppData>(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final bool isDarkTheme =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final Color statusBarDividerColor =
        isDarkTheme ? const Color(0xFF545458) : const Color(0xFFD1D1D6);
    final Color toolbarDividerColor =
        isDarkTheme ? const Color(0xFF545458) : const Color(0xFFD1D1D6);
    final Color toolbarShadowColor =
        isDarkTheme ? const Color(0x66000000) : const Color(0x24000000);
    final bool showEditToolbar = _showEditToolbarForSelection(appData);
    final bool useSharedEditToolbarScroll =
        appData.selectedSection != 'animation_rigs';
    final double editToolbarWidth =
        showEditToolbar ? _editToolbarExpandedWidth : 0.0;
    _syncLayerSelectionState(appData);
    _syncZoneSelectionState(appData);
    _syncSpriteSelectionState(appData);

    if (appData.selectedSection != 'projects') {
      _drawCanvasImage(appData);
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: CDKPickerButtonsSegmented(
            selectedIndex: _selectedSectionIndex(appData.selectedSection),
            options: _buildSegmentedOptions(context),
            onSelected: (index) => unawaited(
              _onTabSelected(appData, sections[index]),
            ),
          ),
        ),
        trailing: appData.autosaveInlineMessage.isEmpty
            ? null
            : SizedBox(
                width: 220,
                child: CDKText(
                  appData.autosaveInlineMessage,
                  role: CDKTextRole.caption,
                  color: appData.autosaveHasError
                      ? CupertinoColors.systemRed
                      : cdkColors.colorTextSecondary,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
      ),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          _updateSelectionModifierStateFromEvent(event);
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: appData.selectedSection == 'projects'
                          ? Container(
                              color: cdkColors.backgroundSecondary1,
                              child: const LayoutProjectsMain(),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final Size viewportSize = Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                );
                                _queueSelectedLevelViewportFit(
                                  appData,
                                  viewportSize,
                                );
                                _queueInitialLayersViewportCenter(
                                  appData,
                                  viewportSize,
                                );
                                return Container(
                                  color: cdkColors.backgroundSecondary1,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        bottom: appData.selectedSection ==
                                                "animation_rigs"
                                            ? _animationRigFrameStripReservedHeight
                                            : 0,
                                        child: Listener(
                                          onPointerDown:
                                              (PointerDownEvent event) {
                                            _isPointerDown = true;
                                            _focusNode.requestFocus();
                                            _refreshSelectionModifierState();
                                            _handlePointerDownForViewportPan(
                                              appData,
                                              event,
                                            );
                                          },
                                          onPointerMove:
                                              (PointerMoveEvent event) {
                                            _handlePointerMoveForViewportPan(
                                              appData,
                                              event,
                                            );
                                          },
                                          onPointerUp: (PointerUpEvent event) {
                                            _isPointerDown = false;
                                            _handlePointerUpForViewportPan(
                                              event,
                                            );
                                          },
                                          onPointerCancel:
                                              (PointerCancelEvent event) {
                                            _isPointerDown = false;
                                            _handlePointerCancelForViewportPan(
                                              event,
                                            );
                                          },
                                          onPointerPanZoomStart:
                                              (PointerPanZoomStartEvent _) {
                                            _stopTrackpadInertia();
                                            _lastTrackpadScale = 1.0;
                                            _lastTrackpadPanTimeStamp = null;
                                            _trackpadPanVelocity = Offset.zero;
                                          },
                                          onPointerPanZoomEnd:
                                              (PointerPanZoomEndEvent _) {
                                            _startTrackpadInertia(appData);
                                            _lastTrackpadScale = 1.0;
                                            _lastTrackpadPanTimeStamp = null;
                                          },
                                          onPointerSignal: (event) {
                                            if (event is PointerScaleEvent) {
                                              _handleTrackpadScaleSignal(
                                                appData,
                                                event,
                                              );
                                              return;
                                            }
                                            if (event is! PointerScrollEvent) {
                                              return;
                                            }
                                            if (event.kind !=
                                                ui.PointerDeviceKind.mouse) {
                                              return;
                                            }
                                            if (appData.selectedSection != "levels" &&
                                                appData.selectedSection !=
                                                    "layers" &&
                                                appData.selectedSection !=
                                                    "tilemap" &&
                                                appData.selectedSection !=
                                                    "zones" &&
                                                appData.selectedSection !=
                                                    "sprites" &&
                                                appData.selectedSection !=
                                                    "paths" &&
                                                appData.selectedSection !=
                                                    "viewport") {
                                              return;
                                            }
                                            _applyLayersZoom(
                                                appData,
                                                event.localPosition,
                                                event.scrollDelta.dy);
                                          },
                                          onPointerPanZoomUpdate:
                                              (PointerPanZoomUpdateEvent
                                                  event) {
                                            _handleTrackpadPanZoomUpdate(
                                              appData,
                                              event,
                                            );
                                          },
                                          child: MouseRegion(
                                            cursor: _tilemapCursor(appData),
                                            onHover: (event) {
                                              final bool hoveringTilemapLayer =
                                                  appData.selectedSection ==
                                                          'tilemap' &&
                                                      LayoutUtils.getTilemapCoords(
                                                              appData,
                                                              event
                                                                  .localPosition) !=
                                                          null;
                                              if (hoveringTilemapLayer !=
                                                  _isHoveringSelectedTilemapLayer) {
                                                setState(() {
                                                  _isHoveringSelectedTilemapLayer =
                                                      hoveringTilemapLayer;
                                                });
                                              }
                                            },
                                            onExit: (_) {
                                              if (_isHoveringSelectedTilemapLayer) {
                                                setState(() {
                                                  _isHoveringSelectedTilemapLayer =
                                                      false;
                                                });
                                              }
                                            },
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onPanStart: (details) =>
                                                  _handlePanStart(
                                                      appData, details),
                                              onPanUpdate: (details) =>
                                                  _handlePanUpdate(
                                                      appData, details),
                                              onPanEnd: (details) =>
                                                  _handlePanEnd(
                                                      appData, details),
                                              onTapDown: (details) =>
                                                  _handleTapDown(
                                                      appData, details),
                                              onTapUp: (details) =>
                                                  _handleTapUp(
                                                      appData, details),
                                              child: CustomPaint(
                                                painter: _layerImage != null
                                                    ? CanvasPainter(
                                                        _layerImage!,
                                                        appData,
                                                        selectedLayerIndices:
                                                            _selectedLayerIndices,
                                                      )
                                                    : null,
                                                child: Container(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (appData.selectedSection == "layers")
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _LayersMarqueePainter(
                                                rect: _layersMarqueeRect,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (appData.selectedSection == "zones")
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _LayersMarqueePainter(
                                                rect: _zonesMarqueeRect,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (appData.selectedSection == "sprites")
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _LayersMarqueePainter(
                                                rect: _spritesMarqueeRect,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_usesWorldViewportSection(
                                            appData.selectedSection,
                                          ) ||
                                          appData.selectedSection == "layers" ||
                                          appData.selectedSection == "zones" ||
                                          appData.selectedSection ==
                                              "tilemap" ||
                                          appData.selectedSection == "sprites")
                                        _buildWorldTopControlsOverlay(
                                          appData,
                                          viewportSize,
                                        ),
                                      if (appData.selectedSection ==
                                          "animation_rigs")
                                        _buildAnimationRigFrameStripOverlay(
                                          appData,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOutCubic,
                      width: editToolbarWidth,
                      decoration: BoxDecoration(
                        color: cdkColors.backgroundSecondary0,
                        border: Border(
                          left: BorderSide(
                            color: cdkColors.colorTextSecondary
                                .withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: _editToolbarExpandedWidth,
                          maxWidth: _editToolbarExpandedWidth,
                          child: SizedBox(
                            width: _editToolbarExpandedWidth,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: showEditToolbar
                                    ? KeyedSubtree(
                                        key: ValueKey<String>(
                                          'edit-toolbar-${appData.selectedSection}',
                                        ),
                                        child: useSharedEditToolbarScroll
                                            ? SingleChildScrollView(
                                                controller:
                                                    _editToolbarScrollController,
                                                primary: false,
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: _buildEditToolbarContent(
                                                  appData,
                                                ),
                                              )
                                            : _buildEditToolbarContent(appData),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey<String>(
                                          'edit-toolbar-empty',
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _rightToolbarWidth,
                        minWidth: _rightToolbarWidth,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cdkColors.background,
                          border: Border(
                            left: BorderSide(
                              color: toolbarDividerColor,
                              width: 1,
                            ),
                          ),
                          boxShadow: showEditToolbar
                              ? [
                                  BoxShadow(
                                    color: toolbarShadowColor,
                                    blurRadius: 10,
                                    offset: const Offset(-3, 0),
                                  ),
                                ]
                              : const [],
                        ),
                        child: _getSelectedLayout(appData),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 1,
                color: statusBarDividerColor,
              ),
              _buildBottomStatusBar(appData, context),
            ],
          ),
        ),
      ),
    );
  }
}
