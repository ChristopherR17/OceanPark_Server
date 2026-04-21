import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_level.dart';
import 'layout_utils.dart';
import 'widgets/editor_labeled_field.dart';
import 'widgets/selectable_color_swatch.dart';
import 'widgets/section_help_button.dart';

// Adaptation mode options shown in the selector.
const List<String> _adaptationLabels = ['Letterbox', 'Expand', 'Stretch'];
const List<String> _adaptationValues = ['letterbox', 'expand', 'stretch'];

// Reference screen aspect ratio used for the preview (16:9).
const double _referenceScreenAspect = 16.0 / 9.0;
const Color _defaultLevelBackgroundColor = Color(0xFFDCDCE1);
const int _defaultViewportWidth = 320;
const int _defaultViewportHeight = 180;
const int _defaultViewportX = 0;
const int _defaultViewportY = 0;

class LayoutViewport extends StatefulWidget {
  const LayoutViewport({super.key});

  @override
  LayoutViewportState createState() => LayoutViewportState();
}

class LayoutViewportState extends State<LayoutViewport> {
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _xController = TextEditingController();
  final TextEditingController _yController = TextEditingController();
  final GlobalKey _initialColorButtonKey = GlobalKey();
  final GlobalKey _previewColorButtonKey = GlobalKey();

