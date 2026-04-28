import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_list_group.dart';
import 'game_level.dart';
import 'widgets/edit_session.dart';
import 'widgets/editor_entity_form_mode.dart';
import 'widgets/editor_form_dialog_scaffold.dart';
import 'widgets/editor_header_delete_button.dart';
import 'widgets/editor_labeled_field.dart';
import 'widgets/editor_live_edit_session.dart';
import 'widgets/grouped_list.dart';
import 'widgets/section_help_button.dart';

const Color _defaultLevelBackgroundColor = Color(0xFFDCDCE1);

class LayoutLevels extends StatefulWidget {
  const LayoutLevels({super.key});

  @override
  LayoutLevelsState createState() => LayoutLevelsState();
}

class LayoutLevelsState extends State<LayoutLevels> {
  final ScrollController scrollController = ScrollController();
  final GlobalKey _addGroupAnchorKey = GlobalKey();
  final Map<String, GlobalKey> _groupActionsAnchorKeys = <String, GlobalKey>{};
  int _newGroupCounter = 0;
  String? _hoveredGroupId;
  String _inlineEditUndoGroupKey = '';
  int _inlineEditUndoLevelIndex = -1;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _autoSaveIfPossible(AppData appData) async {
    if (appData.selectedProject == null) {
      return;
    }
    appData.queueAutosave();
  }

  List<GameListGroup> _levelGroups(AppData appData) {
    if (appData.gameData.levelGroups.isEmpty) {
      return <GameListGroup>[GameListGroup.main()];
    }
    final bool hasMain = appData.gameData.levelGroups
        .any((group) => group.id == GameListGroup.mainId);
    if (hasMain) {
      return appData.gameData.levelGroups;
    }
    return <GameListGroup>[
      GameListGroup.main(),
      ...appData.gameData.levelGroups,
    ];
  }

