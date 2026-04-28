import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';

import 'app_data.dart';
import 'game_animation.dart';
import 'game_animation_hit_box.dart';
import 'game_list_group.dart';
import 'game_media_asset.dart';
import 'layout_utils.dart';
import 'widgets/grouped_list.dart';
import 'widgets/section_help_button.dart';
import 'widgets/selectable_color_swatch.dart';

class LayoutAnimationRigs extends StatefulWidget {
  const LayoutAnimationRigs({super.key});

  @override
  State<LayoutAnimationRigs> createState() => LayoutAnimationRigsState();
}

class LayoutAnimationRigsState extends State<LayoutAnimationRigs> {
  final ScrollController _scrollController = ScrollController();
  bool _updateFormQueued = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void updateForm(AppData appData) {
    if (!mounted || _updateFormQueued) {
      return;
    }
    _updateFormQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateFormQueued = false;
      setState(() {});
    });
  }

  String _selectedFramesValueLabel(List<int> selectedFrames) {
    if (selectedFrames.isEmpty) {
      return 'None';
    }
    final List<int> sorted = selectedFrames.toSet().toList(growable: false)
      ..sort();
    return sorted.join(',');
  }

  List<GameListGroup> _animationGroups(AppData appData) {
    if (appData.gameData.animationGroups.isEmpty) {
      return <GameListGroup>[GameListGroup.main()];
    }
    final bool hasMain = appData.gameData.animationGroups
        .any((group) => group.id == GameListGroup.mainId);
    if (hasMain) {
      return appData.gameData.animationGroups;
    }
    return <GameListGroup>[
      GameListGroup.main(),
      ...appData.gameData.animationGroups,
    ];
  }

  void _ensureMainAnimationGroup(AppData appData) {
    final List<GameListGroup> groups = appData.gameData.animationGroups;
    final int mainIndex =
        groups.indexWhere((group) => group.id == GameListGroup.mainId);
    if (mainIndex == -1) {
      groups.insert(0, GameListGroup.main());
      return;
    }
    final GameListGroup mainGroup = groups[mainIndex];
    final String normalizedName = mainGroup.name.trim().isEmpty
        ? GameListGroup.defaultMainName
        : mainGroup.name.trim();
    if (mainGroup.name != normalizedName) {
      mainGroup.name = normalizedName;
    }
  }

  Set<String> _animationGroupIds(AppData appData) {
    return _animationGroups(appData).map((group) => group.id).toSet();
  }

  String _effectiveAnimationGroupId(AppData appData, GameAnimation animation) {
    final String groupId = animation.groupId.trim();
    if (groupId.isNotEmpty && _animationGroupIds(appData).contains(groupId)) {
      return groupId;
    }
    return GameListGroup.mainId;
  }

  List<GroupedListRow<GameListGroup, GameAnimation>> _buildAnimationRows(
      AppData appData) {
    return GroupedListAlgorithms.buildRows<GameListGroup, GameAnimation>(
      groups: _animationGroups(appData),
      items: appData.gameData.animations,
      mainGroupId: GameListGroup.mainId,
      groupIdOf: (group) => group.id,
      groupCollapsedOf: (group) => group.collapsed,
      itemGroupIdOf: (animation) =>
          _effectiveAnimationGroupId(appData, animation),
    );
  }

  Future<void> _toggleGroupCollapsed(AppData appData, String groupId) async {
    await appData.runProjectMutation(
      debugLabel: 'animation-rig-group-toggle-collapse',
      mutate: () {
        _ensureMainAnimationGroup(appData);
        final List<GameListGroup> groups = appData.gameData.animationGroups;
        final int index = groups.indexWhere((group) => group.id == groupId);
        if (index == -1) {
          return;
        }
        groups[index].collapsed = !groups[index].collapsed;
      },
    );
  }

  void _moveGroup({
    required AppData appData,
    required List<GroupedListRow<GameListGroup, GameAnimation>>
        rowsWithoutMovedItem,
    required GroupedListRow<GameListGroup, GameAnimation> movedRow,
    required int targetRowIndex,
  }) {
    GroupedListAlgorithms.moveGroup<GameListGroup, GameAnimation>(
      groups: appData.gameData.animationGroups,
      rowsWithoutMovedItem: rowsWithoutMovedItem,
      movedRow: movedRow,
      targetRowIndex: targetRowIndex,
      groupIdOf: (group) => group.id,
    );
  }

  void _moveAnimation({
    required AppData appData,
    required List<GroupedListRow<GameListGroup, GameAnimation>>
        rowsWithoutMovedItem,
    required GroupedListRow<GameListGroup, GameAnimation> movedRow,
    required int targetRowIndex,
  }) {
    final List<GameAnimation> animations = appData.gameData.animations;
    appData.selectedAnimation = GroupedListAlgorithms
        .moveItemAndReturnSelectedIndex<GameListGroup, GameAnimation>(
      groups: appData.gameData.animationGroups,
      items: animations,
      rowsWithoutMovedItem: rowsWithoutMovedItem,
      movedRow: movedRow,
      targetRowIndex: targetRowIndex,
      mainGroupId: GameListGroup.mainId,
      groupIdOf: (group) => group.id,
      effectiveGroupIdOfItem: (animation) =>
          _effectiveAnimationGroupId(appData, animation),
      setItemGroupId: (animation, groupId) {
        animation.groupId = groupId;
      },
      selectedIndex: appData.selectedAnimation,
    );
  }

  void _onReorder(
    AppData appData,
    List<GroupedListRow<GameListGroup, GameAnimation>> rows,
    int oldIndex,
    int newIndex,
  ) {
    if (rows.isEmpty || oldIndex < 0 || oldIndex >= rows.length) {
      return;
    }

    final int targetIndex = GroupedListAlgorithms.normalizeTargetIndex(
      oldIndex: oldIndex,
      newIndex: newIndex,
      rowCount: rows.length,
    );
    final List<GroupedListRow<GameListGroup, GameAnimation>>
        rowsWithoutMovedItem =
        List<GroupedListRow<GameListGroup, GameAnimation>>.from(rows);
    final GroupedListRow<GameListGroup, GameAnimation> movedRow =
        rowsWithoutMovedItem.removeAt(oldIndex);
    int boundedTargetIndex = targetIndex;
    if (boundedTargetIndex > rowsWithoutMovedItem.length) {
      boundedTargetIndex = rowsWithoutMovedItem.length;
    }

    unawaited(
      appData.runProjectMutation(
        debugLabel: 'animation-rig-reorder',
        mutate: () {
          _ensureMainAnimationGroup(appData);
          if (movedRow.isGroup) {
            _moveGroup(
              appData: appData,
              rowsWithoutMovedItem: rowsWithoutMovedItem,
              movedRow: movedRow,
              targetRowIndex: boundedTargetIndex,
            );
          } else {
            _moveAnimation(
              appData: appData,
              rowsWithoutMovedItem: rowsWithoutMovedItem,
              movedRow: movedRow,
              targetRowIndex: boundedTargetIndex,
            );
          }
        },
      ),
    );
  }

  List<int> _selectedRigFrames(
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

  int _activeRigFrame(
    AppData appData,
    GameAnimation animation, {
    bool writeBack = false,
  }) {
    final List<int> selectedFrames = _selectedRigFrames(
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

  GameAnimationFrameRig _activeRig(
    AppData appData,
    GameAnimation animation, {
    bool writeBack = false,
  }) {
    final int frame = _activeRigFrame(
      appData,
      animation,
      writeBack: writeBack,
    );
    return animation.rigForFrame(frame);
  }

  _AnimationRigDraft _draftFromRig(GameAnimationFrameRig rig) {
    return _AnimationRigDraft(
      anchorX: rig.anchorX,
      anchorY: rig.anchorY,
      anchorColor: rig.anchorColor,
      hitBoxes: rig.hitBoxes
          .map(
            (item) => _HitBoxDraft(
              id: item.id,
              name: item.name,
              color: item.color,
              x: item.x,
              y: item.y,
              width: item.width,
              height: item.height,
            ),
          )
          .toList(growable: false),
    );
  }

  GameAnimationFrameRig _rigFromDraft({
    required int frame,
    required _AnimationRigDraft draft,
  }) {
    final List<GameAnimationHitBox> next = <GameAnimationHitBox>[];
    for (final _HitBoxDraft hitBox in draft.hitBoxes) {
      final double width = hitBox.width.clamp(0.01, 1.0);
      final double height = hitBox.height.clamp(0.01, 1.0);
      final double x = hitBox.x.clamp(0.0, 1.0 - width);
      final double y = hitBox.y.clamp(0.0, 1.0 - height);
      next.add(
        GameAnimationHitBox(
          id: hitBox.id.trim().isEmpty
              ? '__hb_${DateTime.now().microsecondsSinceEpoch}'
              : hitBox.id.trim(),
          name: hitBox.name.trim().isEmpty ? 'Hit Box' : hitBox.name.trim(),
          color: hitBox.color,
          x: x,
          y: y,
          width: width,
          height: height,
        ),
      );
    }
    return GameAnimationFrameRig(
      frame: frame,
      anchorX: draft.anchorX.clamp(0.0, 1.0),
      anchorY: draft.anchorY.clamp(0.0, 1.0),
      anchorColor: draft.anchorColor,
      hitBoxes: next,
    );
  }

  Future<_AutoHitBoxDraft?> _autoDetectHitBoxDraft(
    AppData appData,
    GameAnimation animation, {
    bool reportFailure = true,
  }) async {
    final GameMediaAsset? media =
        appData.mediaAssetByFileName(animation.mediaFile);
    if (media == null || media.tileWidth <= 0 || media.tileHeight <= 0) {
      if (reportFailure) {
        appData.projectStatusMessage =
            'Auto hit box failed: missing valid media tile size.';
        appData.update();
      }
      return null;
    }

    final ui.Image image = await appData.getImage(animation.mediaFile);
    final int frameWidth = media.tileWidth;
    final int frameHeight = media.tileHeight;
    final int cols = math.max(1, (image.width / frameWidth).floor());
    final int rows = math.max(1, (image.height / frameHeight).floor());
    final int totalFrames = math.max(1, cols * rows);
    final int activeFrame = _activeRigFrame(
      appData,
      animation,
      writeBack: true,
    );
    final int frameIndex = activeFrame.clamp(0, totalFrames - 1);
    final int srcCol = frameIndex % cols;
    final int srcRow = frameIndex ~/ cols;
    final int srcLeft = srcCol * frameWidth;
    final int srcTop = srcRow * frameHeight;
    final int srcRight = math.min(image.width, srcLeft + frameWidth);
    final int srcBottom = math.min(image.height, srcTop + frameHeight);
    if (srcRight <= srcLeft || srcBottom <= srcTop) {
      if (reportFailure) {
        appData.projectStatusMessage =
            'Auto hit box failed: frame area is outside sprite sheet.';
        appData.update();
      }
      return null;
    }

    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      if (reportFailure) {
        appData.projectStatusMessage =
            'Auto hit box failed: pixel data unavailable.';
        appData.update();
      }
      return null;
    }
    final Uint8List rgba = data.buffer.asUint8List();

    int minX = srcRight;
    int minY = srcBottom;
    int maxX = srcLeft - 1;
    int maxY = srcTop - 1;

    for (int y = srcTop; y < srcBottom; y++) {
      final int rowOffset = y * image.width * 4;
      for (int x = srcLeft; x < srcRight; x++) {
        final int alpha = rgba[rowOffset + x * 4 + 3];
        if (alpha == 0) {
          continue;
        }
        if (x < minX) {
          minX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      if (reportFailure) {
        appData.projectStatusMessage =
            'Auto hit box failed: selected frame is fully transparent.';
        appData.update();
      }
      return null;
    }

    final int localMinX = minX - srcLeft;
    final int localMinY = minY - srcTop;
    final int localMaxX = maxX - srcLeft;
    final int localMaxY = maxY - srcTop;

    double width = (localMaxX - localMinX + 1) / frameWidth;
    double height = (localMaxY - localMinY + 1) / frameHeight;
    width = width.clamp(0.01, 1.0).toDouble();
    height = height.clamp(0.01, 1.0).toDouble();
    double x = (localMinX / frameWidth).clamp(0.0, 1.0 - width).toDouble();
    double y = (localMinY / frameHeight).clamp(0.0, 1.0 - height).toDouble();

    return _AutoHitBoxDraft(
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  Future<void> _persistAnimationRig(
    AppData appData,
    GameAnimation animation,
    _AnimationRigDraft draft,
  ) async {
    final GameAnimationFrameRig activeRig = _activeRig(
      appData,
      animation,
      writeBack: true,
    );
    final String selectedId = (appData.selectedAnimationHitBox >= 0 &&
            appData.selectedAnimationHitBox < activeRig.hitBoxes.length)
        ? activeRig.hitBoxes[appData.selectedAnimationHitBox].id
        : '';
    final int activeFrame = _activeRigFrame(
      appData,
      animation,
      writeBack: true,
    );
    final List<int> targetFrames =
        _selectedRigFrames(appData, animation, writeBack: true);

    await appData.runProjectMutation(
      debugLabel: 'animation-rig-update',
      undoGroupKey: 'animation-rig-editor',
      mutate: () {
        final GameAnimationFrameRig nextRig = _rigFromDraft(
          frame: activeFrame,
          draft: draft,
        );
        animation.setRigForFrames(targetFrames, nextRig);
        final GameAnimationFrameRig nextActiveRig = animation.rigForFrame(
          activeFrame,
        );
        final int nextSelectedIndex =
            nextActiveRig.hitBoxes.indexWhere((item) => item.id == selectedId);
        appData.selectedAnimationHitBox = nextSelectedIndex;
      },
    );

    updateForm(appData);
  }

  Widget buildEditToolbarContent(AppData appData) {
    if (appData.selectedAnimation < 0 ||
        appData.selectedAnimation >= appData.gameData.animations.length) {
      return const SizedBox.shrink();
    }
    final GameAnimation animation =
        appData.gameData.animations[appData.selectedAnimation];
    final GameAnimationFrameRig activeRig = _activeRig(
      appData,
      animation,
      writeBack: true,
    );
    final List<int> selectedFrames = _selectedRigFrames(
      appData,
      animation,
      writeBack: true,
    );
    final String selectedFramesLabel =
        _selectedFramesValueLabel(selectedFrames);
    return _AnimationRigEditorPopover(
      key: ValueKey(
        'animation-rig-inline-${animation.id}-${appData.selectedAnimation}',
      ),
      initialDraft: _draftFromRig(activeRig),
      initialSelectedHitBoxIndex: appData.selectedAnimationHitBox,
      hitBoxColorPalette: GameAnimationHitBox.colorPalette,
      anchorColorPalette: GameAnimation.anchorColorPalette,
      selectedFramesLabel: selectedFramesLabel,
      panelWidth: 344,
      onAutoBoundsDetect: () => _autoDetectHitBoxDraft(
        appData,
        animation,
        reportFailure: false,
      ),
      onSelectedHitBoxChanged: (int index) {
        if (appData.selectedAnimationHitBox == index) {
          return;
        }
        appData.selectedAnimationHitBox = index;
        appData.update();
        updateForm(appData);
      },
      onDraftChanged: (nextDraft) async {
        await _persistAnimationRig(appData, animation, nextDraft);
      },
    );
  }

  void _syncSelectedAnimationHitBox(AppData appData) {
    if (appData.selectedAnimation < 0 ||
        appData.selectedAnimation >= appData.gameData.animations.length) {
      if (appData.selectedAnimationHitBox != -1) {
        appData.selectedAnimationHitBox = -1;
      }
      return;
    }
    final GameAnimation animation =
        appData.gameData.animations[appData.selectedAnimation];
    final GameAnimationFrameRig activeRig = _activeRig(
      appData,
      animation,
      writeBack: true,
    );
    if (appData.selectedAnimationHitBox < 0 ||
        appData.selectedAnimationHitBox >= activeRig.hitBoxes.length) {
      appData.selectedAnimationHitBox = -1;
    }
  }

  void _selectAnimation(
    AppData appData,
    int index,
    bool isSelected,
  ) {
    if (isSelected) {
      appData.selectedAnimation = -1;
      appData.selectedAnimationHitBox = -1;
      appData.animationRigSelectionAnimationId = '';
      appData.animationRigSelectedFrames = <int>[];
      appData.animationRigSelectionStartFrame = -1;
      appData.animationRigSelectionEndFrame = -1;
      appData.animationRigActiveFrame = -1;
      appData.update();
      return;
    }
    final List<GameAnimation> animations = appData.gameData.animations;
    if (index < 0 || index >= animations.length) {
      return;
    }
    final GameAnimation animation = animations[index];
    appData.selectedAnimation = index;
    appData.selectedAnimationHitBox = -1;
    LayoutUtils.setAnimationRigSelectedFrames(
      appData: appData,
      animation: animation,
      frames: const <int>[],
      totalFrames: (animation.endFrame < 0 ? 0 : animation.endFrame) + 1,
      setActiveToFirst: true,
    );
    appData.update();
  }

  @override
  Widget build(BuildContext context) {
    final AppData appData = Provider.of<AppData>(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
    final TextStyle sectionTitleStyle = typography.title.copyWith(
      fontSize: (typography.title.fontSize ?? 17) + 2,
    );
    final TextStyle listItemTitleStyle = typography.body.copyWith(
      fontSize: (typography.body.fontSize ?? 14) + 2,
      fontWeight: FontWeight.w700,
    );

    if (appData.selectedProject == null) {
      return const Center(
        child: CDKText(
          'Select a project to edit animation rigs.',
          role: CDKTextRole.body,
          secondary: true,
        ),
      );
    }

    final List<GameAnimation> animations = appData.gameData.animations;
    if (appData.selectedAnimation >= animations.length) {
      appData.selectedAnimation =
          animations.isEmpty ? -1 : animations.length - 1;
    }
    _syncSelectedAnimationHitBox(appData);

    final GameAnimation? selectedAnimation = appData.selectedAnimation >= 0 &&
            appData.selectedAnimation < animations.length
        ? animations[appData.selectedAnimation]
        : null;
    final List<GroupedListRow<GameListGroup, GameAnimation>> rows =
        _buildAnimationRows(appData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Row(
            children: [
              CDKText(
                'Animation Rigs',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'Animation Rigs define anchor point and hit box geometry for each animation.',
              ),
            ],
          ),
        ),
        _AnimationRigPreviewPanel(
          appData: appData,
          animation: selectedAnimation,
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: CDKText(
              '(No animations defined)',
              role: CDKTextRole.caption,
              secondary: true,
            ),
          ),
        Expanded(
          child: CupertinoScrollbar(
            controller: _scrollController,
            child: Localizations.override(
              context: context,
              delegates: const [
                DefaultMaterialLocalizations.delegate,
                DefaultWidgetsLocalizations.delegate,
              ],
              child: ReorderableListView.builder(
                scrollController: _scrollController,
                buildDefaultDragHandles: false,
                itemCount: rows.length,
                onReorder: (oldIndex, newIndex) =>
                    _onReorder(appData, rows, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final GroupedListRow<GameListGroup, GameAnimation> row =
                      rows[index];
                  if (row.isGroup) {
                    final GameListGroup group = row.group!;
                    return Container(
                      key: ValueKey('animation-rig-group-${group.id}'),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      color: cdkColors.backgroundSecondary1,
                      child: Row(
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            minimumSize: const Size(20, 20),
                            onPressed: () async {
                              await _toggleGroupCollapsed(appData, group.id);
                            },
                            child: AnimatedRotation(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOutCubic,
                              turns: group.collapsed ? 0.0 : 0.25,
                              child: Icon(
                                CupertinoIcons.chevron_right,
                                size: 14,
                                color: cdkColors.colorText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CDKText(
                              group.name,
                              role: CDKTextRole.body,
                              style: listItemTitleStyle,
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                CupertinoIcons.bars,
                                size: 16,
                                color: cdkColors.colorText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final GameAnimation animation = row.item!;
                  final int animationIndex = row.itemIndex!;
                  final bool isSelected =
                      animationIndex == appData.selectedAnimation;
                  final String mediaName =
                      appData.mediaDisplayNameByFileName(animation.mediaFile);
                  final String subtitle =
                      '$mediaName | Frames ${animation.startFrame}-${animation.endFrame}';
                  final bool hiddenByCollapse = row.hiddenByCollapse;
                  return AnimatedSize(
                    key: ValueKey('${animation.id}-$index'),
                    duration: const Duration(milliseconds: 300),
                    reverseDuration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: ClipRect(
                      child: Align(
                        heightFactor: hiddenByCollapse ? 0.0 : 1.0,
                        alignment: Alignment.topCenter,
                        child: IgnorePointer(
                          ignoring: hiddenByCollapse,
                          child: GestureDetector(
                            onTap: () => _selectAnimation(
                              appData,
                              animationIndex,
                              isSelected,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 8,
                              ),
                              color: isSelected
                                  ? CupertinoColors.systemBlue
                                      .withValues(alpha: 0.08)
                                  : cdkColors.backgroundSecondary0,
                              child: Row(
                                children: [
                                  const SizedBox(width: 22),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CDKText(
                                          animation.name,
                                          role: isSelected
                                              ? CDKTextRole.bodyStrong
                                              : CDKTextRole.body,
                                          style: listItemTitleStyle,
                                        ),
                                        const SizedBox(height: 2),
                                        CDKText(
                                          subtitle,
                                          role: CDKTextRole.body,
                                          color: cdkColors.colorText,
                                        ),
                                      ],
                                    ),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Icon(
                                        CupertinoIcons.bars,
                                        size: 16,
                                        color: cdkColors.colorText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimationRigPreviewPanel extends StatefulWidget {
  const _AnimationRigPreviewPanel({
    required this.appData,
    required this.animation,
  });

  final AppData appData;
  final GameAnimation? animation;

  @override
  State<_AnimationRigPreviewPanel> createState() =>
      _AnimationRigPreviewPanelState();
}

class _AnimationRigPreviewPanelState extends State<_AnimationRigPreviewPanel> {
  Timer? _previewTimer;
  DateTime? _previewLastTick;
  String _previewAnimationId = '';
  double _previewElapsedSeconds = 0.0;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    _syncPreviewSelection(widget.animation);
  }

  @override
  void didUpdateWidget(covariant _AnimationRigPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation?.id != widget.animation?.id) {
      _syncPreviewSelection(widget.animation);
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewTimer = null;
    super.dispose();
  }

  void _setPreviewPlaying(bool nextPlaying) {
    if (_previewPlaying == nextPlaying) {
      return;
    }
    _previewPlaying = nextPlaying;
    if (!_previewPlaying) {
      _previewLastTick = null;
      _previewTimer?.cancel();
      _previewTimer = null;
      return;
    }
    _previewLastTick = DateTime.now();
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_previewPlaying) {
        return;
      }
      final DateTime now = DateTime.now();
      final DateTime previous = _previewLastTick ?? now;
      _previewLastTick = now;
      final double deltaSeconds =
          now.difference(previous).inMicroseconds / 1000000.0;
      if (deltaSeconds <= 0) {
        return;
      }
      setState(() {
        _previewElapsedSeconds += deltaSeconds;
      });
    });
  }

  void _restartPreview() {
    setState(() {
      _previewElapsedSeconds = 0.0;
    });
  }

  void _syncPreviewSelection(GameAnimation? animation) {
    final String nextId = animation?.id ?? '';
    if (nextId == _previewAnimationId) {
      return;
    }
    _previewAnimationId = nextId;
    _previewElapsedSeconds = 0.0;
    _previewLastTick = null;
    if (animation == null) {
      _setPreviewPlaying(false);
      return;
    }
    _setPreviewPlaying(true);
  }

  int _previewFrameIndex({
    required GameAnimation animation,
    required int totalFrames,
  }) {
    final int safeTotalFrames = math.max(1, totalFrames);
    final int start = animation.startFrame.clamp(0, safeTotalFrames - 1);
    final int end = animation.endFrame.clamp(start, safeTotalFrames - 1);
    final int span = math.max(1, end - start + 1);
    final int ticks = (_previewElapsedSeconds * animation.fps).floor();
    final int offset =
        animation.loop ? ticks % span : math.min(ticks, span - 1);
    return start + offset;
  }

  Widget _buildPreviewPanel(
    BuildContext context,
    AppData appData,
    GameAnimation? animation,
  ) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final bool hasAnimation = animation != null;
    const double previewCanvasHeight = 128;
    final Color checkerA = cdkColors.backgroundSecondary1;
    final Color checkerB = Color.alphaBlend(
      cdkColors.colorText.withValues(alpha: 0.06),
      cdkColors.backgroundSecondary1,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cdkColors.backgroundSecondary0,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cdkColors.colorTextSecondary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasAnimation)
            SizedBox(
              height: previewCanvasHeight,
              child: Center(
                child: CDKText(
                  'Select an animation to preview.',
                  role: CDKTextRole.caption,
                  color: cdkColors.colorTextSecondary,
                ),
              ),
            )
          else
            FutureBuilder<ui.Image>(
              future: appData.getImage(animation.mediaFile),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null) {
                  return const SizedBox(
                    height: previewCanvasHeight,
                    child: Center(
                      child: CupertinoActivityIndicator(),
                    ),
                  );
                }
                final ui.Image? image = snapshot.data;
                final GameMediaAsset? media =
                    appData.mediaAssetByFileName(animation.mediaFile);
                if (image == null ||
                    media == null ||
                    media.tileWidth <= 0 ||
                    media.tileHeight <= 0) {
                  return SizedBox(
                    height: previewCanvasHeight,
                    child: Center(
                      child: CDKText(
                        'Preview unavailable',
                        role: CDKTextRole.caption,
                        color: cdkColors.colorTextSecondary,
                      ),
                    ),
                  );
                }
                final int cols =
                    math.max(1, (image.width / media.tileWidth).floor());
                final int rows =
                    math.max(1, (image.height / media.tileHeight).floor());
                final int totalFrames = math.max(1, cols * rows);
                final int frameIndex = _previewFrameIndex(
                  animation: animation,
                  totalFrames: totalFrames,
                );
                final GameAnimationFrameRig rig = animation.rigForFrame(
                  frameIndex,
                );
                final double frameWidth = media.tileWidth.toDouble();
                final double frameHeight = media.tileHeight.toDouble();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: previewCanvasHeight,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: media.tileWidth / media.tileHeight,
                          child: CustomPaint(
                            painter: _AnimationRigFramePreviewPainter(
                              image: image,
                              frameWidth: frameWidth,
                              frameHeight: frameHeight,
                              columns: cols,
                              frameIndex: frameIndex,
                              anchorX: rig.anchorX,
                              anchorY: rig.anchorY,
                              anchorColor:
                                  LayoutUtils.getColorFromName(rig.anchorColor),
                              checkerA: checkerA,
                              checkerB: checkerB,
                              borderColor: cdkColors.colorTextSecondary
                                  .withValues(alpha: 0.45),
                              guideColor:
                                  cdkColors.colorTextSecondary.withValues(
                                alpha: 0.42,
                              ),
                              anchorOutlineColor: cdkColors.colorText,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Align(
                      alignment: Alignment.center,
                      child: CDKText(
                        'Frame $frameIndex (${animation.startFrame}-${animation.endFrame}) @ ${animation.fps.toStringAsFixed(1)} fps',
                        role: CDKTextRole.caption,
                        color: cdkColors.colorText,
                      ),
                    ),
                  ],
                );
              },
            ),
          if (!hasAnimation) ...[
            SizedBox(height: spacing.xs),
            CDKText(
              'Frame -',
              role: CDKTextRole.caption,
              color: cdkColors.colorText,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final bool hasAnimation = widget.animation != null;
    final bool isPreviewPlaying = hasAnimation && _previewPlaying;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CDKButton(
                style: CDKButtonStyle.normal,
                onPressed: hasAnimation
                    ? () {
                        setState(() {
                          _setPreviewPlaying(!_previewPlaying);
                        });
                      }
                    : null,
                child: Icon(
                  isPreviewPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: 12,
                ),
              ),
              SizedBox(width: spacing.xs),
              CDKButton(
                style: CDKButtonStyle.normal,
                onPressed: hasAnimation ? _restartPreview : null,
                child: const Icon(
                  CupertinoIcons.refresh,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
        _buildPreviewPanel(context, widget.appData, widget.animation),
      ],
    );
  }
}

class _AnimationRigDraft {
  const _AnimationRigDraft({
    required this.anchorX,
    required this.anchorY,
    required this.anchorColor,
    required this.hitBoxes,
  });

  final double anchorX;
  final double anchorY;
  final String anchorColor;
  final List<_HitBoxDraft> hitBoxes;

  _AnimationRigDraft copyWith({
    double? anchorX,
    double? anchorY,
    String? anchorColor,
    List<_HitBoxDraft>? hitBoxes,
  }) {
    return _AnimationRigDraft(
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      anchorColor: anchorColor ?? this.anchorColor,
      hitBoxes: hitBoxes ?? this.hitBoxes,
    );
  }
}

class _HitBoxDraft {
  const _HitBoxDraft({
    required this.id,
    required this.name,
    required this.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String id;
  final String name;
  final String color;
  final double x;
  final double y;
  final double width;
  final double height;

  _HitBoxDraft copyWith({
    String? id,
    String? name,
    String? color,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return _HitBoxDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

class _AutoHitBoxDraft {
  const _AutoHitBoxDraft({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class _AnimationRigEditorPopover extends StatefulWidget {
  const _AnimationRigEditorPopover({
    super.key,
    required this.initialDraft,
    required this.initialSelectedHitBoxIndex,
    required this.hitBoxColorPalette,
    required this.anchorColorPalette,
    required this.selectedFramesLabel,
    required this.onAutoBoundsDetect,
    required this.onSelectedHitBoxChanged,
    required this.onDraftChanged,
    this.panelWidth = 560,
  });

  final _AnimationRigDraft initialDraft;
  final int initialSelectedHitBoxIndex;
  final List<String> hitBoxColorPalette;
  final List<String> anchorColorPalette;
  final String selectedFramesLabel;
  final Future<_AutoHitBoxDraft?> Function() onAutoBoundsDetect;
  final ValueChanged<int> onSelectedHitBoxChanged;
  final Future<void> Function(_AnimationRigDraft draft) onDraftChanged;
  final double panelWidth;

  @override
  State<_AnimationRigEditorPopover> createState() =>
      _AnimationRigEditorPopoverState();
}

class _AnimationRigEditorPopoverState
    extends State<_AnimationRigEditorPopover> {
  static const double _editorEpsilon = 0.0005;
  late final List<_HitBoxDraft> _drafts = widget.initialDraft.hitBoxes
      .map((item) => item.copyWith())
      .toList(growable: true);
  late double _anchorX = widget.initialDraft.anchorX.clamp(0.0, 1.0);
  late double _anchorY = widget.initialDraft.anchorY.clamp(0.0, 1.0);
  late String _anchorColor =
      widget.anchorColorPalette.contains(widget.initialDraft.anchorColor)
          ? widget.initialDraft.anchorColor
          : widget.anchorColorPalette.first;

  final TextEditingController _anchorXController = TextEditingController();
  final TextEditingController _anchorYController = TextEditingController();
  final GlobalKey _anchorColorAnchorKey = GlobalKey();

  // Per-row controllers for hit boxes.
  late final List<TextEditingController> _nameControllers = _drafts
      .map((d) => TextEditingController(text: d.name))
      .toList(growable: true);
  late final List<TextEditingController> _xControllers = _drafts
      .map((d) => TextEditingController(text: _formatUnit(d.x)))
      .toList(growable: true);
  late final List<TextEditingController> _yControllers = _drafts
      .map((d) => TextEditingController(text: _formatUnit(d.y)))
      .toList(growable: true);
  late final List<TextEditingController> _widthControllers = _drafts
      .map((d) => TextEditingController(text: _formatUnit(d.width)))
      .toList(growable: true);
  late final List<TextEditingController> _heightControllers = _drafts
      .map((d) => TextEditingController(text: _formatUnit(d.height)))
      .toList(growable: true);
  late final List<GlobalKey> _hitBoxColorAnchorKeys =
      List.generate(_drafts.length, (_) => GlobalKey(), growable: true);

  bool _isApplyingControllers = false;
  int _selectedIndex = -1;
  int _newKeyCounter = 0;
  bool _isAutoDetecting = false;

  @override
  void initState() {
    super.initState();
    _refreshAnchorControllers();
    final int initialIndex = widget.initialSelectedHitBoxIndex >= 0 &&
            widget.initialSelectedHitBoxIndex < _drafts.length
        ? widget.initialSelectedHitBoxIndex
        : -1;
    _setSelectedIndex(initialIndex, notifyParent: false);
  }

  @override
  void dispose() {
    _anchorXController.dispose();
    _anchorYController.dispose();
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _xControllers) {
      c.dispose();
    }
    for (final c in _yControllers) {
      c.dispose();
    }
    for (final c in _widthControllers) {
      c.dispose();
    }
    for (final c in _heightControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AnimationRigEditorPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromIncomingDraftIfNeeded();
  }

  String _formatUnit(double value) => value.toStringAsFixed(2);

  int _normalizedSelectedIndex(int index, int length) {
    return (index >= 0 && index < length) ? index : -1;
  }

  bool _nearEqual(double a, double b) {
    return (a - b).abs() <= _editorEpsilon;
  }

  bool _sameHitBoxDraft(_HitBoxDraft a, _HitBoxDraft b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.color == b.color &&
        _nearEqual(a.x, b.x) &&
        _nearEqual(a.y, b.y) &&
        _nearEqual(a.width, b.width) &&
        _nearEqual(a.height, b.height);
  }

  bool _sameRigDraft(_AnimationRigDraft a, _AnimationRigDraft b) {
    if (!_nearEqual(a.anchorX, b.anchorX) ||
        !_nearEqual(a.anchorY, b.anchorY) ||
        a.anchorColor != b.anchorColor ||
        a.hitBoxes.length != b.hitBoxes.length) {
      return false;
    }
    for (int i = 0; i < a.hitBoxes.length; i++) {
      if (!_sameHitBoxDraft(a.hitBoxes[i], b.hitBoxes[i])) {
        return false;
      }
    }
    return true;
  }

  String _normalizedAnchorColor(String colorName) {
    if (widget.anchorColorPalette.contains(colorName)) {
      return colorName;
    }
    if (widget.anchorColorPalette.isNotEmpty) {
      return widget.anchorColorPalette.first;
    }
    return colorName;
  }

  String _normalizedHitBoxColor(String colorName) {
    if (widget.hitBoxColorPalette.contains(colorName)) {
      return colorName;
    }
    if (widget.hitBoxColorPalette.isNotEmpty) {
      return widget.hitBoxColorPalette.first;
    }
    return colorName;
  }

  _AnimationRigDraft _normalizedIncomingDraft(_AnimationRigDraft draft) {
    final List<_HitBoxDraft> nextHitBoxes = draft.hitBoxes.map((item) {
      final double width = item.width.clamp(0.01, 1.0);
      final double height = item.height.clamp(0.01, 1.0);
      final double x = item.x.clamp(0.0, 1.0 - width);
      final double y = item.y.clamp(0.0, 1.0 - height);
      return item.copyWith(
        color: _normalizedHitBoxColor(item.color),
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }).toList(growable: false);
    return _AnimationRigDraft(
      anchorX: draft.anchorX.clamp(0.0, 1.0),
      anchorY: draft.anchorY.clamp(0.0, 1.0),
      anchorColor: _normalizedAnchorColor(draft.anchorColor),
      hitBoxes: nextHitBoxes,
    );
  }

  void _syncDraftRowsFromIncoming(List<_HitBoxDraft> incomingDrafts) {
    while (_drafts.length > incomingDrafts.length) {
      final int last = _drafts.length - 1;
      _drafts.removeLast();
      _nameControllers[last].dispose();
      _nameControllers.removeLast();
      _xControllers[last].dispose();
      _xControllers.removeLast();
      _yControllers[last].dispose();
      _yControllers.removeLast();
      _widthControllers[last].dispose();
      _widthControllers.removeLast();
      _heightControllers[last].dispose();
      _heightControllers.removeLast();
      _hitBoxColorAnchorKeys.removeLast();
    }

    for (int i = 0; i < incomingDrafts.length; i++) {
      final _HitBoxDraft incoming = incomingDrafts[i];
      if (i >= _drafts.length) {
        _drafts.add(incoming.copyWith());
        _nameControllers.add(TextEditingController(text: incoming.name));
        _xControllers.add(TextEditingController(text: _formatUnit(incoming.x)));
        _yControllers.add(TextEditingController(text: _formatUnit(incoming.y)));
        _widthControllers
            .add(TextEditingController(text: _formatUnit(incoming.width)));
        _heightControllers
            .add(TextEditingController(text: _formatUnit(incoming.height)));
        _hitBoxColorAnchorKeys.add(GlobalKey());
        continue;
      }

      _drafts[i] = incoming.copyWith();
      _setControllerText(_nameControllers[i], incoming.name);
      _setControllerText(_xControllers[i], _formatUnit(incoming.x));
      _setControllerText(_yControllers[i], _formatUnit(incoming.y));
      _setControllerText(_widthControllers[i], _formatUnit(incoming.width));
      _setControllerText(_heightControllers[i], _formatUnit(incoming.height));
    }
  }

  void _syncFromIncomingDraftIfNeeded() {
    final _AnimationRigDraft incoming =
        _normalizedIncomingDraft(widget.initialDraft);
    final int incomingSelectedIndex = _normalizedSelectedIndex(
      widget.initialSelectedHitBoxIndex,
      incoming.hitBoxes.length,
    );
    if (_sameRigDraft(_snapshot(), incoming) &&
        _selectedIndex == incomingSelectedIndex) {
      return;
    }
    setState(() {
      _anchorX = incoming.anchorX;
      _anchorY = incoming.anchorY;
      _anchorColor = incoming.anchorColor;
      _refreshAnchorControllers();
      _syncDraftRowsFromIncoming(incoming.hitBoxes);
      _selectedIndex = incomingSelectedIndex;
    });
  }

  double? _parseUnit(String raw) {
    final String normalized = raw.replaceAll(',', '.').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  _AnimationRigDraft _snapshot() {
    return _AnimationRigDraft(
      anchorX: _anchorX,
      anchorY: _anchorY,
      anchorColor: _anchorColor,
      hitBoxes: _drafts.map((item) => item.copyWith()).toList(growable: false),
    );
  }

  void _emitChanged() {
    unawaited(widget.onDraftChanged(_snapshot()));
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _refreshAnchorControllers() {
    _isApplyingControllers = true;
    _setControllerText(_anchorXController, _formatUnit(_anchorX));
    _setControllerText(_anchorYController, _formatUnit(_anchorY));
    _isApplyingControllers = false;
  }

  void _setSelectedIndex(int index, {required bool notifyParent}) {
    final int clampedIndex =
        (index >= 0 && index < _drafts.length) ? index : -1;
    if (_selectedIndex == clampedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = clampedIndex;
    });
    if (notifyParent) {
      widget.onSelectedHitBoxChanged(clampedIndex);
    }
  }

  void _updateAnchorX(String value) {
    if (_isApplyingControllers) {
      return;
    }
    final double? parsed = _parseUnit(value);
    if (parsed == null) {
      return;
    }
    final double next = parsed.clamp(0.0, 1.0);
    if ((_anchorX - next).abs() < 0.0005) {
      return;
    }
    setState(() {
      _anchorX = next;
    });
    _emitChanged();
  }

  void _updateAnchorY(String value) {
    if (_isApplyingControllers) {
      return;
    }
    final double? parsed = _parseUnit(value);
    if (parsed == null) {
      return;
    }
    final double next = parsed.clamp(0.0, 1.0);
    if ((_anchorY - next).abs() < 0.0005) {
      return;
    }
    setState(() {
      _anchorY = next;
    });
    _emitChanged();
  }

  void _updateHitBox(
    int index, {
    String? name,
    String? color,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    final _HitBoxDraft current = _drafts[index];
    final double nextWidth = (width ?? current.width).clamp(0.01, 1.0);
    final double nextHeight = (height ?? current.height).clamp(0.01, 1.0);
    final double nextX = (x ?? current.x).clamp(0.0, 1.0 - nextWidth);
    final double nextY = (y ?? current.y).clamp(0.0, 1.0 - nextHeight);
    final _HitBoxDraft next = current.copyWith(
      name: name ?? current.name,
      color: color ?? current.color,
      x: nextX,
      y: nextY,
      width: nextWidth,
      height: nextHeight,
    );
    if (next.name == current.name &&
        next.color == current.color &&
        (next.x - current.x).abs() < 0.0005 &&
        (next.y - current.y).abs() < 0.0005 &&
        (next.width - current.width).abs() < 0.0005 &&
        (next.height - current.height).abs() < 0.0005) {
      return;
    }
    setState(() {
      _drafts[index] = next;
    });
    _emitChanged();
  }

  void _deleteHitBox(int index) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    setState(() {
      _drafts.removeAt(index);
      _nameControllers[index].dispose();
      _nameControllers.removeAt(index);
      _xControllers[index].dispose();
      _xControllers.removeAt(index);
      _yControllers[index].dispose();
      _yControllers.removeAt(index);
      _widthControllers[index].dispose();
      _widthControllers.removeAt(index);
      _heightControllers[index].dispose();
      _heightControllers.removeAt(index);
      _hitBoxColorAnchorKeys.removeAt(index);
    });
    final int nextIndex =
        _drafts.isEmpty ? -1 : (_selectedIndex.clamp(0, _drafts.length - 1));
    _setSelectedIndex(nextIndex, notifyParent: true);
    _emitChanged();
  }

  static const _AutoHitBoxDraft _defaultAutoHitBoxDraft = _AutoHitBoxDraft(
    x: 0.25,
    y: 0.25,
    width: 0.5,
    height: 0.5,
  );

  Future<void> _addHitBox() async {
    if (_isAutoDetecting) {
      return;
    }
    setState(() {
      _isAutoDetecting = true;
    });
    final _AutoHitBoxDraft autoDraft =
        (await widget.onAutoBoundsDetect()) ?? _defaultAutoHitBoxDraft;
    if (!mounted) {
      return;
    }
    setState(() {
      _isAutoDetecting = false;
    });

    final _HitBoxDraft next = _HitBoxDraft(
      id: '__hb_${DateTime.now().microsecondsSinceEpoch}_${_newKeyCounter++}',
      name: 'Hit Box ${_drafts.length + 1}',
      color: GameAnimationHitBox.defaultColor,
      x: autoDraft.x,
      y: autoDraft.y,
      width: autoDraft.width,
      height: autoDraft.height,
    );
    setState(() {
      _drafts.add(next);
      _nameControllers.add(TextEditingController(text: next.name));
      _xControllers.add(TextEditingController(text: _formatUnit(next.x)));
      _yControllers.add(TextEditingController(text: _formatUnit(next.y)));
      _widthControllers
          .add(TextEditingController(text: _formatUnit(next.width)));
      _heightControllers
          .add(TextEditingController(text: _formatUnit(next.height)));
      _hitBoxColorAnchorKeys.add(GlobalKey());
    });
    _setSelectedIndex(_drafts.length - 1, notifyParent: true);
    _emitChanged();
  }

  Future<void> _autoAnchorFromBounds() async {
    if (_isAutoDetecting) {
      return;
    }
    setState(() {
      _isAutoDetecting = true;
    });
    final _AutoHitBoxDraft? autoDraft = await widget.onAutoBoundsDetect();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAutoDetecting = false;
    });
    final double nextAnchorX = autoDraft == null
        ? 0.5
        : (autoDraft.x + (autoDraft.width / 2)).clamp(0.0, 1.0);
    final double nextAnchorY = autoDraft == null
        ? 0.5
        : (autoDraft.y + (autoDraft.height / 2)).clamp(0.0, 1.0);
    if ((_anchorX - nextAnchorX).abs() < 0.0005 &&
        (_anchorY - nextAnchorY).abs() < 0.0005) {
      return;
    }
    setState(() {
      _anchorX = nextAnchorX;
      _anchorY = nextAnchorY;
      _refreshAnchorControllers();
    });
    _emitChanged();
  }

  void _showHitBoxColorPicker(int index) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    final GlobalKey anchorKey = _hitBoxColorAnchorKeys[index];
    if (anchorKey.currentContext == null) {
      return;
    }
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
      child: _HitBoxColorPicker(
        colorPalette: widget.hitBoxColorPalette,
        selectedColorName: _drafts[index].color,
        onSelected: (String colorName) {
          _updateHitBox(index, color: colorName);
          controller.close();
        },
      ),
    );
  }

  void _showAnchorColorPicker() {
    if (_anchorColorAnchorKey.currentContext == null) {
      return;
    }
    final CDKDialogController controller = CDKDialogController();
    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _anchorColorAnchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: _HitBoxColorPicker(
        title: 'Anchor Color',
        colorPalette: widget.anchorColorPalette,
        selectedColorName: _anchorColor,
        onSelected: (String colorName) {
          if (_anchorColor == colorName) {
            controller.close();
            return;
          }
          setState(() {
            _anchorColor = colorName;
          });
          _emitChanged();
          controller.close();
        },
      ),
    );
  }

  Widget _buildHitBoxInlineRow(
    BuildContext context,
    int index,
    _HitBoxDraft draft,
  ) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    const double colorButtonSlotWidth = 44;
    const double deleteButtonSlotWidth = 24;
    const double dragHandleSlotWidth = 18;
    return GestureDetector(
      onTap: () => _setSelectedIndex(index, notifyParent: true),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        color: cdkColors.backgroundSecondary0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: colorButtonSlotWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CDKButton(
                      key: _hitBoxColorAnchorKeys[index],
                      style: CDKButtonStyle.normal,
                      onPressed: () => _showHitBoxColorPicker(index),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: LayoutUtils.getColorFromName(draft.color),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(CupertinoIcons.chevron_down, size: 10),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: CDKFieldText(
                    placeholder: 'Name',
                    controller: _nameControllers[index],
                    onChanged: (value) {
                      if (_isApplyingControllers) return;
                      _updateHitBox(index, name: value);
                    },
                  ),
                ),
                SizedBox(width: spacing.xs),
                SizedBox(
                  width: deleteButtonSlotWidth,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(20, 20),
                    onPressed: () => _deleteHitBox(index),
                    child: Icon(
                      CupertinoIcons.minus_circle,
                      size: 16,
                      color: cdkColors.colorText,
                    ),
                  ),
                ),
                SizedBox(width: spacing.xs),
                SizedBox(
                  width: dragHandleSlotWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        CupertinoIcons.bars,
                        size: 14,
                        color: cdkColors.colorText.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            Padding(
              padding: EdgeInsets.only(
                left: colorButtonSlotWidth + spacing.xs,
                right: deleteButtonSlotWidth +
                    dragHandleSlotWidth +
                    spacing.xs * 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CDKFieldText(
                      placeholder: 'X',
                      controller: _xControllers[index],
                      onChanged: (value) {
                        if (_isApplyingControllers) return;
                        final double? parsed = _parseUnit(value);
                        if (parsed != null) _updateHitBox(index, x: parsed);
                      },
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: CDKFieldText(
                      placeholder: 'Y',
                      controller: _yControllers[index],
                      onChanged: (value) {
                        if (_isApplyingControllers) return;
                        final double? parsed = _parseUnit(value);
                        if (parsed != null) _updateHitBox(index, y: parsed);
                      },
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: CDKFieldText(
                      placeholder: 'W',
                      controller: _widthControllers[index],
                      onChanged: (value) {
                        if (_isApplyingControllers) return;
                        final double? parsed = _parseUnit(value);
                        if (parsed != null) _updateHitBox(index, width: parsed);
                      },
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: CDKFieldText(
                      placeholder: 'H',
                      controller: _heightControllers[index],
                      onChanged: (value) {
                        if (_isApplyingControllers) return;
                        final double? parsed = _parseUnit(value);
                        if (parsed != null) {
                          _updateHitBox(index, height: parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reorderHitBoxes(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _drafts.length ||
        newIndex < 0 ||
        newIndex > _drafts.length) {
      return;
    }
    int insertIndex = newIndex;
    if (oldIndex < newIndex) {
      insertIndex -= 1;
    }
    if (insertIndex == oldIndex) {
      return;
    }

    final String? selectedId =
        (_selectedIndex >= 0 && _selectedIndex < _drafts.length)
            ? _drafts[_selectedIndex].id
            : null;

    setState(() {
      T reorderList<T>(List<T> list) {
        final T item = list.removeAt(oldIndex);
        list.insert(insertIndex, item);
        return item;
      }

      reorderList(_drafts);
      reorderList(_nameControllers);
      reorderList(_xControllers);
      reorderList(_yControllers);
      reorderList(_widthControllers);
      reorderList(_heightControllers);
      reorderList(_hitBoxColorAnchorKeys);

      if (selectedId != null) {
        _selectedIndex = _drafts.indexWhere((item) => item.id == selectedId);
      }
    });

    widget.onSelectedHitBoxChanged(_selectedIndex);
    _emitChanged();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    const double rowHorizontalInset = 6;
    const double anchorColorSlotWidth = 44;
    const double autoButtonSlotWidth = 56;
    final BoxConstraints panelConstraints = BoxConstraints(
      minWidth: widget.panelWidth,
      maxWidth: widget.panelWidth,
    );

    final Widget anchorPanel = Padding(
      padding: const EdgeInsets.symmetric(horizontal: rowHorizontalInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: anchorColorSlotWidth,
                child: const CDKText('Color', role: CDKTextRole.caption),
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: const CDKText('X', role: CDKTextRole.caption),
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: const CDKText('Y', role: CDKTextRole.caption),
              ),
              SizedBox(width: spacing.xs),
              const SizedBox(width: autoButtonSlotWidth),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: anchorColorSlotWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CDKButton(
                    key: _anchorColorAnchorKey,
                    style: CDKButtonStyle.normal,
                    onPressed: _showAnchorColorPicker,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: LayoutUtils.getColorFromName(_anchorColor),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(CupertinoIcons.chevron_down, size: 10),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: CDKFieldText(
                  controller: _anchorXController,
                  placeholder: '0.00',
                  onChanged: _updateAnchorX,
                  onSubmitted: (_) => _refreshAnchorControllers(),
                ),
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                child: CDKFieldText(
                  controller: _anchorYController,
                  placeholder: '0.00',
                  onChanged: _updateAnchorY,
                  onSubmitted: (_) => _refreshAnchorControllers(),
                ),
              ),
              SizedBox(width: spacing.xs),
              SizedBox(
                width: autoButtonSlotWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: CDKButton(
                    style: CDKButtonStyle.action,
                    onPressed: _isAutoDetecting ? null : _autoAnchorFromBounds,
                    child: _isAutoDetecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CupertinoActivityIndicator(radius: 6),
                          )
                        : const Text('Auto'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CDKText('Edit animation rigs', role: CDKTextRole.title),
        SizedBox(height: spacing.md + spacing.xs),
        const CDKText('Selected Frames', role: CDKTextRole.caption),
        const SizedBox(height: 4),
        CDKText(
          widget.selectedFramesLabel,
          role: CDKTextRole.bodyStrong,
        ),
        const SizedBox(height: 2),
        const CDKText(
          'Changes in this editor are applied to the selected frames.',
          role: CDKTextRole.caption,
          secondary: true,
        ),
        SizedBox(height: spacing.md),
        const CDKText('Anchor Point', role: CDKTextRole.caption),
        SizedBox(height: spacing.xs),
        anchorPanel,
        SizedBox(height: spacing.md + spacing.sm),
        const CDKText('Hit Boxes', role: CDKTextRole.caption),
        SizedBox(height: spacing.xs),
        if (_drafts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: CDKText(
              'No hit boxes yet.',
              role: CDKTextRole.caption,
              secondary: true,
            ),
          ),
      ],
    );

    final Widget footer = Padding(
      padding: EdgeInsets.only(top: spacing.sm, bottom: spacing.md),
      child: Align(
        alignment: Alignment.center,
        child: CDKButton(
          style: CDKButtonStyle.action,
          onPressed: _isAutoDetecting ? null : _addHitBox,
          child: _isAutoDetecting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CupertinoActivityIndicator(radius: 6),
                )
              : const Text('Add Hit Box'),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: panelConstraints,
      child: Localizations.override(
        context: context,
        delegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemExtent: 72,
          cacheExtent: 960,
          padding: EdgeInsets.fromLTRB(spacing.md, spacing.md, spacing.md, 0),
          header: header,
          footer: footer,
          itemCount: _drafts.length,
          onReorder: _reorderHitBoxes,
          itemBuilder: (context, index) {
            final _HitBoxDraft draft = _drafts[index];
            return RepaintBoundary(
              key: ValueKey(draft.id),
              child: _buildHitBoxInlineRow(context, index, draft),
            );
          },
        ),
      ),
    );
  }
}

class _HitBoxColorPicker extends StatelessWidget {
  const _HitBoxColorPicker({
    required this.colorPalette,
    required this.selectedColorName,
    required this.onSelected,
    this.title = 'Box Color',
  });

  final List<String> colorPalette;
  final String selectedColorName;
  final ValueChanged<String> onSelected;
  final String title;

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
            CDKText(title, role: CDKTextRole.caption),
            SizedBox(height: spacing.xs),
            Wrap(
              spacing: spacing.xs,
              runSpacing: spacing.xs,
              children: colorPalette
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

class _AnimationRigFramePreviewPainter extends CustomPainter {
  const _AnimationRigFramePreviewPainter({
    required this.image,
    required this.frameWidth,
    required this.frameHeight,
    required this.columns,
    required this.frameIndex,
    required this.anchorX,
    required this.anchorY,
    required this.anchorColor,
    required this.checkerA,
    required this.checkerB,
    required this.borderColor,
    required this.guideColor,
    required this.anchorOutlineColor,
  });

  final ui.Image image;
  final double frameWidth;
  final double frameHeight;
  final int columns;
  final int frameIndex;
  final double anchorX;
  final double anchorY;
  final Color anchorColor;
  final Color checkerA;
  final Color checkerB;
  final Color borderColor;
  final Color guideColor;
  final Color anchorOutlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgA = Paint()..color = checkerA;
    final Paint bgB = Paint()..color = checkerB;
    const double checker = 12.0;
    for (double y = 0; y < size.height; y += checker) {
      for (double x = 0; x < size.width; x += checker) {
        final bool even =
            ((x / checker).floor() + (y / checker).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, checker, checker),
          even ? bgA : bgB,
        );
      }
    }

    if (frameWidth <= 0 ||
        frameHeight <= 0 ||
        columns <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final int row = frameIndex ~/ columns;
    final int col = frameIndex % columns;
    final Rect src = Rect.fromLTWH(
      col * frameWidth,
      row * frameHeight,
      frameWidth,
      frameHeight,
    );
    if (src.right > image.width || src.bottom > image.height) {
      return;
    }

    final double clampedAnchorX = anchorX.clamp(0.0, 1.0);
    final double clampedAnchorY = anchorY.clamp(0.0, 1.0);
    const double padding = 4.0;
    final Offset targetAnchor = Offset(size.width / 2, size.height / 2);

    final double maxDrawWidth = _maxExtentForAnchor(
      anchor: clampedAnchorX,
      before: targetAnchor.dx - padding,
      after: size.width - targetAnchor.dx - padding,
    );
    final double maxDrawHeight = _maxExtentForAnchor(
      anchor: clampedAnchorY,
      before: targetAnchor.dy - padding,
      after: size.height - targetAnchor.dy - padding,
    );
    if (maxDrawWidth <= 0 || maxDrawHeight <= 0) {
      return;
    }

    final double scale = math.min(
      maxDrawWidth / frameWidth,
      maxDrawHeight / frameHeight,
    );
    if (!scale.isFinite || scale <= 0) {
      return;
    }
    final double drawWidth = frameWidth * scale;
    final double drawHeight = frameHeight * scale;
    final Rect dst = Rect.fromLTWH(
      targetAnchor.dx - drawWidth * clampedAnchorX,
      targetAnchor.dy - drawHeight * clampedAnchorY,
      drawWidth,
      drawHeight,
    );

    final Paint guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(padding, targetAnchor.dy),
      Offset(size.width - padding, targetAnchor.dy),
      guidePaint,
    );
    canvas.drawLine(
      Offset(targetAnchor.dx, padding),
      Offset(targetAnchor.dx, size.height - padding),
      guidePaint,
    );

    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.none,
    );

    canvas.drawRect(
      dst,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.drawCircle(
      targetAnchor,
      5.2,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      targetAnchor,
      4.2,
      Paint()
        ..color = anchorColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      targetAnchor,
      4.2,
      Paint()
        ..color = anchorOutlineColor.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  static double _maxExtentForAnchor({
    required double anchor,
    required double before,
    required double after,
  }) {
    final double safeBefore = math.max(0.0, before);
    final double safeAfter = math.max(0.0, after);
    const double epsilon = 0.000001;
    final double beforeLimit =
        anchor > epsilon ? safeBefore / anchor : double.infinity;
    final double afterLimit =
        anchor < 1.0 - epsilon ? safeAfter / (1.0 - anchor) : double.infinity;
    return math.min(beforeLimit, afterLimit);
  }

  @override
  bool shouldRepaint(covariant _AnimationRigFramePreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.columns != columns ||
        oldDelegate.frameIndex != frameIndex ||
        oldDelegate.anchorX != anchorX ||
        oldDelegate.anchorY != anchorY ||
        oldDelegate.anchorColor != anchorColor ||
        oldDelegate.checkerA != checkerA ||
        oldDelegate.checkerB != checkerB ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.guideColor != guideColor ||
        oldDelegate.anchorOutlineColor != anchorOutlineColor;
  }
}