  // Tracks which level the controllers are currently reflecting.
  int _syncedLevel = -2;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _xController.dispose();
    _yController.dispose();
    super.dispose();
  }

  void _syncControllers(GameLevel level) {
    _widthController.text = level.viewportWidth.toString();
    _heightController.text = level.viewportHeight.toString();
    _xController.text = level.viewportX.toString();
    _yController.text = level.viewportY.toString();
  }

  int _parseInt(String text, int fallback) {
    return int.tryParse(text.trim()) ?? fallback;
  }

  Color _parseHexColor(String hex, Color fallback) {
    final String cleaned = hex.trim().replaceFirst('#', '').toUpperCase();
    final RegExp sixHex = RegExp(r'^[0-9A-F]{6}$');
    if (!sixHex.hasMatch(cleaned)) {
      return fallback;
    }
    final int? rgb = int.tryParse(cleaned, radix: 16);
    if (rgb == null) {
      return fallback;
    }
    return Color(0xFF000000 | rgb);
  }

  Color _levelBackgroundColor(GameLevel level) {
    return _parseHexColor(
        level.backgroundColorHex, _defaultLevelBackgroundColor);
  }

  String _normalizeViewportColor(String color, String fallback) {
    if (GameLevel.viewportColorPalette.contains(color)) {
      return color;
    }
    return fallback;
  }

  void _applyChanges(AppData appData) {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    final int oldInitialX = level.viewportX;
    final int oldInitialY = level.viewportY;
    final int oldInitialWidth = level.viewportWidth;
    final int oldInitialHeight = level.viewportHeight;
    final int w = _parseInt(_widthController.text, level.viewportWidth);
    final int h = _parseInt(_heightController.text, level.viewportHeight);
    final int x = _parseInt(_xController.text, level.viewportX);
    final int y = _parseInt(_yController.text, level.viewportY);
    if (w == level.viewportWidth &&
        h == level.viewportHeight &&
        x == level.viewportX &&
        y == level.viewportY) {
      return;
    }
    appData.pushUndo();
    level.viewportWidth = w.clamp(1, 99999);
    level.viewportHeight = h.clamp(1, 99999);
    level.viewportX = x;
    level.viewportY = y;
    // Keep preview synced while it still matches the previous initial position.
    if (appData.viewportPreviewLevel != appData.selectedLevel ||
        (appData.viewportPreviewX == oldInitialX &&
            appData.viewportPreviewY == oldInitialY &&
            appData.viewportPreviewWidth == oldInitialWidth &&
            appData.viewportPreviewHeight == oldInitialHeight)) {
      appData.viewportPreviewX = level.viewportX;
      appData.viewportPreviewY = level.viewportY;
      appData.viewportPreviewWidth = level.viewportWidth;
      appData.viewportPreviewHeight = level.viewportHeight;
      appData.viewportPreviewLevel = appData.selectedLevel;
    }
    appData.update();
    appData.queueAutosave();
  }

  void _usePreviewValues(AppData appData) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    LayoutUtils.ensureViewportPreviewInitialized(appData);
    final level = appData.gameData.levels[appData.selectedLevel];
    if (level.viewportX == appData.viewportPreviewX &&
        level.viewportY == appData.viewportPreviewY &&
        level.viewportWidth == appData.viewportPreviewWidth &&
        level.viewportHeight == appData.viewportPreviewHeight) {
      return;
    }
    appData.pushUndo();
    level.viewportX = appData.viewportPreviewX;
    level.viewportY = appData.viewportPreviewY;
    level.viewportWidth = appData.viewportPreviewWidth;
    level.viewportHeight = appData.viewportPreviewHeight;
    appData.viewportPreviewLevel = appData.selectedLevel;
    _xController.text = level.viewportX.toString();
    _yController.text = level.viewportY.toString();
    _widthController.text = level.viewportWidth.toString();
    _heightController.text = level.viewportHeight.toString();
    appData.update();
    appData.queueAutosave();
  }

  void _resetToDefaults(AppData appData) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    final level = appData.gameData.levels[appData.selectedLevel];
    if (level.viewportWidth == _defaultViewportWidth &&
        level.viewportHeight == _defaultViewportHeight &&
        level.viewportX == _defaultViewportX &&
        level.viewportY == _defaultViewportY) {
      return;
    }
    appData.pushUndo();
    level.viewportWidth = _defaultViewportWidth;
    level.viewportHeight = _defaultViewportHeight;
    level.viewportX = _defaultViewportX;
    level.viewportY = _defaultViewportY;
    appData.viewportPreviewX = _defaultViewportX;
    appData.viewportPreviewY = _defaultViewportY;
    appData.viewportPreviewWidth = _defaultViewportWidth;
    appData.viewportPreviewHeight = _defaultViewportHeight;
    appData.viewportPreviewLevel = appData.selectedLevel;
    _widthController.text = level.viewportWidth.toString();
    _heightController.text = level.viewportHeight.toString();
    _xController.text = level.viewportX.toString();
    _yController.text = level.viewportY.toString();
    appData.update();
    appData.queueAutosave();
  }

  void _setAdaptation(AppData appData, String value) {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    if (level.viewportAdaptation == value) return;
    appData.pushUndo();
    level.viewportAdaptation = value;
    appData.update();
    appData.queueAutosave();
  }

  void _setOrientation(AppData appData, bool portrait) {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    final bool isPortrait = level.viewportHeight > level.viewportWidth;
    if (portrait == isPortrait) return;
    appData.pushUndo();
    final int tmp = level.viewportWidth;
    level.viewportWidth = level.viewportHeight;
    level.viewportHeight = tmp;
    _widthController.text = level.viewportWidth.toString();
    _heightController.text = level.viewportHeight.toString();
    appData.update();
    appData.queueAutosave();
  }

  void _setViewportInitialColor(AppData appData, String colorName) {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    final String normalized = _normalizeViewportColor(
      colorName,
      GameLevel.defaultViewportInitialColor,
    );
    if (level.viewportInitialColor == normalized) {
      return;
    }
    appData.pushUndo();
    level.viewportInitialColor = normalized;
    appData.update();
    appData.queueAutosave();
  }

  void _setViewportPreviewColor(AppData appData, String colorName) {
    if (appData.selectedLevel == -1) return;
    final level = appData.gameData.levels[appData.selectedLevel];
    final String normalized = _normalizeViewportColor(
      colorName,
      GameLevel.defaultViewportPreviewColor,
    );
    if (level.viewportPreviewColor == normalized) {
      return;
    }
    appData.pushUndo();
    level.viewportPreviewColor = normalized;
    appData.update();
    appData.queueAutosave();
  }

  void _showViewportColorPicker({
    required AppData appData,
    required GlobalKey anchorKey,
    required bool isPreviewColor,
  }) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    if (Overlay.maybeOf(context) == null || anchorKey.currentContext == null) {
      return;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final String selectedColorName = isPreviewColor
        ? _normalizeViewportColor(
            level.viewportPreviewColor,
            GameLevel.defaultViewportPreviewColor,
          )
        : _normalizeViewportColor(
            level.viewportInitialColor,
            GameLevel.defaultViewportInitialColor,
          );
    final CDKDialogController controller = CDKDialogController();
    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: anchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: _ViewportColorPickerPopover(
        title: isPreviewColor ? 'Preview color' : 'Initial color',
        selectedColorName: selectedColorName,
        onSelected: (String colorName) {
          if (isPreviewColor) {
            _setViewportPreviewColor(appData, colorName);
          } else {
            _setViewportInitialColor(appData, colorName);
          }
          controller.close();
        },
      ),
    );
  }

  Widget _buildColorButton({
    required GlobalKey anchorKey,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return CDKButton(
      key: anchorKey,
      style: CDKButtonStyle.normal,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            CupertinoIcons.chevron_down,
            size: 10,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appData = Provider.of<AppData>(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
    final TextStyle sectionTitleStyle = typography.title.copyWith(
      fontSize: (typography.title.fontSize ?? 17) + 2,
    );

    final int selectedLevel = appData.selectedLevel;
    final bool hasLevel =
        selectedLevel != -1 && selectedLevel < appData.gameData.levels.length;

    // Keep text controllers in sync when the selected level changes.
    if (hasLevel && selectedLevel != _syncedLevel) {
      _syncedLevel = selectedLevel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncControllers(appData.gameData.levels[selectedLevel]);
          LayoutUtils.ensureViewportPreviewInitialized(appData, force: true);
          setState(() {});
        }
      });
    } else if (!hasLevel && _syncedLevel != -1) {
      _syncedLevel = -1;
    }

    if (hasLevel) {
      LayoutUtils.ensureViewportPreviewInitialized(appData);
    }

    final GameLevel? level =
        hasLevel ? appData.gameData.levels[selectedLevel] : null;
    final int adaptationIndex = level == null
        ? 0
        : _adaptationValues.indexOf(level.viewportAdaptation).clamp(0, 2);
    final bool isPortrait =
        level != null && level.viewportHeight > level.viewportWidth;
    final int previewX = hasLevel ? appData.viewportPreviewX : 0;
    final int previewY = hasLevel ? appData.viewportPreviewY : 0;
    final int previewWidth = hasLevel ? appData.viewportPreviewWidth : 0;
    final int previewHeight = hasLevel ? appData.viewportPreviewHeight : 0;
    final Color levelBackgroundColor = level == null
        ? _defaultLevelBackgroundColor
        : _levelBackgroundColor(level);
    final String viewportInitialColorName = level == null
        ? GameLevel.defaultViewportInitialColor
        : _normalizeViewportColor(
            level.viewportInitialColor,
            GameLevel.defaultViewportInitialColor,
          );
    final String viewportPreviewColorName = level == null
        ? GameLevel.defaultViewportPreviewColor
        : _normalizeViewportColor(
            level.viewportPreviewColor,
            GameLevel.defaultViewportPreviewColor,
          );
    final Color viewportInitialColor =
        LayoutUtils.getColorFromName(viewportInitialColorName);
    final Color viewportPreviewColor =
        LayoutUtils.getColorFromName(viewportPreviewColorName);
    final bool canUsePreviewValues = level != null &&
        (level.viewportX != previewX ||
            level.viewportY != previewY ||
            level.viewportWidth != previewWidth ||
            level.viewportHeight != previewHeight);
    final bool canResetToDefaults = level != null &&
        (level.viewportWidth != _defaultViewportWidth ||
            level.viewportHeight != _defaultViewportHeight ||
            level.viewportX != _defaultViewportX ||
            level.viewportY != _defaultViewportY);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              CDKText(
                'Level Viewport',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'The Viewport defines the area of the level that the game camera shows. '
                    'Set its size (in pixels), initial position, and how it adapts when the '
                    'screen is a different resolution or orientation than expected. '
                    'On the canvas: the initial and preview rectangles use the colors selected from the color buttons. '
                    'Drag the preview rectangle to move it and drag its bottom-right triangle to resize it.',
              ),
            ],
          ),
        ),

        // ── Empty state ──────────────────────────────────────────────────────
        if (!hasLevel)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: CDKText(
                  'No level selected.\nSelect a Level to configure its Viewport.',
                  role: CDKTextRole.body,
                  color: cdkColors.colorText.withValues(alpha: 0.62),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: CupertinoScrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Orientation toggle ───────────────────────────────────
                    EditorLabeledField(
                      label: 'Orientation',
                      child: CDKButtonSelect(
                        selectedIndex: isPortrait ? 1 : 0,
                        options: const ['Landscape', 'Portrait'],
                        onSelected: (int index) {
                          _setOrientation(appData, index == 1);
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Preview ──────────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildColorButton(
                              anchorKey: _previewColorButtonKey,
                              color: viewportPreviewColor,
                              onPressed: () => _showViewportColorPicker(
                                appData: appData,
                                anchorKey: _previewColorButtonKey,
                                isPreviewColor: true,
                              ),
                            ),
                            const SizedBox(width: 6),
                            CDKText(
                              'Screen preview',
                              role: CDKTextRole.caption,
                              color: cdkColors.colorText,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          height: 165,
                          child: CustomPaint(
                            painter: _ViewportPreviewPainter(
                              appData: appData,
                              level: level!,
                              viewportW: previewWidth,
                              viewportH: previewHeight,
                              adaptation: level.viewportAdaptation,
                              previewX: previewX,
                              previewY: previewY,
                              frameTick: appData.frame,
                              cacheSize: appData.imagesCache.length,
                              sceneBackgroundColor: levelBackgroundColor,
                              backgroundColor: cdkColors.background,
                              previewFrameColor: viewportPreviewColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Viewport size ────────────────────────────────────────
                    CDKText(
                      'Viewport size (px)',
                      role: CDKTextRole.caption,
                      color: cdkColors.colorText.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: EditorLabeledField(
                            label: 'Width',
                            child: CDKFieldText(
                              placeholder: 'Width',
                              controller: _widthController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _applyChanges(appData),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: EditorLabeledField(
                            label: 'Height',
                            child: CDKFieldText(
                              placeholder: 'Height',
                              controller: _heightController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _applyChanges(appData),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Initial position ─────────────────────────────────────
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildColorButton(
                          anchorKey: _initialColorButtonKey,
                          color: viewportInitialColor,
                          onPressed: () => _showViewportColorPicker(
                            appData: appData,
                            anchorKey: _initialColorButtonKey,
                            isPreviewColor: false,
                          ),
                        ),
                        const SizedBox(width: 6),
                        CDKText(
                          'Initial position (px)',
                          role: CDKTextRole.caption,
                          color: cdkColors.colorText.withValues(alpha: 0.55),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: EditorLabeledField(
                            label: 'X',
                            child: CDKFieldText(
                              placeholder: 'X',
                              controller: _xController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _applyChanges(appData),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: EditorLabeledField(
                            label: 'Y',
                            child: CDKFieldText(
                              placeholder: 'Y',
                              controller: _yController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _applyChanges(appData),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    CDKText(
                      'Preview: X $previewX, Y $previewY, ${previewWidth}x$previewHeight',
                      role: CDKTextRole.caption,
                      color: cdkColors.colorText,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CDKButton(
                          onPressed: canUsePreviewValues
                              ? () => _usePreviewValues(appData)
                              : null,
                          child: const Text('Use preview values'),
                        ),
                        const SizedBox(width: 8),
                        CDKButton(
                          onPressed: canResetToDefaults
                              ? () => _resetToDefaults(appData)
                              : null,
                          child: const Text('Reset to defaults'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Screen adaptation mode ───────────────────────────────
                    EditorLabeledField(
                      label: 'Screen adaptation',
                      child: CDKButtonSelect(
                        selectedIndex: adaptationIndex,
                        options: _adaptationLabels,
                        onSelected: (int index) {
                          _setAdaptation(appData, _adaptationValues[index]);
                        },
                      ),
                    ),

                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ViewportColorPickerPopover extends StatelessWidget {
  const _ViewportColorPickerPopover({
    required this.title,
    required this.selectedColorName,
    required this.onSelected,
  });

  final String title;
  final String selectedColorName;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Padding(
        padding: EdgeInsets.all(spacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CDKText(
              title,
              role: CDKTextRole.caption,
            ),
            SizedBox(height: spacing.xs),
            Wrap(
              spacing: spacing.xs,
              runSpacing: spacing.xs,
              children: GameLevel.viewportColorPalette
                  .map(
                    (String colorName) => SelectableColorSwatch(
                      color: LayoutUtils.getColorFromName(colorName),
                      selected: colorName == selectedColorName,
                      onTap: () => onSelected(colorName),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preview painter ─────────────────────────────────────────────────────────

class _ViewportPreviewPainter extends CustomPainter {
  final AppData appData;
  final GameLevel level;
  final int viewportW;
  final int viewportH;
  final String adaptation;
  final int previewX;
  final int previewY;
  final int frameTick;
  final int cacheSize;
  final Color sceneBackgroundColor;
  final Color backgroundColor;
  final Color previewFrameColor;

  const _ViewportPreviewPainter({
    required this.appData,
    required this.level,
    required this.viewportW,
    required this.viewportH,
    required this.adaptation,
    required this.previewX,
    required this.previewY,
    required this.frameTick,
    required this.cacheSize,
    required this.sceneBackgroundColor,
    required this.backgroundColor,
    required this.previewFrameColor,
  });

  bool get _isDark => backgroundColor.computeLuminance() < 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final double safeViewportW = math.max(1, viewportW).toDouble();
    final double safeViewportH = math.max(1, viewportH).toDouble();
    final bool isPortrait = viewportH > viewportW;
    final String normalizedAdaptation = adaptation.trim().toLowerCase();
    final bool isLetterbox = normalizedAdaptation == 'letterbox' ||
        normalizedAdaptation == 'fit' ||
        normalizedAdaptation == 'contain';

    // Screen aspect ratio used in the preview
    final double screenAspect =
        isPortrait ? 1.0 / _referenceScreenAspect : _referenceScreenAspect;

    // Fit the "screen" rectangle into the available size with some margin
    const double margin = 6.0;
    final double availW = size.width - margin * 2;
    final double availH = size.height - margin * 2;

    late double screenW, screenH;
    if (availW / screenAspect <= availH) {
      screenW = availW;
      screenH = availW / screenAspect;
    } else {
      screenH = availH;
      screenW = availH * screenAspect;
    }

    final double screenL = (size.width - screenW) / 2;
    final double screenT = (size.height - screenH) / 2;
    final Rect screenRect = Rect.fromLTWH(screenL, screenT, screenW, screenH);
    final RRect clippedScreen =
        RRect.fromRectAndRadius(screenRect, const Radius.circular(4));
    final _PreviewSceneMapping mapping = _buildSceneMapping(
      screenRect: screenRect,
      viewportW: safeViewportW,
      viewportH: safeViewportH,
      adaptation: adaptation,
    );

    // Screen background. In letterbox mode, unused bands must match the
    // level background color shown in gameplay.
    final Color screenBackgroundColor = isLetterbox
        ? sceneBackgroundColor
        : (_isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8));
    canvas.drawRRect(
      clippedScreen,
      Paint()
        ..color = screenBackgroundColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      clippedScreen,
      Paint()
        ..color = _isDark ? const Color(0xFF555555) : const Color(0xFFBBBBBB)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    canvas.save();
    canvas.clipRRect(clippedScreen);
    canvas.drawRect(
      mapping.contentRect,
      Paint()..color = sceneBackgroundColor,
    );
    canvas.save();
    canvas.clipRect(mapping.contentRect);
    _paintScene(canvas, mapping);
    canvas.restore();
    canvas.drawRect(
      mapping.contentRect,
      Paint()
        ..color = previewFrameColor
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  _PreviewSceneMapping _buildSceneMapping({
    required Rect screenRect,
    required double viewportW,
    required double viewportH,
    required String adaptation,
  }) {
    final String normalizedAdaptation =
        _normalizeViewportAdaptation(adaptation);
    final double screenAspect = screenRect.width / screenRect.height;
    final double viewportAspect = viewportW / viewportH;
    Rect contentRect = screenRect;
    double cameraWorldW = viewportW;
    double cameraWorldH = viewportH;
    double cameraWorldLeft = previewX.toDouble();
    double cameraWorldTop = previewY.toDouble();

    switch (normalizedAdaptation) {
      case 'letterbox':
        if (viewportAspect > screenAspect) {
          final double h = screenRect.width / viewportAspect;
          contentRect = Rect.fromLTWH(
            screenRect.left,
            screenRect.top + (screenRect.height - h) / 2,
            screenRect.width,
            h,
          );
        } else {
          final double w = screenRect.height * viewportAspect;
          contentRect = Rect.fromLTWH(
            screenRect.left + (screenRect.width - w) / 2,
            screenRect.top,
            w,
            screenRect.height,
          );
        }
        break;
      case 'expand':
        if (screenAspect > viewportAspect) {
          cameraWorldW = viewportH * screenAspect;
          cameraWorldH = viewportH;
        } else {
          cameraWorldW = viewportW;
          cameraWorldH = viewportW / screenAspect;
        }
        cameraWorldLeft = previewX - (cameraWorldW - viewportW) / 2;
        cameraWorldTop = previewY - (cameraWorldH - viewportH) / 2;
        break;
      case 'stretch':
      default:
        break;
    }

    return _PreviewSceneMapping(
      contentRect: contentRect,
      cameraWorldW: cameraWorldW,
      cameraWorldH: cameraWorldH,
      cameraWorldLeft: cameraWorldLeft,
      cameraWorldTop: cameraWorldTop,
    );
  }

  String _normalizeViewportAdaptation(String value) {
    final String normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'fit':
      case 'contain':
      case 'letterbox':
        return 'letterbox';
      case 'expand':
        return 'expand';
      case 'stretch':
      case 'strech':
        return 'stretch';
      default:
        return 'letterbox';
    }
  }

  void _paintScene(Canvas canvas, _PreviewSceneMapping mapping) {
    final double cameraCenterX =
        mapping.cameraWorldLeft + mapping.cameraWorldW / 2;
    final double cameraCenterY =
        mapping.cameraWorldTop + mapping.cameraWorldH / 2;
    final double levelDepthSensitivity = level.depthSensitivity;
    final double scaleX = mapping.contentRect.width / mapping.cameraWorldW;
    final double scaleY = mapping.contentRect.height / mapping.cameraWorldH;
    final Paint drawPaint = Paint()..filterQuality = FilterQuality.none;

    for (int li = level.layers.length - 1; li >= 0; li--) {
      final layer = level.layers[li];
      if (!layer.visible) continue;
      if (!appData.imagesCache.containsKey(layer.tilesSheetFile)) continue;
      if (layer.tileMap.isEmpty || layer.tileMap.first.isEmpty) continue;

      final ui.Image tilesetImg = appData.imagesCache[layer.tilesSheetFile]!;
      final double tw = layer.tilesWidth.toDouble();
      final double th = layer.tilesHeight.toDouble();
      if (tw <= 0 || th <= 0) continue;
      final int tsetCols = (tilesetImg.width / tw).floor();
      if (tsetCols <= 0) continue;

      final int rows = layer.tileMap.length;
      final int cols = layer.tileMap.first.length;
      final double layerX = layer.x.toDouble();
      final double layerY = layer.y.toDouble();
      final double depthProjection = LayoutUtils.depthProjectionFactorForDepth(
        layer.depth,
        sensitivity: levelDepthSensitivity,
      );
      final double scaledTileW = tw * depthProjection;
      final double scaledTileH = th * depthProjection;
      if (scaledTileW <= 0 || scaledTileH <= 0) continue;
      final double layerXScaled = layerX * depthProjection;
      final double layerYScaled = layerY * depthProjection;
      final double cameraPx =
          cameraCenterX * depthProjection - mapping.cameraWorldW / 2;
      final double cameraPy =
          cameraCenterY * depthProjection - mapping.cameraWorldH / 2;
      final double visibleLeft = cameraPx;
      final double visibleTop = cameraPy;
      final double visibleRight = cameraPx + mapping.cameraWorldW;
      final double visibleBottom = cameraPy + mapping.cameraWorldH;

      int startCol = ((visibleLeft - layerXScaled) / scaledTileW).floor();
      int endCol = ((visibleRight - layerXScaled) / scaledTileW).ceil();
      int startRow = ((visibleTop - layerYScaled) / scaledTileH).floor();
      int endRow = ((visibleBottom - layerYScaled) / scaledTileH).ceil();
      startCol = math.max(0, math.min(cols - 1, startCol));
      endCol = math.max(0, math.min(cols - 1, endCol));
      startRow = math.max(0, math.min(rows - 1, startRow));
      endRow = math.max(0, math.min(rows - 1, endRow));
      if (startCol > endCol || startRow > endRow) continue;

      for (int row = startRow; row <= endRow; row++) {
        for (int col = startCol; col <= endCol; col++) {
          final int tileIndex = layer.tileMap[row][col];
          if (tileIndex < 0) continue;
          final int tileRow = (tileIndex / tsetCols).floor();
          final int tileCol = tileIndex % tsetCols;
          final double worldX = layerXScaled + col * scaledTileW;
          final double worldY = layerYScaled + row * scaledTileH;
          final Rect dstRect = Rect.fromLTWH(
            mapping.contentRect.left + (worldX - cameraPx) * scaleX,
            mapping.contentRect.top + (worldY - cameraPy) * scaleY,
            scaledTileW * scaleX,
            scaledTileH * scaleY,
          );
          canvas.drawImageRect(
            tilesetImg,
            Rect.fromLTWH(tileCol * tw, tileRow * th, tw, th),
            dstRect,
            drawPaint,
          );
        }
      }
    }

    for (int i = 0; i < level.sprites.length; i++) {
      final sprite = level.sprites[i];
      final String imageFile = LayoutUtils.spriteImageFile(appData, sprite);
      if (imageFile.isEmpty || !appData.imagesCache.containsKey(imageFile)) {
        continue;
      }
      final ui.Image spriteImage = appData.imagesCache[imageFile]!;
      final Size frameSize = LayoutUtils.spriteFrameSize(appData, sprite);
      final double spriteWidth = frameSize.width;
      final double spriteHeight = frameSize.height;
      if (spriteWidth <= 0 || spriteHeight <= 0) continue;

      final int frames = LayoutUtils.spriteTotalFramesFromImage(
        image: spriteImage,
        frameSize: frameSize,
      );
      final int frameIndex = LayoutUtils.spriteFrameIndex(
        appData: appData,
        sprite: sprite,
        totalFrames: frames,
      );
      final Rect srcRect = LayoutUtils.spriteSourceRectForFrame(
        image: spriteImage,
        frameSize: frameSize,
        frameIndex: frameIndex,
      );

      final double depthProjection = LayoutUtils.depthProjectionFactorForDepth(
        sprite.depth,
        sensitivity: levelDepthSensitivity,
      );
      final double cameraPx =
          cameraCenterX * depthProjection - mapping.cameraWorldW / 2;
      final double cameraPy =
          cameraCenterY * depthProjection - mapping.cameraWorldH / 2;
      final Rect spriteWorldRect = LayoutUtils.spriteWorldRect(
        appData,
        sprite,
        frameSize: frameSize,
        frameIndex: frameIndex,
        totalFrames: frames,
      );
      final double projectedSpriteLeft = spriteWorldRect.left * depthProjection;
      final double projectedSpriteTop = spriteWorldRect.top * depthProjection;
      final double projectedSpriteWidth = spriteWidth * depthProjection;
      final double projectedSpriteHeight = spriteHeight * depthProjection;
      final Rect dstRect = Rect.fromLTWH(
        mapping.contentRect.left + (projectedSpriteLeft - cameraPx) * scaleX,
        mapping.contentRect.top + (projectedSpriteTop - cameraPy) * scaleY,
        projectedSpriteWidth * scaleX,
        projectedSpriteHeight * scaleY,
      );

      if (sprite.flipX || sprite.flipY) {
        final double centerX = dstRect.center.dx;
        final double centerY = dstRect.center.dy;
        canvas.save();
        canvas.translate(centerX, centerY);
        canvas.scale(sprite.flipX ? -1.0 : 1.0, sprite.flipY ? -1.0 : 1.0);
        canvas.translate(-centerX, -centerY);
        canvas.drawImageRect(spriteImage, srcRect, dstRect, drawPaint);
        canvas.restore();
      } else {
        canvas.drawImageRect(spriteImage, srcRect, dstRect, drawPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ViewportPreviewPainter old) =>
      old.viewportW != viewportW ||
      old.viewportH != viewportH ||
      old.adaptation != adaptation ||
      old.previewX != previewX ||
      old.previewY != previewY ||
      old.frameTick != frameTick ||
      old.cacheSize != cacheSize ||
      old.sceneBackgroundColor != sceneBackgroundColor ||
      old.backgroundColor != backgroundColor ||
      old.previewFrameColor != previewFrameColor;
}

class _PreviewSceneMapping {
  final Rect contentRect;
  final double cameraWorldW;
  final double cameraWorldH;
  final double cameraWorldLeft;
  final double cameraWorldTop;

  const _PreviewSceneMapping({
    required this.contentRect,
    required this.cameraWorldW,
    required this.cameraWorldH,
    required this.cameraWorldLeft,
    required this.cameraWorldTop,
  });
}