  void _ensureMainLevelGroup(AppData appData) {
    final List<GameListGroup> groups = appData.gameData.levelGroups;
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

  Set<String> _levelGroupIds(AppData appData) {
    return _levelGroups(appData).map((group) => group.id).toSet();
  }

  String _effectiveLevelGroupId(AppData appData, GameLevel level) {
    final String groupId = level.groupId.trim();
    if (groupId.isNotEmpty && _levelGroupIds(appData).contains(groupId)) {
      return groupId;
    }
    return GameListGroup.mainId;
  }

  GameListGroup? _findLevelGroupById(AppData appData, String groupId) {
    for (final group in _levelGroups(appData)) {
      if (group.id == groupId) {
        return group;
      }
    }
    return null;
  }

  List<GroupedListRow<GameListGroup, GameLevel>> _buildLevelRows(
      AppData appData) {
    return GroupedListAlgorithms.buildRows<GameListGroup, GameLevel>(
      groups: _levelGroups(appData),
      items: appData.gameData.levels,
      mainGroupId: GameListGroup.mainId,
      groupIdOf: (group) => group.id,
      groupCollapsedOf: (group) => group.collapsed,
      itemGroupIdOf: (level) => _effectiveLevelGroupId(appData, level),
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

  Set<String> _levelGroupNames(
    AppData appData, {
    String? excludingId,
  }) {
    return _levelGroups(appData)
        .where((group) => group.id != excludingId)
        .map((group) => group.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  String _newGroupId() {
    return '__group_${DateTime.now().microsecondsSinceEpoch}_${_newGroupCounter++}';
  }

  Future<bool> _upsertLevelGroup(
      AppData appData, GroupedListGroupDraft draft) async {
    final String nextName = draft.name.trim();
    if (nextName.isEmpty) {
      return false;
    }
    if (_levelGroupNames(appData, excludingId: draft.id)
        .contains(nextName.toLowerCase())) {
      return false;
    }

    appData.pushUndo();
    _ensureMainLevelGroup(appData);
    final List<GameListGroup> groups = appData.gameData.levelGroups;
    final int existingIndex =
        groups.indexWhere((group) => group.id == draft.id);
    if (existingIndex != -1) {
      groups[existingIndex].name = nextName;
    } else {
      groups.add(
        GameListGroup(
          id: draft.id,
          name: nextName,
          collapsed: false,
        ),
      );
    }
    appData.update();
    await _autoSaveIfPossible(appData);
    return true;
  }

  Future<bool> _confirmAndDeleteLevelGroup(
      AppData appData, String groupId) async {
    if (!mounted) {
      return false;
    }
    if (groupId == GameListGroup.mainId) {
      return false;
    }

    final GameListGroup? group = _findLevelGroupById(appData, groupId);
    if (group == null) {
      return false;
    }
    final int levelsInGroup = appData.gameData.levels
        .where((level) => _effectiveLevelGroupId(appData, level) == groupId)
        .length;
    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete group',
      message: levelsInGroup > 0
          ? 'Delete "${group.name}"? $levelsInGroup level(s) will be moved to "Main".'
          : 'Delete "${group.name}"?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }

    appData.pushUndo();
    _ensureMainLevelGroup(appData);
    final List<GameListGroup> groups = appData.gameData.levelGroups;
    final List<GameLevel> levels = appData.gameData.levels;
    final int groupIndex = groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) {
      return false;
    }
    GroupedListAlgorithms.reassignItemsToGroup<GameLevel>(
      items: levels,
      fromGroupId: groupId,
      toGroupId: GameListGroup.mainId,
      itemGroupIdOf: (level) => level.groupId,
      setItemGroupId: (level, nextGroupId) {
        level.groupId = nextGroupId;
      },
    );
    groups.removeAt(groupIndex);

    appData.update();
    await _autoSaveIfPossible(appData);
    return true;
  }

  Future<void> _showAddGroupPopover(AppData appData) async {
    if (Overlay.maybeOf(context) == null) {
      return;
    }
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
        title: 'Add Level Group',
        existingNames: _levelGroups(appData).map((group) => group.name),
        onCancel: controller.close,
        onAdd: (name) async {
          final bool added = await _upsertLevelGroup(
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
        existingNames: _levelGroups(appData)
            .where((candidate) => candidate.id != group.id)
            .map((candidate) => candidate.name),
        onCancel: controller.close,
        onRename: (name) async {
          final bool renamed = await _upsertLevelGroup(
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
                    await _confirmAndDeleteLevelGroup(appData, group.id);
                if (deleted) {
                  controller.close();
                }
                return deleted;
              },
      ),
    );
  }

  void _addLevel({
    required AppData appData,
    required String name,
    required String description,
    required String gameplayData,
    required String backgroundColorHex,
    required double depthSensitivity,
    required String groupId,
  }) {
    _ensureMainLevelGroup(appData);
    final Set<String> validGroupIds = _levelGroupIds(appData);
    final String targetGroupId =
        validGroupIds.contains(groupId) ? groupId : GameListGroup.mainId;
    final newLevel = GameLevel(
      name: name,
      description: description,
      gameplayData: gameplayData,
      layers: [],
      zones: [],
      sprites: [],
      backgroundColorHex: backgroundColorHex,
      depthSensitivity: depthSensitivity,
      groupId: targetGroupId,
    );

    appData.gameData.levels.add(newLevel);
    appData.selectedLevel = -1;
    appData.update();
  }

  Future<_LevelDialogData?> _promptLevelData({
    required String title,
    required EditorEntityFormMode mode,
    String initialName = "",
    String initialDescription = "",
    String initialGameplayData = "",
    String initialBackgroundColorHex = "#DCDCE1",
    double initialDepthSensitivity = GameLevel.defaultDepthSensitivity,
    String initialGroupId = GameListGroup.mainId,
    int? editingIndex,
    bool showGroupSelector = false,
    String groupFieldLabel = "Level Group",
    GlobalKey? anchorKey,
    bool useArrowedPopover = false,
    Future<void> Function(_LevelDialogData value)? onLiveChanged,
    VoidCallback? onDelete,
  }) async {
    if (Overlay.maybeOf(context) == null) {
      return null;
    }

    final appData = Provider.of<AppData>(context, listen: false);
    final Set<String> existingNames = appData.gameData.levels
        .asMap()
        .entries
        .where((entry) => entry.key != editingIndex)
        .map((entry) => entry.value)
        .map((level) => level.name.trim().toLowerCase())
        .toSet();
    final CDKDialogController controller = CDKDialogController();
    final Completer<_LevelDialogData?> completer =
        Completer<_LevelDialogData?>();
    _LevelDialogData? result;

    final dialogChild = _LevelFormDialog(
      title: title,
      mode: mode,
      initialName: initialName,
      initialDescription: initialDescription,
      initialGameplayData: initialGameplayData,
      initialBackgroundColorHex: initialBackgroundColorHex,
      initialDepthSensitivity: initialDepthSensitivity,
      initialGroupId: initialGroupId,
      groupOptions: _levelGroups(appData),
      showGroupSelector: showGroupSelector,
      groupFieldLabel: groupFieldLabel,
      existingNames: existingNames,
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

  Future<void> _promptAndAddLevel() async {
    final AppData appData = Provider.of<AppData>(context, listen: false);
    _ensureMainLevelGroup(appData);
    appData.selectedLevel = -1;
    appData.selectedLayer = -1;
    appData.selectedLayerIndices = <int>{};
    appData.selectedZone = -1;
    appData.selectedZoneIndices = <int>{};
    appData.selectedSprite = -1;
    appData.selectedSpriteIndices = <int>{};
    appData.selectedPath = -1;
    appData.update();
    final _LevelDialogData? levelData = await _promptLevelData(
      title: "New level",
      mode: EditorEntityFormMode.add,
      initialGroupId: GameListGroup.mainId,
      showGroupSelector: true,
      groupFieldLabel: "Level Group",
    );
    if (levelData == null || !mounted) {
      return;
    }
    appData.pushUndo();
    _addLevel(
      appData: appData,
      name: levelData.name,
      description: levelData.description,
      gameplayData: levelData.gameplayData,
      backgroundColorHex: levelData.backgroundColorHex,
      depthSensitivity: levelData.depthSensitivity,
      groupId: levelData.groupId,
    );
    await _autoSaveIfPossible(appData);
  }

  Future<void> _deleteLevel(AppData appData, int index) async {
    if (index < 0 || index >= appData.gameData.levels.length) {
      return;
    }
    appData.pushUndo();
    appData.gameData.levels.removeAt(index);
    appData.selectedLevel = -1;
    appData.selectedLayer = -1;
    appData.selectedZone = -1;
    appData.selectedSprite = -1;
    appData.selectedPath = -1;
    appData.update();
    await _autoSaveIfPossible(appData);
  }

  Future<bool> confirmAndDeleteSelectedLevelFromKeyboard(
    AppData appData,
  ) async {
    final int index = appData.selectedLevel;
    if (index < 0 || index >= appData.gameData.levels.length || !mounted) {
      return false;
    }
    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete level',
      message: 'Delete this level? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    await _deleteLevel(appData, index);
    return true;
  }

  String _inlineUndoGroupKeyForLevel(int index) {
    if (_inlineEditUndoGroupKey.isNotEmpty &&
        _inlineEditUndoLevelIndex == index) {
      return _inlineEditUndoGroupKey;
    }
    _inlineEditUndoLevelIndex = index;
    _inlineEditUndoGroupKey =
        'level-inline-$index-${DateTime.now().microsecondsSinceEpoch}';
    return _inlineEditUndoGroupKey;
  }

  Set<String> _existingLevelNames(
    AppData appData, {
    int? excludingIndex,
  }) {
    return appData.gameData.levels
        .asMap()
        .entries
        .where((entry) => entry.key != excludingIndex)
        .map((entry) => entry.value.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _applyLevelChange(
    AppData appData, {
    required int index,
    required _LevelDialogData value,
    required bool groupedUndo,
  }) async {
    await appData.runProjectMutation(
      debugLabel: groupedUndo ? 'level-inline-live-edit' : 'level-inline-edit',
      undoGroupKey: groupedUndo ? _inlineUndoGroupKeyForLevel(index) : null,
      mutate: () {
        _updateLevel(
          appData: appData,
          index: index,
          name: value.name,
          description: value.description,
          gameplayData: value.gameplayData,
          backgroundColorHex: value.backgroundColorHex,
          depthSensitivity: value.depthSensitivity,
        );
      },
    );
  }

  Widget buildEditToolbarContent(AppData appData) {
    final int index = appData.selectedLevel;
    if (index < 0 || index >= appData.gameData.levels.length) {
      return const SizedBox.shrink();
    }
    final GameLevel selected = appData.gameData.levels[index];
    return _LevelFormDialog(
      key: ValueKey('level-inline-editor-$index'),
      title: "Edit level",
      mode: EditorEntityFormMode.edit,
      initialName: selected.name,
      initialDescription: selected.description,
      initialGameplayData: selected.gameplayData,
      initialBackgroundColorHex: selected.backgroundColorHex,
      initialDepthSensitivity: selected.depthSensitivity,
      initialGroupId: _effectiveLevelGroupId(appData, selected),
      groupOptions: _levelGroups(appData),
      showGroupSelector: false,
      groupFieldLabel: "Level Group",
      existingNames: _existingLevelNames(
        appData,
        excludingIndex: index,
      ),
      minWidth: 280,
      maxWidth: 340,
      onLiveChanged: (value) async {
        await _applyLevelChange(
          appData,
          index: index,
          value: value,
          groupedUndo: true,
        );
      },
      onConfirm: (value) {
        unawaited(
          _applyLevelChange(
            appData,
            index: index,
            value: value,
            groupedUndo: false,
          ),
        );
      },
      onCancel: () {
        _selectLevel(appData, index, true);
      },
      onDelete: () {
        unawaited(_deleteLevel(appData, index));
      },
    );
  }

  void _updateLevel({
    required AppData appData,
    required int index,
    required String name,
    required String description,
    required String gameplayData,
    required String backgroundColorHex,
    required double depthSensitivity,
  }) {
    if (index >= 0 && index < appData.gameData.levels.length) {
      final previous = appData.gameData.levels[index];
      appData.gameData.levels[index] = GameLevel(
        name: name,
        description: description,
        gameplayData: gameplayData,
        layers: previous.layers,
        layerGroups: previous.layerGroups,
        zones: previous.zones,
        zoneGroups: previous.zoneGroups,
        sprites: previous.sprites,
        spriteGroups: previous.spriteGroups,
        pathGroups: previous.pathGroups,
        paths: previous.paths,
        pathBindings: previous.pathBindings,
        groupId: previous.groupId,
        viewportWidth: previous.viewportWidth,
        viewportHeight: previous.viewportHeight,
        viewportX: previous.viewportX,
        viewportY: previous.viewportY,
        viewportAdaptation: previous.viewportAdaptation,
        viewportInitialColor: previous.viewportInitialColor,
        viewportPreviewColor: previous.viewportPreviewColor,
        backgroundColorHex: backgroundColorHex,
        depthSensitivity: depthSensitivity,
      );
      appData.selectedLevel = index;
    }
  }

  void _selectLevel(AppData appData, int index, bool isSelected) {
    if (isSelected) {
      appData.selectedLevel = -1;
      appData.selectedLayer = -1;
      appData.selectedZone = -1;
      appData.selectedSprite = -1;
      appData.selectedPath = -1;
      appData.update();
      return;
    }
    appData.selectedLevel = index;
    appData.selectedLayer = -1;
    appData.selectedZone = -1;
    appData.selectedSprite = -1;
    appData.selectedPath = -1;
    appData.update();
  }

  Future<void> _toggleGroupCollapsed(AppData appData, String groupId) async {
    appData.pushUndo();
    _ensureMainLevelGroup(appData);
    final List<GameListGroup> groups = appData.gameData.levelGroups;
    final int index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      return;
    }
    final GameListGroup group = groups[index];
    group.collapsed = !group.collapsed;
    if (group.collapsed &&
        appData.selectedLevel >= 0 &&
        appData.selectedLevel < appData.gameData.levels.length &&
        _effectiveLevelGroupId(
              appData,
              appData.gameData.levels[appData.selectedLevel],
            ) ==
            group.id) {
      appData.selectedLevel = -1;
      appData.selectedLayer = -1;
      appData.selectedZone = -1;
      appData.selectedSprite = -1;
      appData.selectedPath = -1;
    }
    appData.update();
    await _autoSaveIfPossible(appData);
  }

  void _moveGroup({
    required AppData appData,
    required List<GroupedListRow<GameListGroup, GameLevel>>
        rowsWithoutMovedItem,
    required GroupedListRow<GameListGroup, GameLevel> movedRow,
    required int targetRowIndex,
  }) {
    GroupedListAlgorithms.moveGroup<GameListGroup, GameLevel>(
      groups: appData.gameData.levelGroups,
      rowsWithoutMovedItem: rowsWithoutMovedItem,
      movedRow: movedRow,
      targetRowIndex: targetRowIndex,
      groupIdOf: (group) => group.id,
    );
  }

  void _moveLevel({
    required AppData appData,
    required List<GroupedListRow<GameListGroup, GameLevel>>
        rowsWithoutMovedItem,
    required GroupedListRow<GameListGroup, GameLevel> movedRow,
    required int targetRowIndex,
  }) {
    final List<GameLevel> levels = appData.gameData.levels;
    appData.selectedLevel = GroupedListAlgorithms
        .moveItemAndReturnSelectedIndex<GameListGroup, GameLevel>(
      groups: appData.gameData.levelGroups,
      items: levels,
      rowsWithoutMovedItem: rowsWithoutMovedItem,
      movedRow: movedRow,
      targetRowIndex: targetRowIndex,
      mainGroupId: GameListGroup.mainId,
      groupIdOf: (group) => group.id,
      effectiveGroupIdOfItem: (level) => _effectiveLevelGroupId(appData, level),
      setItemGroupId: (level, groupId) {
        level.groupId = groupId;
      },
      selectedIndex: appData.selectedLevel,
    );
    if (appData.selectedLevel == -1) {
      appData.selectedLayer = -1;
      appData.selectedZone = -1;
      appData.selectedSprite = -1;
      appData.selectedPath = -1;
    }
  }

  void _onReorder(
    AppData appData,
    List<GroupedListRow<GameListGroup, GameLevel>> rows,
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

    final List<GroupedListRow<GameListGroup, GameLevel>> rowsWithoutMovedItem =
        List<GroupedListRow<GameListGroup, GameLevel>>.from(rows);
    final GroupedListRow<GameListGroup, GameLevel> movedRow =
        rowsWithoutMovedItem.removeAt(oldIndex);
    int boundedTargetIndex = targetIndex;
    if (boundedTargetIndex > rowsWithoutMovedItem.length) {
      boundedTargetIndex = rowsWithoutMovedItem.length;
    }

    appData.pushUndo();
    _ensureMainLevelGroup(appData);
    if (movedRow.isGroup) {
      _moveGroup(
        appData: appData,
        rowsWithoutMovedItem: rowsWithoutMovedItem,
        movedRow: movedRow,
        targetRowIndex: boundedTargetIndex,
      );
    } else {
      _moveLevel(
        appData: appData,
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
    final levelRows = _buildLevelRows(appData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              CDKText(
                'Levels',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'Levels are independent scenes or maps in your game. Each level has its own layers, zones, and objects.',
              ),
              const Spacer(),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: () async {
                  await _promptAndAddLevel();
                },
                child: const Text('+ Level'),
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
        Expanded(
            child: levelRows.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: const CDKText(
                      '(No levels defined)',
                      role: CDKTextRole.caption,
                      secondary: true,
                    ),
                  )
                : CupertinoScrollbar(
                    controller: scrollController,
                    child: Localizations.override(
                      context: context,
                      delegates: [
                        DefaultMaterialLocalizations
                            .delegate, // Add Material Localizations
                        DefaultWidgetsLocalizations.delegate,
                      ],
                      child: ReorderableListView.builder(
                        scrollController: scrollController,
                        buildDefaultDragHandles: false,
                        itemCount: levelRows.length,
                        onReorder: (oldIndex, newIndex) =>
                            _onReorder(appData, levelRows, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final GroupedListRow<GameListGroup, GameLevel> row =
                              levelRows[index];
                          if (row.isGroup) {
                            final GameListGroup group = row.group!;
                            final bool showGroupActions =
                                _hoveredGroupId == group.id;
                            final GlobalKey groupActionsAnchorKey =
                                _groupActionsAnchorKey(group.id);
                            return MouseRegion(
                              key: ValueKey('level-group-hover-${group.id}'),
                              onEnter: (_) => _setHoveredGroupId(group.id),
                              onExit: (_) {
                                if (_hoveredGroupId == group.id) {
                                  _setHoveredGroupId(null);
                                }
                              },
                              child: Container(
                                key: ValueKey('level-group-${group.id}'),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 8,
                                ),
                                color: cdkColors.backgroundSecondary1,
                                child: Row(
                                  children: [
                                    CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      minimumSize: const Size(20, 20),
                                      onPressed: () async {
                                        await _toggleGroupCollapsed(
                                            appData, group.id);
                                      },
                                      child: AnimatedRotation(
                                        duration:
                                            const Duration(milliseconds: 220),
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
                                          if (group.id ==
                                              GameListGroup.mainId) ...[
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
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

                          final int levelIndex = row.itemIndex!;
                          final GameLevel level = row.item!;
                          final bool isSelected =
                              (levelIndex == appData.selectedLevel);
                          final bool hiddenByCollapse = row.hiddenByCollapse;

                          return AnimatedSize(
                            key: ValueKey('level-item-$levelIndex'),
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
                                    onTap: () {
                                      _selectLevel(
                                          appData, levelIndex, isSelected);
                                    },
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 36,
                                      ),
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
                                            child: CDKText(
                                              level.name,
                                              role: CDKTextRole.body,
                                              style: listItemTitleStyle,
                                            ),
                                          ),
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                  )),
      ],
    );
  }
}

class _LevelDialogData {
  const _LevelDialogData({
    required this.name,
    required this.description,
    required this.gameplayData,
    required this.backgroundColorHex,
    required this.depthSensitivity,
    required this.groupId,
  });

  final String name;
  final String description;
  final String gameplayData;
  final String backgroundColorHex;
  final double depthSensitivity;
  final String groupId;
}

class _LevelFormDialog extends StatefulWidget {
  const _LevelFormDialog({
    super.key,
    required this.title,
    required this.mode,
    required this.initialName,
    required this.initialDescription,
    required this.initialGameplayData,
    required this.initialBackgroundColorHex,
    required this.initialDepthSensitivity,
    required this.initialGroupId,
    required this.groupOptions,
    required this.showGroupSelector,
    required this.groupFieldLabel,
    required this.existingNames,
    this.onLiveChanged,
    this.onClose,
    this.minWidth = 320,
    this.maxWidth = 420,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
  });

  final String title;
  final EditorEntityFormMode mode;
  final String initialName;
  final String initialDescription;
  final String initialGameplayData;
  final String initialBackgroundColorHex;
  final double initialDepthSensitivity;
  final String initialGroupId;
  final List<GameListGroup> groupOptions;
  final bool showGroupSelector;
  final String groupFieldLabel;
  final Set<String> existingNames;
  final Future<void> Function(_LevelDialogData value)? onLiveChanged;
  final VoidCallback? onClose;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<_LevelDialogData> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  State<_LevelFormDialog> createState() => _LevelFormDialogState();
}

class _LevelFormDialogState extends State<_LevelFormDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription);
  late final TextEditingController _gameplayDataController =
      TextEditingController(text: widget.initialGameplayData);
  late final TextEditingController _depthSensitivityController =
      TextEditingController(
    text: widget.initialDepthSensitivity.toString(),
  );
  final GlobalKey _backgroundColorAnchorKey = GlobalKey();
  final FocusNode _nameFocusNode = FocusNode();
  String? _errorText;
  late String _selectedGroupId = _resolveInitialGroupId();
  late String _backgroundColorHex = _toHexColor(
    _parseHexColor(
        widget.initialBackgroundColorHex, _defaultLevelBackgroundColor),
  );
  EditSession<_LevelDialogData>? _editSession;

  String _resolveInitialGroupId() {
    for (final group in widget.groupOptions) {
      if (group.id == widget.initialGroupId) {
        return group.id;
      }
    }
    if (widget.groupOptions.isNotEmpty) {
      return widget.groupOptions.first.id;
    }
    return GameListGroup.mainId;
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

  String _toHexColor(Color color) {
    final int rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _showBackgroundColorPicker() {
    if (_backgroundColorAnchorKey.currentContext == null) {
      return;
    }
    final ValueNotifier<Color> colorNotifier = ValueNotifier(
      _parseHexColor(_backgroundColorHex, _defaultLevelBackgroundColor),
    );
    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _backgroundColorAnchorKey,
      isAnimated: true,
      isTranslucent: false,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ValueListenableBuilder<Color>(
          valueListenable: colorNotifier,
          builder: (context, value, child) {
            return CDKPickerColor(
              color: value,
              onChanged: (Color color) {
                final Color opaqueColor = Color(color.toARGB32() | 0xFF000000);
                if (opaqueColor.toARGB32() != colorNotifier.value.toARGB32()) {
                  colorNotifier.value = opaqueColor;
                }
                final String nextHex = _toHexColor(opaqueColor);
                if (nextHex == _backgroundColorHex) {
                  return;
                }
                setState(() {
                  _backgroundColorHex = nextHex;
                });
                _onInputChanged();
              },
            );
          },
        ),
      ),
    );
  }

  _LevelDialogData _currentData() {
    final double? parsedDepthSensitivity = _parseDepthSensitivity(
      _depthSensitivityController.text,
    );
    return _LevelDialogData(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      gameplayData: _gameplayDataController.text,
      backgroundColorHex: _backgroundColorHex,
      depthSensitivity:
          parsedDepthSensitivity ?? GameLevel.defaultDepthSensitivity,
      groupId: _selectedGroupId,
    );
  }

  double? _parseDepthSensitivity(String value) {
    final String cleaned = value.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      return null;
    }
    return parsed;
  }

  String? _validateData(_LevelDialogData data) {
    final String cleaned = data.name.trim();
    if (cleaned.isEmpty) {
      return 'Name is required.';
    }
    if (widget.existingNames.contains(cleaned.toLowerCase())) {
      return 'Another level is named like that.';
    }
    if (_parseDepthSensitivity(_depthSensitivityController.text) == null) {
      return 'Depth sensitivity must be a number >= 0.';
    }
    return null;
  }

  bool get _isValid {
    return _validateData(_currentData()) == null;
  }

  bool _didInitialDataChange(_LevelFormDialog oldWidget) {
    return oldWidget.initialName != widget.initialName ||
        oldWidget.initialDescription != widget.initialDescription ||
        oldWidget.initialGameplayData != widget.initialGameplayData ||
        oldWidget.initialBackgroundColorHex !=
            widget.initialBackgroundColorHex ||
        oldWidget.initialDepthSensitivity != widget.initialDepthSensitivity ||
        oldWidget.initialGroupId != widget.initialGroupId;
  }

  void _setControllerTextIfNeeded(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _validate(String value) {
    final String cleaned = value.trim();
    final String? error;
    if (cleaned.isNotEmpty &&
        widget.existingNames.contains(cleaned.toLowerCase())) {
      error = "Another level is named like that.";
    } else {
      error = null;
    }
    setState(() {
      _errorText = error;
    });
  }

  void _onInputChanged() {
    queueEditorLiveEditUpdate(
      mode: widget.mode,
      session: _editSession,
      value: _currentData(),
    );
  }

  void _confirm() {
    final String cleanedName = _nameController.text.trim();
    final double? parsedDepthSensitivity = _parseDepthSensitivity(
      _depthSensitivityController.text,
    );
    _validate(cleanedName);
    if (cleanedName.isEmpty ||
        widget.existingNames.contains(cleanedName.toLowerCase()) ||
        parsedDepthSensitivity == null) {
      if (parsedDepthSensitivity == null) {
        setState(() {
          _errorText = 'Depth sensitivity must be a number >= 0.';
        });
      }
      return;
    }
    widget.onConfirm(
      _LevelDialogData(
        name: cleanedName,
        description: _descriptionController.text.trim(),
        gameplayData: _gameplayDataController.text,
        backgroundColorHex: _backgroundColorHex,
        depthSensitivity: parsedDepthSensitivity,
        groupId: _selectedGroupId,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _editSession = createEditorLiveEditSession<_LevelDialogData>(
      mode: widget.mode,
      initialValue: _currentData(),
      validate: _validateData,
      onPersist: widget.onLiveChanged,
      areEqual: (a, b) =>
          a.name == b.name &&
          a.description == b.description &&
          a.gameplayData == b.gameplayData &&
          a.backgroundColorHex == b.backgroundColorHex &&
          a.depthSensitivity == b.depthSensitivity &&
          a.groupId == b.groupId,
    );
    if (!widget.mode.isLiveEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _nameFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _LevelFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool initialDataChanged = _didInitialDataChange(oldWidget);
    bool shouldRebuild = false;
    if (initialDataChanged) {
      _setControllerTextIfNeeded(_nameController, widget.initialName);
      _setControllerTextIfNeeded(
        _descriptionController,
        widget.initialDescription,
      );
      _setControllerTextIfNeeded(
        _gameplayDataController,
        widget.initialGameplayData,
      );
      _setControllerTextIfNeeded(
        _depthSensitivityController,
        widget.initialDepthSensitivity.toString(),
      );
      final String nextBackgroundHex = _toHexColor(
        _parseHexColor(
          widget.initialBackgroundColorHex,
          _defaultLevelBackgroundColor,
        ),
      );
      if (_backgroundColorHex != nextBackgroundHex) {
        _backgroundColorHex = nextBackgroundHex;
        shouldRebuild = true;
      }
      _errorText = null;
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
    _descriptionController.dispose();
    _gameplayDataController.dispose();
    _depthSensitivityController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
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
              title: 'Delete level',
              message: 'Delete this level? This cannot be undone.',
            ),
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabeledField(
            label: 'Name',
            child: CDKFieldText(
              placeholder: 'Level name',
              controller: _nameController,
              focusNode: _nameFocusNode,
              onChanged: (value) {
                _validate(value);
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
            label: 'Description',
            child: CDKFieldText(
              placeholder: 'Level description (optional)',
              controller: _descriptionController,
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
          SizedBox(height: spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: EditorLabeledField(
                  label: 'Background color',
                  child: Row(
                    children: [
                      CDKButtonColor(
                        key: _backgroundColorAnchorKey,
                        color: _parseHexColor(
                            _backgroundColorHex, _defaultLevelBackgroundColor),
                        onPressed: _showBackgroundColorPicker,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CDKText(
                          _backgroundColorHex,
                          role: CDKTextRole.caption,
                          color: cdkColors.colorText,
                          style: typography.caption.copyWith(
                            fontSize: (typography.caption.fontSize ?? 12) - 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: EditorLabeledField(
                  label: 'Depth sensitivity',
                  child: CDKFieldText(
                    placeholder: '0.08',
                    controller: _depthSensitivityController,
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
          ),
          SizedBox(height: spacing.sm),
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
          if (_errorText != null) ...[
            SizedBox(height: spacing.sm),
            Text(
              _errorText!,
              style: typography.caption.copyWith(color: CDKTheme.red),
            ),
          ],
        ],
      ),
    );
  }
}
