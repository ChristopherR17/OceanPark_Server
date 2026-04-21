import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_animation.dart';
import 'game_list_group.dart';
import 'game_media_asset.dart';
import 'layout_utils.dart';
import 'widgets/edit_session.dart';
import 'widgets/editor_entity_form_mode.dart';
import 'widgets/editor_form_dialog_scaffold.dart';
import 'widgets/editor_header_delete_button.dart';
import 'widgets/editor_labeled_field.dart';
import 'widgets/editor_live_edit_session.dart';
import 'widgets/grouped_list.dart';
import 'widgets/section_help_button.dart';

class LayoutAnimations extends StatefulWidget {
  const LayoutAnimations({super.key});

  @override
  State<LayoutAnimations> createState() => _LayoutAnimationsState();
}

class _LayoutAnimationsState extends State<LayoutAnimations> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _addGroupToolbarAnchorKey = GlobalKey();
  final Map<String, GlobalKey> _groupActionsAnchorKeys = <String, GlobalKey>{};
  int _newGroupCounter = 0;
  String? _hoveredGroupId;
  Timer? _previewTimer;
  DateTime? _previewLastTick;
  String _previewAnimationId = '';
  double _previewElapsedSeconds = 0.0;
  bool _previewPlaying = false;

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

  Widget _buildPreviewPanel(AppData appData, GameAnimation? animation) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final bool hasAnimation = animation != null;
    const double previewCanvasHeight = 120;

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
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return CustomPaint(
                                painter: _AnimationFramePreviewPainter(
                                  image: image,
                                  frameWidth: frameWidth,
                                  frameHeight: frameHeight,
                                  columns: cols,
                                  frameIndex: frameIndex,
                                ),
                              );
                            },
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

  List<GameMediaAsset> _animationSourceAssets(AppData appData) {
    return appData.gameData.mediaAssets
        .where(
          (asset) =>
              asset.mediaType == 'spritesheet' || asset.mediaType == 'atlas',
        )
        .toList(growable: false);
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

  GameListGroup? _findAnimationGroupById(AppData appData, String groupId) {
    for (final group in _animationGroups(appData)) {
      if (group.id == groupId) {
        return group;
      }
    }
    return null;
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

  GlobalKey _groupActionsAnchorKey(String groupId) {
    return _groupActionsAnchorKeys.putIfAbsent(groupId, GlobalKey.new);
  }

  void _setHoveredGroupId(String? groupId) {
    if (_hoveredGroupId == groupId || !mounted) {
      return;
    }
    setState(() {
      _hoveredGroupId = groupId;
    });
  }

  Set<String> _animationGroupNames(
    AppData appData, {
    String? excludingId,
  }) {
    return _animationGroups(appData)
        .where((group) => group.id != excludingId)
        .map((group) => group.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  String _newGroupId() {
    return '__group_${DateTime.now().microsecondsSinceEpoch}_${_newGroupCounter++}';
  }

  Future<bool> _upsertAnimationGroup(
    AppData appData,
    GroupedListGroupDraft draft,
  ) async {
    final String nextName = draft.name.trim();
    if (nextName.isEmpty) {
      return false;
    }
    if (_animationGroupNames(appData, excludingId: draft.id)
        .contains(nextName.toLowerCase())) {
      return false;
    }

    await appData.runProjectMutation(
      debugLabel: 'animation-group-upsert',
      mutate: () {
        _ensureMainAnimationGroup(appData);
        final List<GameListGroup> groups = appData.gameData.animationGroups;
        final int existingIndex =
            groups.indexWhere((group) => group.id == draft.id);
        if (existingIndex != -1) {
          groups[existingIndex].name = nextName;
          return;
        }
        groups.add(
          GameListGroup(
            id: draft.id,
            name: nextName,
            collapsed: false,
          ),
        );
      },
    );

    return true;
  }

  Future<bool> _confirmAndDeleteAnimationGroup(
      AppData appData, String groupId) async {
    if (!mounted) {
      return false;
    }
    if (groupId == GameListGroup.mainId) {
      return false;
    }

    final GameListGroup? group = _findAnimationGroupById(appData, groupId);
    if (group == null) {
      return false;
    }

    final List<GameAnimation> animationsInGroup = appData.gameData.animations
        .where(
          (animation) =>
              _effectiveAnimationGroupId(appData, animation) == groupId,
        )
        .toList(growable: false);

    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete group',
      message: animationsInGroup.isNotEmpty
          ? 'Delete "${group.name}"? ${animationsInGroup.length} animation(s) will be moved to "Main".'
          : 'Delete "${group.name}"?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }

    await appData.runProjectMutation(
      debugLabel: 'animation-group-delete',
      mutate: () {
        _ensureMainAnimationGroup(appData);
        final List<GameListGroup> groups = appData.gameData.animationGroups;
        final List<GameAnimation> animations = appData.gameData.animations;
        final int groupIndex = groups.indexWhere((g) => g.id == groupId);
        if (groupIndex == -1) {
          return;
        }
        GroupedListAlgorithms.reassignItemsToGroup<GameAnimation>(
          items: animations,
          fromGroupId: groupId,
          toGroupId: GameAnimation.defaultGroupId,
          itemGroupIdOf: (animation) => animation.groupId,
          setItemGroupId: (animation, nextGroupId) {
            animation.groupId = nextGroupId;
          },
        );
        groups.removeAt(groupIndex);
      },
    );

    return true;
  }

  Future<void> _showAddGroupPopover(AppData appData) async {
    if (Overlay.maybeOf(context) == null) {
      return;
    }
    final CDKDialogController controller = CDKDialogController();
    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _addGroupToolbarAnchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: GroupedListAddGroupPopover(
        title: 'Add Animation Group',
        existingNames: _animationGroups(appData).map((group) => group.name),
        onCancel: controller.close,
        onAdd: (name) async {
          final bool added = await _upsertAnimationGroup(
            appData,
            GroupedListGroupDraft(
              id: _newGroupId(),
              name: name,
              collapsed: false,
            ),
          );
          if (added) {
            controller.close();
          }
          return added;
        },
      ),
    );
  }

  Future<void> _showGroupActionsPopover(
    AppData appData,
    GameListGroup group,
    GlobalKey anchorKey,
  ) async {
    if (Overlay.maybeOf(context) == null) {
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
      child: GroupedListEditGroupPopover(
        initialName: group.name,
        existingNames: _animationGroups(appData)
            .where((candidate) => candidate.id != group.id)
            .map((candidate) => candidate.name),
        onCancel: controller.close,
        onRename: (name) async {
          final bool renamed = await _upsertAnimationGroup(
            appData,
            GroupedListGroupDraft(
              id: group.id,
              name: name,
              collapsed: group.collapsed,
            ),
          );
          return renamed;
        },
        onDelete: group.id == GameListGroup.mainId
            ? null
            : () async {
                final bool deleted =
                    await _confirmAndDeleteAnimationGroup(appData, group.id);
                if (deleted) {
                  controller.close();
                }
                return deleted;
              },
      ),
    );
  }

  void _syncFrameSelectionToAnimation(
      AppData appData, GameAnimation? animation) {
    if (animation == null) {
      LayoutUtils.clearAnimationFrameSelection(appData);
      return;
    }
    appData.animationSelectionStartFrame = animation.startFrame;
    appData.animationSelectionEndFrame = animation.endFrame;
  }

  void _addAnimation({
    required AppData appData,
    required _AnimationDialogData data,
  }) {
    _ensureMainAnimationGroup(appData);
    final Set<String> validGroupIds =
        _animationGroups(appData).map((group) => group.id).toSet();
    final String targetGroupId = validGroupIds.contains(data.groupId)
        ? data.groupId
        : GameListGroup.mainId;
    appData.gameData.animations.add(
      GameAnimation(
        id: 'anim_${DateTime.now().microsecondsSinceEpoch}',
        name: data.name,
        mediaFile: data.mediaFile,
        startFrame: data.startFrame,
        endFrame: data.endFrame,
        fps: data.fps,
        loop: data.loop,
        groupId: targetGroupId,
      ),
    );
    appData.selectedAnimation = -1;
    appData.update();
  }

  Future<_AnimationDialogData?> _promptAnimationData({
    required String title,
    required EditorEntityFormMode mode,
    required _AnimationDialogData initialData,
    required List<GameMediaAsset> sourceAssets,
    List<GameListGroup> groupOptions = const <GameListGroup>[],
    bool showGroupSelector = false,
    String groupFieldLabel = 'Animation Group',
    GlobalKey? anchorKey,
    bool useArrowedPopover = false,
    Future<void> Function(_AnimationDialogData value)? onLiveChanged,
    VoidCallback? onDelete,
  }) async {
    if (Overlay.maybeOf(context) == null) {
      return null;
    }

    final AppData appData = Provider.of<AppData>(context, listen: false);
    final CDKDialogController controller = CDKDialogController();
    final Completer<_AnimationDialogData?> completer =
        Completer<_AnimationDialogData?>();
    _AnimationDialogData? result;

    final dialogChild = _AnimationFormDialog(
      title: title,
      mode: mode,
      initialData: initialData,
      sourceAssets: sourceAssets,
      groupOptions: groupOptions,
      showGroupSelector: showGroupSelector,
      groupFieldLabel: groupFieldLabel,
      onLiveChanged: onLiveChanged,
      onClose: () {
        unawaited(() async {
          await appData.flushPendingAutosave();
          controller.close();
        }());
      },
      onConfirm: (value) {
        result = value;
        controller.close();
      },
      onCancel: controller.close,
      onDelete: onDelete != null
          ? () {
              controller.close();
              onDelete();
            }
          : null,
    );

    if (useArrowedPopover && anchorKey != null) {
      CDKDialogsManager.showPopoverArrowed(
        context: context,
        anchorKey: anchorKey,
        isAnimated: true,
        animateContentResize: false,
        dismissOnEscape: true,
        dismissOnOutsideTap: true,
        showBackgroundShade: false,
        controller: controller,
        onHide: () {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
        child: dialogChild,
      );
    } else {
      CDKDialogsManager.showModal(
        context: context,
        dismissOnEscape: true,
        dismissOnOutsideTap: false,
        showBackgroundShade: true,
        controller: controller,
        onHide: () {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
        child: dialogChild,
      );
    }

    return completer.future;
  }

  Future<void> _promptAndAddAnimation(List<GameMediaAsset> sourceAssets) async {
    if (sourceAssets.isEmpty) {
      return;
    }
    final AppData appData = Provider.of<AppData>(context, listen: false);
    _ensureMainAnimationGroup(appData);
    appData.selectedAnimation = -1;
    _syncFrameSelectionToAnimation(appData, null);
    appData.update();
    final GameMediaAsset first = sourceAssets.first;
    final _AnimationDialogData? data = await _promptAnimationData(
      title: 'New animation',
      mode: EditorEntityFormMode.add,
      initialData: _AnimationDialogData(
        name: '',
        mediaFile: first.fileName,
        startFrame: 0,
        endFrame: 0,
        fps: 12.0,
        loop: true,
        groupId: GameListGroup.mainId,
      ),
      sourceAssets: sourceAssets,
      groupOptions: _animationGroups(appData),
      showGroupSelector: true,
      groupFieldLabel: 'Animation Group',
    );
    if (!mounted || data == null) {
      return;
    }
    await appData.runProjectMutation(
      debugLabel: 'animation-add',
      mutate: () {
        _addAnimation(appData: appData, data: data);
      },
    );
  }

  void _selectAnimation(AppData appData, int index, bool isSelected) {
    if (isSelected) {
      appData.selectedAnimation = -1;
      _syncFrameSelectionToAnimation(appData, null);
      appData.update();
      return;
    }
    appData.selectedAnimation = index;
    if (index >= 0 && index < appData.gameData.animations.length) {
      _syncFrameSelectionToAnimation(
        appData,
        appData.gameData.animations[index],
      );
    } else {
      _syncFrameSelectionToAnimation(appData, null);
    }
    appData.update();
  }

  int _selectedAnimationUsageCount(AppData appData, String animationId) {
    int count = 0;
    for (final level in appData.gameData.levels) {
      for (final sprite in level.sprites) {
        if (sprite.animationId == animationId) {
          count += 1;
        }
      }
    }
    return count;
  }

  Future<bool> confirmAndDeleteSelectedAnimationFromKeyboard(
    AppData appData,
  ) async {
    final int index = appData.selectedAnimation;
    if (index < 0 || index >= appData.gameData.animations.length || !mounted) {
      return false;
    }
    final GameAnimation animation = appData.gameData.animations[index];
    if (_selectedAnimationUsageCount(appData, animation.id) > 0) {
      return false;
    }
    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete animation',
      message: 'Delete this animation? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    await appData.runProjectMutation(
      debugLabel: 'animation-delete',
      mutate: () {
        if (index < 0 || index >= appData.gameData.animations.length) {
          return;
        }
        appData.gameData.animations.removeAt(index);
        appData.selectedAnimation = -1;
        LayoutUtils.clearAnimationFrameSelection(appData);
      },
    );
    return true;
  }

  Future<void> _toggleGroupCollapsed(AppData appData, String groupId) async {
    await appData.runProjectMutation(
      debugLabel: 'animation-group-toggle-collapse',
      mutate: () {
        _ensureMainAnimationGroup(appData);
        final List<GameListGroup> groups = appData.gameData.animationGroups;
        final int index = groups.indexWhere((group) => group.id == groupId);
        if (index == -1) {
          return;
        }
        final GameListGroup group = groups[index];
        group.collapsed = !group.collapsed;
        if (group.collapsed &&
            appData.selectedAnimation >= 0 &&
            appData.selectedAnimation < appData.gameData.animations.length &&
            _effectiveAnimationGroupId(
                  appData,
                  appData.gameData.animations[appData.selectedAnimation],
                ) ==
                group.id) {
          appData.selectedAnimation = -1;
          _syncFrameSelectionToAnimation(appData, null);
        }
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
        debugLabel: 'animation-reorder',
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

  @override
  Widget build(BuildContext context) {
    final AppData appData = Provider.of<AppData>(context);
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
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
          'Select a project to manage animations.',
          role: CDKTextRole.body,
          secondary: true,
        ),
      );
    }

    final List<GameMediaAsset> sourceAssets = _animationSourceAssets(appData);
    final bool hasSources = sourceAssets.isNotEmpty;
    final animations = appData.gameData.animations;
    final animationRows = _buildAnimationRows(appData);

    if (appData.selectedAnimation >= animations.length) {
      appData.selectedAnimation =
          animations.isEmpty ? -1 : animations.length - 1;
      if (appData.selectedAnimation >= 0 &&
          appData.selectedAnimation < animations.length) {
        _syncFrameSelectionToAnimation(
          appData,
          animations[appData.selectedAnimation],
        );
      } else {
        _syncFrameSelectionToAnimation(appData, null);
      }
    }

    final GameAnimation? selectedAnimation = appData.selectedAnimation >= 0 &&
            appData.selectedAnimation < animations.length
        ? animations[appData.selectedAnimation]
        : null;
    _syncPreviewSelection(selectedAnimation);
    final bool hasSelectedAnimation = selectedAnimation != null;
    final bool isPreviewPlaying = hasSelectedAnimation && _previewPlaying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              CDKText(
                'Animations',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'Animations define sequences of frames from a spritesheet. They are referenced by sprites to bring game characters and objects to life.',
              ),
              const Spacer(),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: hasSources
                    ? () async {
                        await _promptAndAddAnimation(sourceAssets);
                      }
                    : null,
                child: const Text('+ Animation'),
              ),
              SizedBox(width: spacing.xs),
              CDKButton(
                key: _addGroupToolbarAnchorKey,
                style: CDKButtonStyle.normal,
                onPressed: () async {
                  await _showAddGroupPopover(appData);
                },
                child: const Icon(
                  CupertinoIcons.rectangle_stack,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CDKButton(
                style: CDKButtonStyle.normal,
                onPressed: hasSelectedAnimation
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
                onPressed: hasSelectedAnimation ? _restartPreview : null,
                child: const Icon(
                  CupertinoIcons.refresh,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
        _buildPreviewPanel(appData, selectedAnimation),
        if (animations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CDKText(
              hasSources
                  ? '(No animations defined)'
                  : 'Add a spritesheet or atlas in Media first.',
              role: CDKTextRole.caption,
              secondary: true,
            ),
          ),
        Expanded(
          child: CupertinoScrollbar(
            controller: _scrollController,
            child: Localizations.override(
              context: context,
              delegates: [
                DefaultMaterialLocalizations.delegate,
                DefaultWidgetsLocalizations.delegate,
              ],
              child: ReorderableListView.builder(
                scrollController: _scrollController,
                buildDefaultDragHandles: false,
                itemCount: animationRows.length,
                onReorder: (oldIndex, newIndex) => _onReorder(
                  appData,
                  animationRows,
                  oldIndex,
                  newIndex,
                ),
                itemBuilder: (context, index) {
                  final GroupedListRow<GameListGroup, GameAnimation> row =
                      animationRows[index];
                  if (row.isGroup) {
                    final GameListGroup group = row.group!;
                    final bool showGroupActions = _hoveredGroupId == group.id;
                    final GlobalKey groupActionsAnchorKey =
                        _groupActionsAnchorKey(group.id);
                    return MouseRegion(
                      key: ValueKey('animation-group-hover-${group.id}'),
                      onEnter: (_) => _setHoveredGroupId(group.id),
                      onExit: (_) {
                        if (_hoveredGroupId == group.id) {
                          _setHoveredGroupId(null);
                        }
                      },
                      child: Container(
                        key: ValueKey('animation-group-${group.id}'),
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        color: cdkColors.backgroundSecondary1,
                        child: Row(
                          children: [
                            CupertinoButton(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
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
                              child: Row(
                                children: [
                                  CDKText(
                                    group.name,
                                    role: CDKTextRole.body,
                                    style: listItemTitleStyle,
                                  ),
                                  if (group.id == GameListGroup.mainId) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      CupertinoIcons.lock_fill,
                                      size: 12,
                                      color: cdkColors.colorText
                                          .withValues(alpha: 0.7),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (showGroupActions)
                              CupertinoButton(
                                key: groupActionsAnchorKey,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                minimumSize: const Size(20, 20),
                                onPressed: () async {
                                  await _showGroupActionsPopover(
                                    appData,
                                    group,
                                    groupActionsAnchorKey,
                                  );
                                },
                                child: Icon(
                                  CupertinoIcons.ellipsis_circle,
                                  size: 15,
                                  color: cdkColors.colorText,
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

class _AnimationDialogData {
  const _AnimationDialogData({
    required this.name,
    required this.mediaFile,
    required this.startFrame,
    required this.endFrame,
    required this.fps,
    required this.loop,
    required this.groupId,
  });

  final String name;
  final String mediaFile;
  final int startFrame;
  final int endFrame;
  final double fps;
  final bool loop;
  final String groupId;
}

class AnimationInlineEditPanel extends StatefulWidget {
  const AnimationInlineEditPanel({
    super.key,
    required this.animationIndex,
  });

  final int animationIndex;

  @override
  State<AnimationInlineEditPanel> createState() =>
      _AnimationInlineEditPanelState();
}

class _AnimationInlineEditPanelState extends State<AnimationInlineEditPanel> {
  late final String _undoGroupKey =
      'animation-inline-${DateTime.now().microsecondsSinceEpoch}';

  List<GameMediaAsset> _animationSourceAssets(AppData appData) {
    return appData.gameData.mediaAssets
        .where(
          (asset) =>
              asset.mediaType == 'spritesheet' || asset.mediaType == 'atlas',
        )
        .toList(growable: false);
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

  String _effectiveAnimationGroupId(AppData appData, GameAnimation animation) {
    final String groupId = animation.groupId.trim();
    final Set<String> validGroupIds =
        _animationGroups(appData).map((group) => group.id).toSet();
    if (groupId.isNotEmpty && validGroupIds.contains(groupId)) {
      return groupId;
    }
    return GameListGroup.mainId;
  }

  int _animationUsageCount(AppData appData, String animationId) {
    int count = 0;
    for (final level in appData.gameData.levels) {
      for (final sprite in level.sprites) {
        if (sprite.animationId == animationId) {
          count += 1;
        }
      }
    }
    return count;
  }

  void _applyAnimationMediaToSprites(
    AppData appData,
    GameAnimation animation,
  ) {
    final GameMediaAsset? media =
        appData.mediaAssetByFileName(animation.mediaFile);
    for (final level in appData.gameData.levels) {
      for (final sprite in level.sprites) {
        if (sprite.animationId != animation.id) {
          continue;
        }
        sprite.imageFile = animation.mediaFile;
        if (media != null && media.tileWidth > 0 && media.tileHeight > 0) {
          sprite.spriteWidth = media.tileWidth;
          sprite.spriteHeight = media.tileHeight;
        }
      }
    }
  }

  Future<void> _applyAnimationChange(
    AppData appData,
    _AnimationDialogData value, {
    required bool groupedUndo,
  }) async {
    await appData.runProjectMutation(
      debugLabel:
          groupedUndo ? 'animation-inline-live-edit' : 'animation-inline-edit',
      undoGroupKey: groupedUndo ? _undoGroupKey : null,
      mutate: () {
        _ensureMainAnimationGroup(appData);
        final List<GameAnimation> animations = appData.gameData.animations;
        final int index = widget.animationIndex;
        if (index < 0 || index >= animations.length) {
          return;
        }
        final GameAnimation previous = animations[index];
        final Set<String> validGroupIds =
            appData.gameData.animationGroups.map((group) => group.id).toSet();
        final String targetGroupId = validGroupIds.contains(value.groupId)
            ? value.groupId
            : GameListGroup.mainId;
        final GameAnimation updated = GameAnimation(
          id: previous.id,
          name: value.name,
          mediaFile: value.mediaFile,
          startFrame: value.startFrame,
          endFrame: value.endFrame,
          fps: value.fps,
          loop: value.loop,
          groupId: targetGroupId,
          anchorX: previous.anchorX,
          anchorY: previous.anchorY,
          anchorColor: previous.anchorColor,
          hitBoxes: previous.hitBoxes,
        );
        animations[index] = updated;
        _applyAnimationMediaToSprites(appData, updated);
        appData.selectedAnimation = index;
        appData.animationSelectionStartFrame = updated.startFrame;
        appData.animationSelectionEndFrame = updated.endFrame;
      },
    );
  }

  Future<void> _deleteAnimation(AppData appData, int index) async {
    final List<GameAnimation> animations = appData.gameData.animations;
    if (index < 0 || index >= animations.length) {
      return;
    }
    await appData.runProjectMutation(
      debugLabel: 'animation-delete',
      mutate: () {
        if (index < 0 || index >= animations.length) {
          return;
        }
        animations.removeAt(index);
        appData.selectedAnimation = -1;
        LayoutUtils.clearAnimationFrameSelection(appData);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppData appData = Provider.of<AppData>(context);
    final List<GameAnimation> animations = appData.gameData.animations;
    final int index = widget.animationIndex;
    if (index < 0 || index >= animations.length) {
      return const SizedBox.shrink();
    }
    final GameAnimation animation = animations[index];
    final List<GameMediaAsset> sourceAssets = _animationSourceAssets(appData);
    final int usageCount = _animationUsageCount(appData, animation.id);

    return _AnimationFormDialog(
      title: 'Edit animation',
      mode: EditorEntityFormMode.edit,
      initialData: _AnimationDialogData(
        name: animation.name,
        mediaFile: animation.mediaFile,
        startFrame: animation.startFrame,
        endFrame: animation.endFrame,
        fps: animation.fps,
        loop: animation.loop,
        groupId: _effectiveAnimationGroupId(appData, animation),
      ),
      sourceAssets: sourceAssets,
      groupOptions: _animationGroups(appData),
      showGroupSelector: true,
      groupFieldLabel: 'Animation Group',
      minWidth: 280,
      maxWidth: 360,
      onLiveChanged: (value) async {
        await _applyAnimationChange(appData, value, groupedUndo: true);
      },
      onConfirm: (value) {
        unawaited(_applyAnimationChange(appData, value, groupedUndo: false));
      },
      onCancel: () {
        appData.selectedAnimation = -1;
        LayoutUtils.clearAnimationFrameSelection(appData);
        appData.update();
      },
      onDelete: usageCount == 0
          ? () {
              unawaited(_deleteAnimation(appData, index));
            }
          : null,
    );
  }
}

class _AnimationFormDialog extends StatefulWidget {
  const _AnimationFormDialog({
    required this.title,
    required this.mode,
    required this.initialData,
    required this.sourceAssets,
    required this.groupOptions,
    required this.showGroupSelector,
    required this.groupFieldLabel,
    this.onLiveChanged,
    this.onClose,
    this.minWidth = 400,
    this.maxWidth = 540,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
  });

  final String title;
  final EditorEntityFormMode mode;
  final _AnimationDialogData initialData;
  final List<GameMediaAsset> sourceAssets;
  final List<GameListGroup> groupOptions;
  final bool showGroupSelector;
  final String groupFieldLabel;
  final Future<void> Function(_AnimationDialogData value)? onLiveChanged;
  final VoidCallback? onClose;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<_AnimationDialogData> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  State<_AnimationFormDialog> createState() => _AnimationFormDialogState();
}

class _AnimationFormDialogState extends State<_AnimationFormDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialData.name,
  );
  late final TextEditingController _startFrameController =
      TextEditingController(text: widget.initialData.startFrame.toString());
  late final TextEditingController _endFrameController =
      TextEditingController(text: widget.initialData.endFrame.toString());
  late final TextEditingController _fpsController = TextEditingController(
    text: widget.initialData.fps.toStringAsFixed(1),
  );
  late bool _loop = widget.initialData.loop;
  late int _selectedAssetIndex = _resolveInitialAssetIndex();
  late String _selectedGroupId = _resolveInitialGroupId();
  EditSession<_AnimationDialogData>? _editSession;

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _setFpsFromNumericValue(double value) {
    final String next = value.toStringAsFixed(1);
    if (_fpsController.text != next) {
      _setControllerText(_fpsController, next);
    }
    setState(() {});
    _onInputChanged();
  }

  int _resolveInitialAssetIndex() {
    final String current = widget.initialData.mediaFile;
    if (current.isNotEmpty) {
      final int found =
          widget.sourceAssets.indexWhere((asset) => asset.fileName == current);
      if (found != -1) {
        return found;
      }
    }
    return 0;
  }

  String _resolveInitialGroupId() {
    for (final group in widget.groupOptions) {
      if (group.id == widget.initialData.groupId) {
        return group.id;
      }
    }
    if (widget.groupOptions.isNotEmpty) {
      return widget.groupOptions.first.id;
    }
    return GameListGroup.mainId;
  }

  GameMediaAsset? get _selectedAsset {
    if (widget.sourceAssets.isEmpty) {
      return null;
    }
    if (_selectedAssetIndex < 0 ||
        _selectedAssetIndex >= widget.sourceAssets.length) {
      _selectedAssetIndex = 0;
    }
    return widget.sourceAssets[_selectedAssetIndex];
  }

  int? _parseFrame(String raw) {
    final int? value = int.tryParse(raw.trim());
    if (value == null || value < 0) {
      return null;
    }
    return value;
  }

  double? _parseFps(String raw) {
    final String normalized = raw.trim().replaceAll(',', '.');
    final double? value = double.tryParse(normalized);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  bool get _isValid {
    final int? start = _parseFrame(_startFrameController.text);
    final int? end = _parseFrame(_endFrameController.text);
    final double? fps = _parseFps(_fpsController.text);
    if (_nameController.text.trim().isEmpty || _selectedAsset == null) {
      return false;
    }
    if (start == null || end == null || fps == null) {
      return false;
    }
    return end >= start;
  }

  _AnimationDialogData _currentData() {
    final GameMediaAsset? asset = _selectedAsset;
    final int start = _parseFrame(_startFrameController.text) ?? 0;
    final int end = _parseFrame(_endFrameController.text) ?? start;
    return _AnimationDialogData(
      name: _nameController.text.trim(),
      mediaFile: asset?.fileName ?? widget.initialData.mediaFile,
      startFrame: start,
      endFrame: end < start ? start : end,
      fps: _parseFps(_fpsController.text) ?? 12.0,
      loop: _loop,
      groupId: _selectedGroupId,
    );
  }

  String? _validateData(_AnimationDialogData value) {
    if (value.name.trim().isEmpty) {
      return 'Animation name is required.';
    }
    if (_selectedAsset == null) {
      return 'Select a spritesheet or atlas in Media first.';
    }
    if (value.startFrame < 0 || value.endFrame < value.startFrame) {
      return 'Frame range must be valid.';
    }
    if (value.fps <= 0) {
      return 'FPS must be greater than 0.';
    }
    return null;
  }

  void _onInputChanged() {
    queueEditorLiveEditUpdate(
      mode: widget.mode,
      session: _editSession,
      value: _currentData(),
    );
  }

  void _confirm() {
    if (!_isValid) {
      return;
    }
    widget.onConfirm(_currentData());
  }

  @override
  void initState() {
    super.initState();
    _editSession = createEditorLiveEditSession<_AnimationDialogData>(
      mode: widget.mode,
      initialValue: _currentData(),
      validate: _validateData,
      onPersist: widget.onLiveChanged,
      areEqual: (a, b) =>
          a.name == b.name &&
          a.mediaFile == b.mediaFile &&
          a.startFrame == b.startFrame &&
          a.endFrame == b.endFrame &&
          a.fps == b.fps &&
          a.loop == b.loop &&
          a.groupId == b.groupId,
    );
  }

  @override
  void didUpdateWidget(covariant _AnimationFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialData.startFrame != widget.initialData.startFrame) {
      _setControllerText(
        _startFrameController,
        widget.initialData.startFrame.toString(),
      );
    }
    if (oldWidget.initialData.endFrame != widget.initialData.endFrame) {
      _setControllerText(
        _endFrameController,
        widget.initialData.endFrame.toString(),
      );
    }
    if ((oldWidget.initialData.fps - widget.initialData.fps).abs() > 0.0001) {
      _setControllerText(
        _fpsController,
        widget.initialData.fps.toStringAsFixed(1),
      );
    }
  }

  @override
  void dispose() {
    if (_editSession != null) {
      unawaited(_editSession!.flush());
      _editSession!.dispose();
    }
    _nameController.dispose();
    _startFrameController.dispose();
    _endFrameController.dispose();
    _fpsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final GameMediaAsset? asset = _selectedAsset;
    final List<String> mediaOptions = widget.sourceAssets
        .map((a) => a.name.trim().isNotEmpty ? a.name : a.fileName)
        .toList(growable: false);

    return EditorFormDialogScaffold(
      title: widget.title,
      description: '',
      confirmLabel: widget.mode.confirmLabel,
      confirmEnabled: _isValid,
      onConfirm: _confirm,
      onCancel: widget.onCancel,
      liveEditMode: widget.mode.isLiveEdit,
      onClose: widget.onClose,
      onDelete: widget.onDelete,
      headerTrailing: widget.onDelete == null
          ? null
          : EditorHeaderDeleteButton(
              onDelete: widget.onDelete!,
              title: 'Delete animation',
              message: 'Delete this animation? This cannot be undone.',
            ),
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabeledField(
            label: 'Animation Name',
            child: CDKFieldText(
              placeholder: 'Animation name',
              controller: _nameController,
              onChanged: (_) {
                setState(() {});
                _onInputChanged();
              },
              onSubmitted: (_) {
                if (widget.mode.isLiveEdit) {
                  _onInputChanged();
                  return;
                }
                _confirm();
              },
            ),
          ),
          SizedBox(height: spacing.sm),
          EditorLabeledField(
            label: 'Source Media',
            child: Row(
              children: [
                mediaOptions.isEmpty
                    ? const Expanded(
                        child: CDKText(
                          'No spritesheet or atlas available',
                          role: CDKTextRole.caption,
                          secondary: true,
                        ),
                      )
                    : CDKButtonSelect(
                        selectedIndex: _selectedAssetIndex,
                        options: mediaOptions,
                        onSelected: (int index) {
                          setState(() {
                            _selectedAssetIndex = index;
                          });
                          _onInputChanged();
                        },
                      ),
              ],
            ),
          ),
          SizedBox(height: spacing.sm),
          EditorLabeledField(
            label: 'Frame size',
            child: CDKText(
              asset != null
                  ? '${asset.tileWidth}×${asset.tileHeight} px'
                  : 'No media selected',
              role: CDKTextRole.caption,
              color: cdkColors.colorText,
              secondary: true,
            ),
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: EditorLabeledField(
                  label: 'Start Frame',
                  child: CDKFieldText(
                    placeholder: 'Start',
                    controller: _startFrameController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      setState(() {});
                      _onInputChanged();
                    },
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: EditorLabeledField(
                  label: 'End Frame',
                  child: CDKFieldText(
                    placeholder: 'End',
                    controller: _endFrameController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      setState(() {});
                      _onInputChanged();
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: EditorLabeledField(
                  label: 'FPS',
                  child: CDKFieldNumeric(
                    value: _parseFps(_fpsController.text) ??
                        widget.initialData.fps,
                    min: 0.1,
                    max: 999.0,
                    increment: 0.5,
                    decimals: 1,
                    onTextChanged: _setFpsFromNumericValue,
                    onValueChanged: _setFpsFromNumericValue,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 74,
                    child: EditorLabeledField(
                      label: 'Loop',
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 39,
                          height: 24,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: CupertinoSwitch(
                              value: _loop,
                              onChanged: (bool value) {
                                setState(() {
                                  _loop = value;
                                });
                                _onInputChanged();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (widget.showGroupSelector && widget.groupOptions.isNotEmpty) ...[
            SizedBox(height: spacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 240,
                child: EditorLabeledField(
                  label: widget.groupFieldLabel,
                  child: CDKButtonSelect(
                    selectedIndex: widget.groupOptions
                        .indexWhere((group) => group.id == _selectedGroupId)
                        .clamp(0, widget.groupOptions.length - 1),
                    options: widget.groupOptions
                        .map((group) => group.name.trim().isEmpty
                            ? GameListGroup.defaultMainName
                            : group.name)
                        .toList(growable: false),
                    onSelected: (int index) {
                      setState(() {
                        _selectedGroupId = widget.groupOptions[index].id;
                      });
                      _onInputChanged();
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimationFramePreviewPainter extends CustomPainter {
  const _AnimationFramePreviewPainter({
    required this.image,
    required this.frameWidth,
    required this.frameHeight,
    required this.columns,
    required this.frameIndex,
  });

  final ui.Image image;
  final double frameWidth;
  final double frameHeight;
  final int columns;
  final int frameIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgA = Paint()..color = const Color(0xFFE7E7E7);
    final Paint bgB = Paint()..color = const Color(0xFFD7D7D7);
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

    if (frameWidth <= 0 || frameHeight <= 0 || columns <= 0) {
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

    final Rect dst = _animationPreviewFrameRect(
      size: size,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
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
        ..color = const Color(0x66007AFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _AnimationFramePreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.columns != columns ||
        oldDelegate.frameIndex != frameIndex;
  }
}

Rect _animationPreviewFrameRect({
  required Size size,
  required double frameWidth,
  required double frameHeight,
}) {
  final double scale =
      math.min(size.width / frameWidth, size.height / frameHeight);
  final double drawWidth = frameWidth * scale;
  final double drawHeight = frameHeight * scale;
  return Rect.fromLTWH(
    (size.width - drawWidth) / 2,
    (size.height - drawHeight) / 2,
    drawWidth,
    drawHeight,
  );
}
