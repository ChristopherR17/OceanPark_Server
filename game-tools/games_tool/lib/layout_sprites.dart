import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_animation.dart';
import 'game_level.dart';
import 'game_list_group.dart';
import 'game_media_asset.dart';
import 'game_sprite.dart';
import 'widgets/edit_session.dart';
import 'widgets/editor_entity_form_mode.dart';
import 'widgets/editor_form_dialog_scaffold.dart';
import 'widgets/editor_header_delete_button.dart';
import 'widgets/editor_labeled_field.dart';
import 'widgets/editor_live_edit_session.dart';
import 'widgets/grouped_list.dart';
import 'widgets/section_help_button.dart';

class LayoutSprites extends StatefulWidget {
  const LayoutSprites({super.key});

  @override
  LayoutSpritesState createState() => LayoutSpritesState();
}

class LayoutSpritesState extends State<LayoutSprites> {
  final ScrollController scrollController = ScrollController();
  final GlobalKey _addGroupAnchorKey = GlobalKey();
  final Map<String, GlobalKey> _groupActionsAnchorKeys = <String, GlobalKey>{};
  int _newGroupCounter = 0;
  String _inlineEditUndoGroupKey = '';
  int _inlineEditUndoSpriteIndex = -1;

  Future<void> _autoSaveIfPossible(AppData appData) async {
    if (appData.selectedProject == null) {
      return;
    }
    appData.queueAutosave();
  }

  void updateForm(AppData appData) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  bool _isMultiSelectModifierPressed() {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final Set<LogicalKeyboardKey> pressed = keyboard.logicalKeysPressed;
    return keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        pressed.contains(LogicalKeyboardKey.meta) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.superKey) ||
        pressed.contains(LogicalKeyboardKey.alt) ||
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight) ||
        pressed.contains(LogicalKeyboardKey.control) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
  }

  int _firstSelectedIndex(Set<int> selection) {
    if (selection.isEmpty) {
      return -1;
    }
    final List<int> sorted = selection.toList()..sort();
    return sorted.first;
  }

  List<GameListGroup> _spriteGroups(GameLevel level) {
    if (level.spriteGroups.isEmpty) {
      return <GameListGroup>[GameListGroup.main()];
    }
    final bool hasMain =
        level.spriteGroups.any((group) => group.id == GameListGroup.mainId);
    if (hasMain) {
      return level.spriteGroups;
    }
    return <GameListGroup>[GameListGroup.main(), ...level.spriteGroups];
  }

  void _ensureMainSpriteGroup(GameLevel level) {
    final int mainIndex = level.spriteGroups
        .indexWhere((group) => group.id == GameListGroup.mainId);
    if (mainIndex == -1) {
      level.spriteGroups.insert(0, GameListGroup.main());
      return;
    }
    final GameListGroup mainGroup = level.spriteGroups[mainIndex];
    final String normalizedName = mainGroup.name.trim().isEmpty
        ? GameListGroup.defaultMainName
        : mainGroup.name.trim();
    if (mainGroup.name != normalizedName) {
      mainGroup.name = normalizedName;
    }
  }

  Set<String> _spriteGroupIds(GameLevel level) {
    return _spriteGroups(level).map((group) => group.id).toSet();
  }

  String _effectiveSpriteGroupId(GameLevel level, GameSprite sprite) {
    final String groupId = sprite.groupId.trim();
    if (groupId.isNotEmpty && _spriteGroupIds(level).contains(groupId)) {
      return groupId;
    }
    return GameListGroup.mainId;
  }

  GameListGroup? _findSpriteGroupById(GameLevel level, String groupId) {
    for (final group in _spriteGroups(level)) {
      if (group.id == groupId) {
        return group;
      }
    }
    return null;
  }

  List<GroupedListRow<GameListGroup, GameSprite>> _buildSpriteRows(
      GameLevel level) {
    return GroupedListAlgorithms.buildRows<GameListGroup, GameSprite>(
      groups: _spriteGroups(level),
      items: level.sprites,
      mainGroupId: GameListGroup.mainId,
      groupIdOf: (group) => group.id,
      groupCollapsedOf: (group) => group.collapsed,
      itemGroupIdOf: (sprite) => _effectiveSpriteGroupId(level, sprite),
    );
  }

  GlobalKey _groupActionsAnchorKey(String groupId) {
    return _groupActionsAnchorKeys.putIfAbsent(groupId, GlobalKey.new);
  }

  Set<String> _spriteGroupNames(
    GameLevel level, {
    String? excludingId,
  }) {
    return _spriteGroups(level)
        .where((group) => group.id != excludingId)
        .map((group) => group.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  String _newGroupId() {
    return '__group_${DateTime.now().microsecondsSinceEpoch}_${_newGroupCounter++}';
  }

  Future<bool> _upsertSpriteGroup(
      AppData appData, GroupedListGroupDraft draft) async {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }

    final String nextName = draft.name.trim();
    if (nextName.isEmpty) {
      return false;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    if (_spriteGroupNames(level, excludingId: draft.id)
        .contains(nextName.toLowerCase())) {
      return false;
    }

    await appData.runProjectMutation(
      debugLabel: 'sprite-group-upsert',
      mutate: () {
        final GameLevel level = appData.gameData.levels[appData.selectedLevel];
        _ensureMainSpriteGroup(level);
        final List<GameListGroup> groups = level.spriteGroups;
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

  Future<bool> _confirmAndDeleteSpriteGroup(
      AppData appData, String groupId) async {
    if (!mounted ||
        appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    if (groupId == GameListGroup.mainId) {
      return false;
    }

    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final GameListGroup? group = _findSpriteGroupById(level, groupId);
    if (group == null) {
      return false;
    }

    final int spritesInGroup = level.sprites
        .where((sprite) => _effectiveSpriteGroupId(level, sprite) == groupId)
        .length;

    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete group',
      message: spritesInGroup > 0
          ? 'Delete "${group.name}"? $spritesInGroup sprite(s) will be moved to "Main".'
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
      debugLabel: 'sprite-group-delete',
      mutate: () {
        final GameLevel level = appData.gameData.levels[appData.selectedLevel];
        _ensureMainSpriteGroup(level);
        final List<GameListGroup> groups = level.spriteGroups;
        final List<GameSprite> sprites = level.sprites;
        final int groupIndex = groups.indexWhere((g) => g.id == groupId);
        if (groupIndex == -1) {
          return;
        }
        GroupedListAlgorithms.reassignItemsToGroup<GameSprite>(
          items: sprites,
          fromGroupId: groupId,
          toGroupId: GameListGroup.mainId,
          itemGroupIdOf: (sprite) => sprite.groupId,
          setItemGroupId: (sprite, nextGroupId) {
            sprite.groupId = nextGroupId;
          },
        );
        groups.removeAt(groupIndex);
      },
    );

    return true;
  }

  Future<void> _showAddGroupPopover(AppData appData) async {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length ||
        Overlay.maybeOf(context) == null) {
      return;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final CDKDialogController controller = CDKDialogController();
    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _addGroupAnchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: GroupedListAddGroupPopover(
        title: 'Add Sprite Group',
        existingNames: _spriteGroups(level).map((group) => group.name),
        onCancel: controller.close,
        onAdd: (name) async {
          final bool added = await _upsertSpriteGroup(
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
    GameLevel level,
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
        existingNames: _spriteGroups(level)
            .where((candidate) => candidate.id != group.id)
            .map((candidate) => candidate.name),
        onCancel: controller.close,
        onRename: (name) async {
          final bool renamed = await _upsertSpriteGroup(
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
                    await _confirmAndDeleteSpriteGroup(appData, group.id);
                if (deleted) {
                  controller.close();
                }
                return deleted;
              },
      ),
    );
  }

  List<GameAnimation> _animations(AppData appData) {
    return appData.gameData.animations;
  }

  GameAnimation? _animationById(AppData appData, String animationId) {
    return appData.animationById(animationId);
  }

  GameAnimation? _defaultAnimation(
      AppData appData, List<GameAnimation> animations) {
    if (animations.isEmpty) {
      return null;
    }
    if (appData.selectedAnimation >= 0 &&
        appData.selectedAnimation < animations.length) {
      return animations[appData.selectedAnimation];
    }
    return animations.first;
  }

  _SpriteDialogData _dialogDataFromAnimation({
    required String name,
    required int x,
    required int y,
    required GameAnimation animation,
    required AppData appData,
    String gameplayData = '',
    String groupId = GameListGroup.mainId,
    bool flipX = false,
    bool flipY = false,
    double depth = 0.0,
  }) {
    final GameMediaAsset? media =
        appData.mediaAssetByFileName(animation.mediaFile);
    return _SpriteDialogData(
      name: name,
      gameplayData: gameplayData,
      x: x,
      y: y,
      depth: depth,
      animationId: animation.id,
      width: media?.tileWidth ?? 32,
      height: media?.tileHeight ?? 32,
      imageFile: animation.mediaFile,
      flipX: flipX,
      flipY: flipY,
      groupId: groupId,
    );
  }

  _SpriteDialogData _dialogDataFromSprite({
    required AppData appData,
    required GameSprite sprite,
    required List<GameAnimation> animations,
  }) {
    GameAnimation? animation = _animationById(appData, sprite.animationId);
    animation ??= animations.isEmpty
        ? null
        : animations.firstWhere(
            (candidate) => candidate.mediaFile == sprite.imageFile,
            orElse: () => animations.first,
          );

    if (animation != null) {
      return _dialogDataFromAnimation(
        name: sprite.name,
        gameplayData: sprite.gameplayData,
        x: sprite.x,
        y: sprite.y,
        animation: animation,
        appData: appData,
        groupId: sprite.groupId,
        flipX: sprite.flipX,
        flipY: sprite.flipY,
        depth: sprite.depth,
      );
    }

    return _SpriteDialogData(
      name: sprite.name,
      gameplayData: sprite.gameplayData,
      x: sprite.x,
      y: sprite.y,
      depth: sprite.depth,
      animationId: sprite.animationId,
      width: sprite.spriteWidth,
      height: sprite.spriteHeight,
      imageFile: sprite.imageFile,
      flipX: sprite.flipX,
      flipY: sprite.flipY,
      groupId: sprite.groupId,
    );
  }

  void _addSprite({
    required AppData appData,
    required _SpriteDialogData data,
  }) {
    if (appData.selectedLevel == -1) {
      return;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    _ensureMainSpriteGroup(level);
    final Set<String> validGroupIds = _spriteGroupIds(level);
    final String targetGroupId = validGroupIds.contains(data.groupId)
        ? data.groupId
        : GameListGroup.mainId;
    level.sprites.add(
      GameSprite(
        name: data.name,
        gameplayData: data.gameplayData,
        animationId: data.animationId,
        x: data.x,
        y: data.y,
        depth: data.depth,
        spriteWidth: data.width,
        spriteHeight: data.height,
        imageFile: data.imageFile,
        flipX: data.flipX,
        flipY: data.flipY,
        groupId: targetGroupId,
      ),
    );
    appData.selectedSprite = -1;
    appData.selectedSpriteIndices = <int>{};
    appData.update();
  }

  void _updateSprite({
    required AppData appData,
    required int index,
    required _SpriteDialogData data,
  }) {
    if (appData.selectedLevel == -1) {
      return;
    }
    final sprites = appData.gameData.levels[appData.selectedLevel].sprites;
    if (index < 0 || index >= sprites.length) {
      return;
    }
    sprites[index] = GameSprite(
      name: data.name,
      gameplayData: data.gameplayData,
      animationId: data.animationId,
      x: data.x,
      y: data.y,
      depth: data.depth,
      spriteWidth: data.width,
      spriteHeight: data.height,
      imageFile: data.imageFile,
      flipX: data.flipX,
      flipY: data.flipY,
      groupId: sprites[index].groupId,
    );
    appData.selectedSprite = index;
    appData.selectedSpriteIndices = <int>{index};
  }

  Future<_SpriteDialogData?> _promptSpriteData({
    required String title,
    required EditorEntityFormMode mode,
    required _SpriteDialogData initialData,
    required List<GameAnimation> animations,
    List<GameListGroup> groupOptions = const <GameListGroup>[],
    bool showGroupSelector = false,
    String groupFieldLabel = 'Sprite Group',
    GlobalKey? anchorKey,
    bool useArrowedPopover = false,
    Future<void> Function(_SpriteDialogData value)? onLiveChanged,
    VoidCallback? onDelete,
  }) async {
    if (Overlay.maybeOf(context) == null) {
      return null;
    }

    final AppData appData = Provider.of<AppData>(context, listen: false);
    final CDKDialogController controller = CDKDialogController();
    final Completer<_SpriteDialogData?> completer =
        Completer<_SpriteDialogData?>();
    _SpriteDialogData? result;

    final dialogChild = _SpriteFormDialog(
      title: title,
      mode: mode,
      initialData: initialData,
      animations: animations,
      groupOptions: groupOptions,
      showGroupSelector: showGroupSelector,
      groupFieldLabel: groupFieldLabel,
      resolveMediaByFileName: appData.mediaAssetByFileName,
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

  Future<void> _promptAndAddSprite(List<GameAnimation> animations) async {
    final AppData appData = Provider.of<AppData>(context, listen: false);
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    appData.selectedSprite = -1;
    appData.selectedSpriteIndices = <int>{};
    appData.update();
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    _ensureMainSpriteGroup(level);
    final GameAnimation? defaultAnimation =
        _defaultAnimation(appData, animations);
    if (defaultAnimation == null) {
      return;
    }

    final _SpriteDialogData? data = await _promptSpriteData(
      title: 'New sprite',
      mode: EditorEntityFormMode.add,
      initialData: _dialogDataFromAnimation(
        name: '',
        x: 0,
        y: 0,
        animation: defaultAnimation,
        appData: appData,
        groupId: GameListGroup.mainId,
      ),
      animations: animations,
      groupOptions: _spriteGroups(level),
      showGroupSelector: true,
      groupFieldLabel: 'Sprite Group',
    );
    if (!mounted || data == null) {
      return;
    }

    appData.pushUndo();
    _addSprite(appData: appData, data: data);
    await _autoSaveIfPossible(appData);
  }

  Future<void> _deleteSprite(AppData appData, int index) async {
    if (appData.selectedLevel == -1) {
      return;
    }
    final sprites = appData.gameData.levels[appData.selectedLevel].sprites;
    if (index < 0 || index >= sprites.length) {
      return;
    }
    appData.pushUndo();
    sprites.removeAt(index);
    appData.selectedSprite = -1;
    appData.selectedSpriteIndices = <int>{};
    appData.update();
    await _autoSaveIfPossible(appData);
  }

  Future<bool> confirmAndDeleteSelectedSpriteFromKeyboard(
    AppData appData,
  ) async {
    if (appData.selectedLevel == -1 || !mounted) {
      return false;
    }
    final List<GameSprite> sprites =
        appData.gameData.levels[appData.selectedLevel].sprites;
    final int spriteCount = sprites.length;
    if (spriteCount <= 0) {
      return false;
    }
    final Set<int> selected = appData.selectedSpriteIndices
        .where((index) => index >= 0 && index < spriteCount)
        .toSet();
    if (selected.isEmpty &&
        appData.selectedSprite >= 0 &&
        appData.selectedSprite < spriteCount) {
      selected.add(appData.selectedSprite);
    }
    if (selected.isEmpty) {
      return false;
    }
    final bool isSingle = selected.length == 1;
    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: isSingle ? 'Delete sprite' : 'Delete sprites',
      message: isSingle
          ? 'Delete this sprite? This cannot be undone.'
          : 'Delete ${selected.length} selected sprites? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    await appData.runProjectMutation(
      debugLabel: 'sprite-delete-selected',
      mutate: () {
        final List<GameSprite> currentSprites =
            appData.gameData.levels[appData.selectedLevel].sprites;
        final List<int> indices = selected.toList(growable: false)
          ..sort((a, b) => b.compareTo(a));
        for (final index in indices) {
          if (index >= 0 && index < currentSprites.length) {
            currentSprites.removeAt(index);
          }
        }
        appData.selectedSprite = -1;
        appData.selectedSpriteIndices = <int>{};
      },
    );
    await _autoSaveIfPossible(appData);
    return true;
  }

  int _inlineSelectedSpriteIndex(AppData appData) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return -1;
    }
    final int spriteCount =
        appData.gameData.levels[appData.selectedLevel].sprites.length;
    if (spriteCount <= 0) {
      return -1;
    }
    if (appData.selectedSprite >= 0 && appData.selectedSprite < spriteCount) {
      return appData.selectedSprite;
    }
    final Set<int> selected = appData.selectedSpriteIndices
        .where((index) => index >= 0 && index < spriteCount)
        .toSet();
    if (selected.length != 1) {
      return -1;
    }
    return selected.first;
  }

  String _inlineUndoGroupKeyForSprite(int index) {
    if (_inlineEditUndoGroupKey.isNotEmpty &&
        _inlineEditUndoSpriteIndex == index) {
      return _inlineEditUndoGroupKey;
    }
    _inlineEditUndoSpriteIndex = index;
    _inlineEditUndoGroupKey =
        'sprite-inline-$index-${DateTime.now().microsecondsSinceEpoch}';
    return _inlineEditUndoGroupKey;
  }

  Future<void> _applySpriteChange(
    AppData appData, {
    required int index,
    required _SpriteDialogData value,
    required bool groupedUndo,
  }) async {
    await appData.runProjectMutation(
      debugLabel:
          groupedUndo ? 'sprite-inline-live-edit' : 'sprite-inline-edit',
      undoGroupKey: groupedUndo ? _inlineUndoGroupKeyForSprite(index) : null,
      mutate: () {
        _updateSprite(appData: appData, index: index, data: value);
      },
    );
  }

  Widget buildEditToolbarContent(AppData appData) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return const SizedBox.shrink();
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final int index = _inlineSelectedSpriteIndex(appData);
    if (index < 0 || index >= level.sprites.length) {
      return const SizedBox.shrink();
    }
    final List<GameAnimation> animations = _animations(appData);
    final GameSprite sprite = level.sprites[index];
    return _SpriteFormDialog(
      key: ValueKey('sprite-inline-editor-$index'),
      title: 'Edit sprite',
      mode: EditorEntityFormMode.edit,
      initialData: _dialogDataFromSprite(
        appData: appData,
        sprite: sprite,
        animations: animations,
      ),
      animations: animations,
      groupOptions: _spriteGroups(level),
      showGroupSelector: false,
      groupFieldLabel: 'Sprite Group',
      resolveMediaByFileName: appData.mediaAssetByFileName,
      minWidth: 280,
      maxWidth: 340,
      onLiveChanged: (value) async {
        await _applySpriteChange(
          appData,
          index: index,
          value: value,
          groupedUndo: true,
        );
      },
      onConfirm: (value) {
        unawaited(
          _applySpriteChange(
            appData,
            index: index,
            value: value,
            groupedUndo: false,
          ),
        );
      },
      onCancel: () {
        _selectSprite(appData, index, true);
      },
      onDelete: () {
        unawaited(_deleteSprite(appData, index));
      },
    );
  }

  void _selectSprite(
    AppData appData,
    int index,
    bool isSelected, {
    bool additive = false,
  }) {
    if (additive &&
        appData.selectedLevel >= 0 &&
        appData.selectedLevel < appData.gameData.levels.length) {
      final int spriteCount =
          appData.gameData.levels[appData.selectedLevel].sprites.length;
      final Set<int> nextSelection = appData.selectedSpriteIndices
          .where((value) => value >= 0 && value < spriteCount)
          .toSet();
      final int currentPrimary = appData.selectedSprite;
      if (currentPrimary >= 0 && currentPrimary < spriteCount) {
        nextSelection.add(currentPrimary);
      }
      final bool removed = nextSelection.remove(index);
      if (!removed) {
        nextSelection.add(index);
      }
      final int nextPrimary;
      if (nextSelection.isEmpty) {
        nextPrimary = -1;
      } else if (!removed) {
        nextPrimary = index;
      } else if (currentPrimary >= 0 &&
          nextSelection.contains(currentPrimary)) {
        nextPrimary = currentPrimary;
      } else {
        nextPrimary = _firstSelectedIndex(nextSelection);
      }
      appData.selectedSprite = nextPrimary;
      appData.selectedSpriteIndices = nextSelection;
      appData.update();
      return;
    }
    if (isSelected) {
      appData.selectedSprite = -1;
      appData.selectedSpriteIndices = <int>{};
      appData.update();
      return;
    }
    appData.selectedSprite = index;
    appData.selectedSpriteIndices = <int>{index};
    appData.update();
  }

  void selectSprite(AppData appData, int index, bool isSelected) {
    _selectSprite(appData, index, isSelected);
  }

  Future<void> _toggleGroupCollapsed(AppData appData, String groupId) async {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    await appData.runProjectMutation(
      debugLabel: 'sprite-group-toggle-collapse',
      mutate: () {
        final GameLevel level = appData.gameData.levels[appData.selectedLevel];
        _ensureMainSpriteGroup(level);
        final int index =
            level.spriteGroups.indexWhere((group) => group.id == groupId);
        if (index == -1) {
          return;
        }
        final GameListGroup group = level.spriteGroups[index];
        group.collapsed = !group.collapsed;
        if (group.collapsed &&
            appData.selectedSprite >= 0 &&
            appData.selectedSprite < level.sprites.length &&
            _effectiveSpriteGroupId(
                  level,
                  level.sprites[appData.selectedSprite],
                ) ==
                group.id) {
          appData.selectedSprite = -1;
          appData.selectedSpriteIndices = <int>{};
        }
      },
    );
  }

  void _moveGroup({
    required GameLevel level,
    required List<GroupedListRow<GameListGroup, GameSprite>>
        rowsWithoutMovedItem,
    required GroupedListRow<GameListGroup, GameSprite> movedRow,
    required int targetRowIndex,
  }) {
    GroupedListAlgorithms.moveGroup<GameListGroup, GameSprite>(
      groups: level.spriteGroups,
      rowsWithoutMovedItem: rowsWithoutMovedItem,
      movedRow: movedRow,
      targetRowIndex: targetRowIndex,
      groupIdOf: (group) => group.id,
    );
  }

  void _moveSprite({
    required AppData appData,
    required GameLevel level,
    required List<GroupedListRow<GameListGroup, GameSprite>>
        rowsWithoutMovedItem,
    required GroupedListRow<GameListGroup, GameSprite> movedRow,
    required int targetRowIndex,
  }) {
    final List<GameSprite> sprites = level.sprites;
    appData.selectedSprite = GroupedListAlgorithms
        .moveItemAndReturnSelectedIndex<GameListGroup, GameSprite>(
      groups: level.spriteGroups,
      items: sprites,
      rowsWithoutMovedItem: rowsWithoutMovedItem,
      movedRow: movedRow,
      targetRowIndex: targetRowIndex,
      mainGroupId: GameListGroup.mainId,
      groupIdOf: (group) => group.id,
      effectiveGroupIdOfItem: (sprite) =>
          _effectiveSpriteGroupId(level, sprite),
      setItemGroupId: (sprite, groupId) {
        sprite.groupId = groupId;
      },
      selectedIndex: appData.selectedSprite,
    );
    appData.selectedSpriteIndices =
        appData.selectedSprite >= 0 ? <int>{appData.selectedSprite} : <int>{};
  }

  void _onReorder(
    AppData appData,
    List<GroupedListRow<GameListGroup, GameSprite>> rows,
    int oldIndex,
    int newIndex,
  ) {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    if (rows.isEmpty || oldIndex < 0 || oldIndex >= rows.length) {
      return;
    }

    final int targetIndex = GroupedListAlgorithms.normalizeTargetIndex(
      oldIndex: oldIndex,
      newIndex: newIndex,
      rowCount: rows.length,
    );

    final List<GroupedListRow<GameListGroup, GameSprite>> rowsWithoutMovedItem =
        List<GroupedListRow<GameListGroup, GameSprite>>.from(rows);
    final GroupedListRow<GameListGroup, GameSprite> movedRow =
        rowsWithoutMovedItem.removeAt(oldIndex);
    int boundedTargetIndex = targetIndex;
    if (boundedTargetIndex > rowsWithoutMovedItem.length) {
      boundedTargetIndex = rowsWithoutMovedItem.length;
    }

    appData.pushUndo();
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    _ensureMainSpriteGroup(level);
    if (movedRow.isGroup) {
      _moveGroup(
        level: level,
        rowsWithoutMovedItem: rowsWithoutMovedItem,
        movedRow: movedRow,
        targetRowIndex: boundedTargetIndex,
      );
    } else {
      _moveSprite(
        appData: appData,
        level: level,
        rowsWithoutMovedItem: rowsWithoutMovedItem,
        movedRow: movedRow,
        targetRowIndex: boundedTargetIndex,
      );
    }

    appData.update();
    unawaited(_autoSaveIfPossible(appData));
  }

  @override
  Widget build(BuildContext context) {
    final appData = Provider.of<AppData>(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
    final TextStyle sectionTitleStyle = typography.title.copyWith(
      fontSize: (typography.title.fontSize ?? 17) + 2,
    );
    final TextStyle listItemTitleStyle = typography.body.copyWith(
      fontSize: (typography.body.fontSize ?? 14) + 2,
      fontWeight: FontWeight.w700,
    );

    final bool hasLevel = appData.selectedLevel >= 0 &&
        appData.selectedLevel < appData.gameData.levels.length;
    if (!hasLevel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Row(
              children: [
                CDKText(
                  'Level Sprites',
                  role: CDKTextRole.title,
                  style: sectionTitleStyle,
                ),
                const SizedBox(width: 6),
                const SectionHelpButton(
                  message:
                      'Sprites are game objects that combine animations and properties. They represent characters, items, or any animated entity placed in a level.',
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: CDKText(
                  'No level selected.\nSelect a Level to edit its sprites.',
                  role: CDKTextRole.body,
                  color: cdkColors.colorText.withValues(alpha: 0.62),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final level = appData.gameData.levels[appData.selectedLevel];
    final sprites = level.sprites;
    final spriteRows = _buildSpriteRows(level);
    final Set<int> multiSelectedSpriteIndices = appData.selectedSpriteIndices
        .where((index) => index >= 0 && index < level.sprites.length)
        .toSet();
    final List<GameAnimation> animations = _animations(appData);
    final bool hasAnimations = animations.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              CDKText(
                'Level Sprites',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'Sprites are game objects that combine animations and properties. They represent characters, items, or any animated entity placed in a level.',
              ),
              const Spacer(),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: hasAnimations
                    ? () async {
                        await _promptAndAddSprite(animations);
                      }
                    : null,
                child: const Text('+ Sprite'),
              ),
              const SizedBox(width: 8),
              CDKButton(
                key: _addGroupAnchorKey,
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
        if (sprites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CDKText(
              hasAnimations
                  ? '(No sprites defined)'
                  : 'Define at least one animation first.',
              role: CDKTextRole.caption,
              secondary: true,
            ),
          ),
        Expanded(
          child: CupertinoScrollbar(
            controller: scrollController,
            child: Localizations.override(
              context: context,
              delegates: [
                DefaultMaterialLocalizations.delegate,
                DefaultWidgetsLocalizations.delegate,
              ],
              child: ReorderableListView.builder(
                scrollController: scrollController,
                buildDefaultDragHandles: false,
                itemCount: spriteRows.length,
                onReorder: (oldIndex, newIndex) =>
                    _onReorder(appData, spriteRows, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final GroupedListRow<GameListGroup, GameSprite> row =
                      spriteRows[index];
                  if (row.isGroup) {
                    final GameListGroup group = row.group!;
                    final GlobalKey groupActionsAnchorKey =
                        _groupActionsAnchorKey(group.id);
                    return Container(
                      key: ValueKey('sprite-group-${group.id}'),
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
                          CupertinoButton(
                            key: groupActionsAnchorKey,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                            ),
                            minimumSize: const Size(20, 20),
                            onPressed: () async {
                              await _showGroupActionsPopover(
                                appData,
                                level,
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
                    );
                  }

                  final int spriteIndex = row.itemIndex!;
                  final bool isSelected =
                      multiSelectedSpriteIndices.contains(spriteIndex) ||
                          spriteIndex == appData.selectedSprite;
                  final GameSprite sprite = row.item!;
                  final String animationName =
                      appData.animationDisplayNameById(sprite.animationId);
                  final String subtitle =
                      'Depth ${sprite.depth} - $animationName';
                  final bool hiddenByCollapse = row.hiddenByCollapse;
                  return AnimatedSize(
                    key: ValueKey('sprite-item-$spriteIndex'),
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
                            onTap: () => _selectSprite(
                              appData,
                              spriteIndex,
                              isSelected,
                              additive: _isMultiSelectModifierPressed(),
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
                                        RichText(
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          strutStyle: StrutStyle.fromTextStyle(
                                            listItemTitleStyle,
                                            forceStrutHeight: true,
                                          ),
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: sprite.name,
                                                style:
                                                    listItemTitleStyle.copyWith(
                                                  color: cdkColors.colorText,
                                                ),
                                              ),
                                            ],
                                          ),
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

class _SpriteDialogData {
  const _SpriteDialogData({
    required this.name,
    required this.gameplayData,
    required this.x,
    required this.y,
    required this.depth,
    required this.animationId,
    required this.width,
    required this.height,
    required this.imageFile,
    required this.flipX,
    required this.flipY,
    required this.groupId,
  });

  final String name;
  final String gameplayData;
  final int x;
  final int y;
  final double depth;
  final String animationId;
  final int width;
  final int height;
  final String imageFile;
  final bool flipX;
  final bool flipY;
  final String groupId;
}

class _SpriteFormDialog extends StatefulWidget {
  const _SpriteFormDialog({
    super.key,
    required this.title,
    required this.mode,
    required this.initialData,
    required this.animations,
    required this.groupOptions,
    required this.showGroupSelector,
    required this.groupFieldLabel,
    required this.resolveMediaByFileName,
    this.onLiveChanged,
    this.onClose,
    this.minWidth = 380,
    this.maxWidth = 500,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
  });

  final String title;
  final EditorEntityFormMode mode;
  final _SpriteDialogData initialData;
  final List<GameAnimation> animations;
  final List<GameListGroup> groupOptions;
  final bool showGroupSelector;
  final String groupFieldLabel;
  final GameMediaAsset? Function(String fileName) resolveMediaByFileName;
  final Future<void> Function(_SpriteDialogData value)? onLiveChanged;
  final VoidCallback? onClose;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<_SpriteDialogData> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  State<_SpriteFormDialog> createState() => _SpriteFormDialogState();
}

class _SpriteFormDialogState extends State<_SpriteFormDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialData.name,
  );
  late final TextEditingController _gameplayDataController =
      TextEditingController(
    text: widget.initialData.gameplayData,
  );
  late final TextEditingController _xController = TextEditingController(
    text: widget.initialData.x.toString(),
  );
  late final TextEditingController _yController = TextEditingController(
    text: widget.initialData.y.toString(),
  );
  late final TextEditingController _depthController = TextEditingController(
    text: widget.initialData.depth.toString(),
  );
  late int _selectedAnimationIndex = _resolveInitialAnimationIndex();
  late String _selectedGroupId = _resolveInitialGroupId();
  late bool _flipX = widget.initialData.flipX;
  late bool _flipY = widget.initialData.flipY;
  EditSession<_SpriteDialogData>? _editSession;

  bool _didInitialDataChange(
      _SpriteDialogData previous, _SpriteDialogData next) {
    return previous.name != next.name ||
        previous.gameplayData != next.gameplayData ||
        previous.x != next.x ||
        previous.y != next.y ||
        previous.depth != next.depth ||
        previous.animationId != next.animationId ||
        previous.width != next.width ||
        previous.height != next.height ||
        previous.imageFile != next.imageFile ||
        previous.flipX != next.flipX ||
        previous.flipY != next.flipY ||
        previous.groupId != next.groupId;
  }

  void _setControllerTextIfNeeded(
      TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  int _resolveInitialAnimationIndex() {
    final String currentAnimationId = widget.initialData.animationId;
    if (currentAnimationId.isNotEmpty) {
      final int found =
          widget.animations.indexWhere((a) => a.id == currentAnimationId);
      if (found != -1) {
        return found;
      }
    }
    final String currentImageFile = widget.initialData.imageFile;
    if (currentImageFile.isNotEmpty) {
      final int found =
          widget.animations.indexWhere((a) => a.mediaFile == currentImageFile);
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

  GameAnimation? get _selectedAnimation {
    if (widget.animations.isEmpty) {
      return null;
    }
    if (_selectedAnimationIndex < 0 ||
        _selectedAnimationIndex >= widget.animations.length) {
      _selectedAnimationIndex = 0;
    }
    return widget.animations[_selectedAnimationIndex];
  }

  GameMediaAsset? get _selectedMedia {
    final GameAnimation? animation = _selectedAnimation;
    if (animation == null) {
      return null;
    }
    return widget.resolveMediaByFileName(animation.mediaFile);
  }

  bool get _isValid {
    return _nameController.text.trim().isNotEmpty && _selectedAnimation != null;
  }

  double _parseDepth() {
    final String cleaned = _depthController.text.trim().replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0.0;
  }

  _SpriteDialogData _currentData() {
    final GameAnimation? animation = _selectedAnimation;
    final GameMediaAsset? media = _selectedMedia;
    return _SpriteDialogData(
      name: _nameController.text.trim(),
      gameplayData: _gameplayDataController.text,
      x: int.tryParse(_xController.text.trim()) ?? 0,
      y: int.tryParse(_yController.text.trim()) ?? 0,
      depth: _parseDepth(),
      animationId: animation?.id ?? widget.initialData.animationId,
      width: media?.tileWidth ?? widget.initialData.width,
      height: media?.tileHeight ?? widget.initialData.height,
      imageFile: animation?.mediaFile ?? widget.initialData.imageFile,
      flipX: _flipX,
      flipY: _flipY,
      groupId: _selectedGroupId,
    );
  }

  String? _validateData(_SpriteDialogData value) {
    if (value.name.trim().isEmpty) {
      return 'Sprite name is required.';
    }
    if (_selectedAnimation == null) {
      return 'Define at least one animation first.';
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
    _editSession = createEditorLiveEditSession<_SpriteDialogData>(
      mode: widget.mode,
      initialValue: _currentData(),
      validate: _validateData,
      onPersist: widget.onLiveChanged,
      areEqual: (a, b) =>
          a.name == b.name &&
          a.gameplayData == b.gameplayData &&
          a.x == b.x &&
          a.y == b.y &&
          a.depth == b.depth &&
          a.animationId == b.animationId &&
          a.width == b.width &&
          a.height == b.height &&
          a.imageFile == b.imageFile &&
          a.flipX == b.flipX &&
          a.flipY == b.flipY &&
          a.groupId == b.groupId,
    );
  }

  @override
  void didUpdateWidget(covariant _SpriteFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool initialDataChanged =
        _didInitialDataChange(oldWidget.initialData, widget.initialData);
    bool shouldRebuild = false;

    if (initialDataChanged) {
      _setControllerTextIfNeeded(_nameController, widget.initialData.name);
      _setControllerTextIfNeeded(
        _gameplayDataController,
        widget.initialData.gameplayData,
      );
      _setControllerTextIfNeeded(_xController, widget.initialData.x.toString());
      _setControllerTextIfNeeded(_yController, widget.initialData.y.toString());
      _setControllerTextIfNeeded(
        _depthController,
        widget.initialData.depth.toString(),
      );
      if (_flipX != widget.initialData.flipX) {
        _flipX = widget.initialData.flipX;
        shouldRebuild = true;
      }
      if (_flipY != widget.initialData.flipY) {
        _flipY = widget.initialData.flipY;
        shouldRebuild = true;
      }
    }

    if (initialDataChanged ||
        _selectedAnimationIndex >= widget.animations.length) {
      final int nextAnimationIndex = _resolveInitialAnimationIndex();
      if (_selectedAnimationIndex != nextAnimationIndex) {
        _selectedAnimationIndex = nextAnimationIndex;
        shouldRebuild = true;
      }
    }

    if (initialDataChanged ||
        !widget.groupOptions.any((group) => group.id == _selectedGroupId)) {
      final String nextGroupId = _resolveInitialGroupId();
      if (_selectedGroupId != nextGroupId) {
        _selectedGroupId = nextGroupId;
        shouldRebuild = true;
      }
    }

    if (shouldRebuild && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (_editSession != null) {
      unawaited(_editSession!.flush());
      _editSession!.dispose();
    }
    _nameController.dispose();
    _gameplayDataController.dispose();
    _xController.dispose();
    _yController.dispose();
    _depthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final GameMediaAsset? media = _selectedMedia;
    final List<String> animationOptions = widget.animations
        .map((a) => a.name.trim().isNotEmpty ? a.name : a.id)
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
              title: 'Delete sprite',
              message: 'Delete this sprite? This cannot be undone.',
            ),
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabeledField(
            label: 'Sprite Name',
            child: CDKFieldText(
              placeholder: 'Sprite name',
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
          Row(
            children: [
              Expanded(
                child: EditorLabeledField(
                  label: 'Start X (px)',
                  child: CDKFieldText(
                    placeholder: 'Start X (px)',
                    controller: _xController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _onInputChanged(),
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: EditorLabeledField(
                  label: 'Start Y (px)',
                  child: CDKFieldText(
                    placeholder: 'Start Y (px)',
                    controller: _yController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _onInputChanged(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EditorLabeledField(
                  label: 'Depth displacement',
                  child: CDKFieldText(
                    placeholder: 'Depth',
                    controller: _depthController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => _onInputChanged(),
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: EditorLabeledField(
                        label: 'Flip X',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 39,
                            height: 24,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: CupertinoSwitch(
                                value: _flipX,
                                onChanged: (bool value) {
                                  setState(() {
                                    _flipX = value;
                                  });
                                  _onInputChanged();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: EditorLabeledField(
                        label: 'Flip Y',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 39,
                            height: 24,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: CupertinoSwitch(
                                value: _flipY,
                                onChanged: (bool value) {
                                  setState(() {
                                    _flipY = value;
                                  });
                                  _onInputChanged();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          EditorLabeledField(
            label: 'Animation',
            child: Row(
              children: [
                if (animationOptions.isNotEmpty)
                  CDKButtonSelect(
                    selectedIndex: _selectedAnimationIndex,
                    options: animationOptions,
                    onSelected: (int index) {
                      setState(() {
                        _selectedAnimationIndex = index;
                      });
                      _onInputChanged();
                    },
                  )
                else
                  const Expanded(
                    child: CDKText(
                      'No animations available',
                      role: CDKTextRole.caption,
                      secondary: true,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: spacing.sm),
          EditorLabeledField(
            label: 'Frame size',
            child: CDKText(
              '${(media?.tileWidth ?? widget.initialData.width)}×${(media?.tileHeight ?? widget.initialData.height)} px',
              role: CDKTextRole.caption,
              color: cdkColors.colorText,
            ),
          ),
          SizedBox(height: spacing.md),
          if (widget.showGroupSelector && widget.groupOptions.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
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
                SizedBox(width: spacing.sm),
                Expanded(
                  child: EditorLabeledField(
                    label: 'Gameplay data',
                    child: CDKFieldText(
                      placeholder: 'Gameplay data',
                      controller: _gameplayDataController,
                      onChanged: (_) => _onInputChanged(),
                      onSubmitted: (_) {
                        if (widget.mode.isLiveEdit) {
                          _onInputChanged();
                          return;
                        }
                        _confirm();
                      },
                    ),
                  ),
                ),
              ],
            )
          else
            EditorLabeledField(
              label: 'Gameplay data',
              child: CDKFieldText(
                placeholder: 'Gameplay data',
                controller: _gameplayDataController,
                onChanged: (_) => _onInputChanged(),
                onSubmitted: (_) {
                  if (widget.mode.isLiveEdit) {
                    _onInputChanged();
                    return;
                  }
                  _confirm();
                },
              ),
            ),
        ],
      ),
    );
  }
}
