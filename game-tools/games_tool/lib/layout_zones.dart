import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_level.dart';
import 'game_zone.dart';
import 'game_zone_group.dart';
import 'game_zone_type.dart';
import 'layout_utils.dart';
import 'widgets/edit_session.dart';
import 'widgets/editor_entity_form_mode.dart';
import 'widgets/editor_form_dialog_scaffold.dart';
import 'widgets/editor_header_delete_button.dart';
import 'widgets/editor_labeled_field.dart';
import 'widgets/editor_live_edit_session.dart';
import 'widgets/grouped_list.dart';
import 'widgets/section_help_button.dart';
import 'widgets/selectable_color_swatch.dart';

const List<String> _zoneTypeColorPalette = [
  'red',
  'deepOrange',
  'orange',
  'amber',
  'yellow',
  'lime',
  'lightGreen',
  'green',
  'teal',
  'cyan',
  'lightBlue',
  'blue',
  'indigo',
  'purple',
  'pink',
];

const GameZoneType _defaultZoneType = GameZoneType(
  name: 'Default',
  color: 'blue',
);

class LayoutZones extends StatefulWidget {
  const LayoutZones({super.key});

  @override
  LayoutZonesState createState() => LayoutZonesState();
}

class LayoutZonesState extends State<LayoutZones> {
  final ScrollController scrollController = ScrollController();
  final GlobalKey _zoneTypesAnchorKey = GlobalKey();
  final GlobalKey _addGroupAnchorKey = GlobalKey();
  final Map<String, GlobalKey> _groupActionsAnchorKeys = <String, GlobalKey>{};
  int _newGroupCounter = 0;
  String _inlineEditUndoGroupKey = '';
  int _inlineEditUndoZoneIndex = -1;

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

  List<GameZoneType> _zoneTypes(AppData appData) {
    return appData.gameData.zoneTypes;
  }

  List<GameZoneGroup> _zoneGroups(GameLevel level) {
    if (level.zoneGroups.isEmpty) {
      return <GameZoneGroup>[GameZoneGroup.main()];
    }
    final bool hasMain =
        level.zoneGroups.any((group) => group.id == GameZoneGroup.mainId);
    if (hasMain) {
      return level.zoneGroups;
    }
    return <GameZoneGroup>[GameZoneGroup.main(), ...level.zoneGroups];
  }

  void _ensureMainGroupInLevel(GameLevel level) {
    final int mainIndex = level.zoneGroups
        .indexWhere((group) => group.id == GameZoneGroup.mainId);
    if (mainIndex == -1) {
      level.zoneGroups.insert(0, GameZoneGroup.main());
      return;
    }
    final GameZoneGroup mainGroup = level.zoneGroups[mainIndex];
    final String normalizedName = mainGroup.name.trim().isEmpty
        ? GameZoneGroup.defaultMainName
        : mainGroup.name.trim();
    if (mainGroup.name != normalizedName) {
      mainGroup.name = normalizedName;
    }
  }

  Set<String> _groupIds(GameLevel level) {
    return _zoneGroups(level).map((group) => group.id).toSet();
  }

  String _effectiveZoneGroupId(GameLevel level, GameZone zone) {
    final String groupId = zone.groupId.trim();
    if (groupId.isNotEmpty && _groupIds(level).contains(groupId)) {
      return groupId;
    }
    return GameZoneGroup.mainId;
  }

  GameZoneGroup? _findGroupById(GameLevel level, String groupId) {
    for (final group in _zoneGroups(level)) {
      if (group.id == groupId) {
        return group;
      }
    }
    return null;
  }

  List<_ZoneListRow> _buildZoneRows(GameLevel level) {
    final List<_ZoneListRow> rows = [];
    final List<GameZoneGroup> groups = _zoneGroups(level);
    final Set<String> validGroupIds = groups.map((group) => group.id).toSet();
    final Map<String, List<int>> zoneIndicesByGroupId = <String, List<int>>{};

    for (int i = 0; i < level.zones.length; i++) {
      final GameZone zone = level.zones[i];
      final String zoneGroupId = zone.groupId.trim();
      final String effectiveGroupId = validGroupIds.contains(zoneGroupId)
          ? zoneGroupId
          : GameZoneGroup.mainId;
      zoneIndicesByGroupId.putIfAbsent(effectiveGroupId, () => <int>[]).add(i);
    }

    for (final group in groups) {
      rows.add(_ZoneListRow.group(group: group));
      final List<int> zoneIndices =
          zoneIndicesByGroupId[group.id] ?? const <int>[];
      for (final int zoneIndex in zoneIndices) {
        final GameZone zone = level.zones[zoneIndex];
        rows.add(
          _ZoneListRow.zone(
            groupId: group.id,
            zone: zone,
            zoneIndex: zoneIndex,
            hiddenByCollapse: group.collapsed,
          ),
        );
      }
    }
    return rows;
  }

  GlobalKey _groupActionsAnchorKey(String groupId) {
    return _groupActionsAnchorKeys.putIfAbsent(groupId, GlobalKey.new);
  }

  Set<String> _zoneGroupNames(
    GameLevel level, {
    String? excludingId,
  }) {
    return _zoneGroups(level)
        .where((group) => group.id != excludingId)
        .map((group) => group.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  int _firstZoneIndexForGroup(List<GameZone> zones, String groupId) {
    for (int i = 0; i < zones.length; i++) {
      if (zones[i].groupId == groupId) {
        return i;
      }
    }
    return -1;
  }

  int _lastZoneIndexForGroup(List<GameZone> zones, String groupId) {
    for (int i = zones.length - 1; i >= 0; i--) {
      if (zones[i].groupId == groupId) {
        return i;
      }
    }
    return -1;
  }

  int _insertionIndexAtGroupStart(
    GameLevel level,
    List<GameZone> zones,
    String groupId,
  ) {
    final int firstInGroup = _firstZoneIndexForGroup(zones, groupId);
    if (firstInGroup != -1) {
      return firstInGroup;
    }

    final int groupOrderIndex =
        _zoneGroups(level).indexWhere((group) => group.id == groupId);
    if (groupOrderIndex == -1) {
      return zones.length;
    }

    for (int i = groupOrderIndex - 1; i >= 0; i--) {
      final int lastPrev =
          _lastZoneIndexForGroup(zones, _zoneGroups(level)[i].id);
      if (lastPrev != -1) {
        return lastPrev + 1;
      }
    }

    for (int i = groupOrderIndex + 1; i < _zoneGroups(level).length; i++) {
      final int firstNext =
          _firstZoneIndexForGroup(zones, _zoneGroups(level)[i].id);
      if (firstNext != -1) {
        return firstNext;
      }
    }
    return zones.length;
  }

  int _insertionIndexAtGroupEnd(
    GameLevel level,
    List<GameZone> zones,
    String groupId,
  ) {
    final int lastInGroup = _lastZoneIndexForGroup(zones, groupId);
    if (lastInGroup != -1) {
      return lastInGroup + 1;
    }
    return _insertionIndexAtGroupStart(level, zones, groupId);
  }

  String _normalizeZoneTypeColor(String color) {
    if (_zoneTypeColorPalette.contains(color)) {
      return color;
    }
    return _defaultZoneType.color;
  }

  String _zoneColorForTypeName(AppData appData, String typeName) {
    for (final type in _zoneTypes(appData)) {
      if (type.name == typeName) {
        return type.color;
      }
    }
    return _defaultZoneType.color;
  }

  String _zoneColorName(AppData appData, GameZone zone) {
    final String fromType = _zoneColorForTypeName(appData, zone.type);
    if (fromType.isNotEmpty) {
      return fromType;
    }
    return _normalizeZoneTypeColor(zone.color);
  }

  String _zoneDisplayName(GameZone zone, int index) {
    final String zoneName = zone.name.trim();
    if (zoneName.isNotEmpty) {
      return zoneName;
    }
    final String zoneType = zone.type.trim();
    if (zoneType.isNotEmpty) {
      return zoneType;
    }
    return 'Zone ${index + 1}';
  }

  Set<String> _usedZoneTypeNames(AppData appData) {
    final Set<String> used = {};
    for (final level in appData.gameData.levels) {
      for (final zone in level.zones) {
        final String typeName = zone.type.trim();
        if (typeName.isNotEmpty) {
          used.add(typeName);
        }
      }
    }
    return used;
  }

  void _applyZoneTypeDrafts(AppData appData, List<_ZoneTypeDraft> drafts) {
    final List<_ZoneTypeDraft> cleaned = [];
    final Set<String> seenNames = {};
    for (final draft in drafts) {
      final String trimmedName = draft.name.trim();
      if (trimmedName.isEmpty || seenNames.contains(trimmedName)) {
        continue;
      }
      cleaned.add(
        _ZoneTypeDraft(
          key: draft.key,
          name: trimmedName,
          color: _normalizeZoneTypeColor(draft.color),
        ),
      );
      seenNames.add(trimmedName);
    }

    final List<GameZoneType> nextTypes = cleaned
        .map(
          (draft) => GameZoneType(
            name: draft.name,
            color: draft.color,
          ),
        )
        .toList(growable: false);

    if (cleaned.isNotEmpty) {
      final Map<String, _ZoneTypeDraft> byKey = {
        for (final draft in cleaned) draft.key: draft
      };
      final Map<String, _ZoneTypeDraft> byName = {
        for (final draft in cleaned) draft.name: draft
      };
      final _ZoneTypeDraft fallback = cleaned.first;

      for (final level in appData.gameData.levels) {
        for (final zone in level.zones) {
          final _ZoneTypeDraft? renamedType = byKey[zone.type];
          if (renamedType != null) {
            zone.type = renamedType.name;
            zone.color = renamedType.color;
            continue;
          }
          final _ZoneTypeDraft? existingType = byName[zone.type];
          if (existingType != null) {
            zone.color = existingType.color;
            continue;
          }
          zone.type = fallback.name;
          zone.color = fallback.color;
        }
      }
    }

    appData.gameData.zoneTypes
      ..clear()
      ..addAll(nextTypes);
  }

  Future<void> _persistZoneTypeDrafts(
      AppData appData, List<_ZoneTypeDraft> drafts) async {
    await appData.runProjectMutation(
      debugLabel: 'zone-types-persist',
      mutate: () {
        _applyZoneTypeDrafts(appData, drafts);
      },
    );
  }

  Future<void> _showZoneTypesPopover(AppData appData) async {
    if (Overlay.maybeOf(context) == null) {
      return;
    }
    final CDKDialogController controller = CDKDialogController();

    final List<_ZoneTypeDraft> initialDrafts = _zoneTypes(appData)
        .map(
          (type) => _ZoneTypeDraft(
            key: type.name,
            name: type.name,
            color: _normalizeZoneTypeColor(type.color),
          ),
        )
        .toList(growable: false);

    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _zoneTypesAnchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: _ZoneTypesPopover(
        initialTypes: initialDrafts,
        colorPalette: _zoneTypeColorPalette,
        usedTypeKeys: _usedZoneTypeNames(appData),
        onTypesChanged: (nextDrafts) {
          unawaited(_persistZoneTypeDrafts(appData, nextDrafts));
        },
      ),
    );
  }

  String _newGroupId() {
    return '__group_${DateTime.now().microsecondsSinceEpoch}_${_newGroupCounter++}';
  }

  Future<bool> _upsertZoneGroup(
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
    if (_zoneGroupNames(level, excludingId: draft.id)
        .contains(nextName.toLowerCase())) {
      return false;
    }

    await appData.runProjectMutation(
      debugLabel: 'zone-group-upsert',
      mutate: () {
        final GameLevel level = appData.gameData.levels[appData.selectedLevel];
        _ensureMainGroupInLevel(level);
        final List<GameZoneGroup> groups = level.zoneGroups;
        final int existingIndex =
            groups.indexWhere((group) => group.id == draft.id);
        if (existingIndex != -1) {
          groups[existingIndex].name = nextName;
          return;
        }
        groups.add(
          GameZoneGroup(
            id: draft.id,
            name: nextName,
            collapsed: false,
          ),
        );
      },
    );

    return true;
  }

  Future<bool> _confirmAndDeleteZoneGroup(
      AppData appData, String groupId) async {
    if (!mounted ||
        appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    if (groupId == GameZoneGroup.mainId) {
      return false;
    }

    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final GameZoneGroup? group = _findGroupById(level, groupId);
    if (group == null) {
      return false;
    }

    final int zonesInGroup = level.zones
        .where((zone) => _effectiveZoneGroupId(level, zone) == groupId)
        .length;

    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete group',
      message: zonesInGroup > 0
          ? 'Delete "${group.name}"? $zonesInGroup zone(s) will be moved to "Main".'
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
      debugLabel: 'zone-group-delete',
      mutate: () {
        final GameLevel level = appData.gameData.levels[appData.selectedLevel];
        _ensureMainGroupInLevel(level);
        final List<GameZoneGroup> groups = level.zoneGroups;
        final List<GameZone> zones = level.zones;
        final int groupIndex = groups.indexWhere((g) => g.id == groupId);
        if (groupIndex == -1) {
          return;
        }
        GroupedListAlgorithms.reassignItemsToGroup<GameZone>(
          items: zones,
          fromGroupId: groupId,
          toGroupId: GameZoneGroup.mainId,
          itemGroupIdOf: (zone) => zone.groupId,
          setItemGroupId: (zone, nextGroupId) {
            zone.groupId = nextGroupId;
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
        title: 'Add Zone Group',
        existingNames: _zoneGroups(level).map((group) => group.name),
        onCancel: controller.close,
        onAdd: (name) async {
          final bool added = await _upsertZoneGroup(
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
    GameZoneGroup group,
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
        existingNames: _zoneGroups(level)
            .where((candidate) => candidate.id != group.id)
            .map((candidate) => candidate.name),
        onCancel: controller.close,
        onRename: (name) async {
          final bool renamed = await _upsertZoneGroup(
            appData,
            GroupedListGroupDraft(
              id: group.id,
              name: name,
              collapsed: group.collapsed,
            ),
          );
          return renamed;
        },
        onDelete: group.id == GameZoneGroup.mainId
            ? null
            : () async {
                final bool deleted =
                    await _confirmAndDeleteZoneGroup(appData, group.id);
                if (deleted) {
                  controller.close();
                }
                return deleted;
              },
      ),
    );
  }

  void _addZone({
    required AppData appData,
    required _ZoneDialogData data,
  }) {
    if (appData.selectedLevel == -1) {
      return;
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    _ensureMainGroupInLevel(level);
    final Set<String> validGroupIds = _groupIds(level);
    final String targetGroupId = validGroupIds.contains(data.groupId)
        ? data.groupId
        : GameZoneGroup.mainId;
    level.zones.add(
      GameZone(
        name: data.name,
        type: data.type,
        gameplayData: data.gameplayData,
        x: data.x,
        y: data.y,
        width: data.width,
        height: data.height,
        color: _zoneColorForTypeName(appData, data.type),
        groupId: targetGroupId,
      ),
    );
    appData.selectedZone = -1;
    appData.selectedZoneIndices = <int>{};
  }

  void _updateZone({
    required AppData appData,
    required int index,
    required _ZoneDialogData data,
  }) {
    if (appData.selectedLevel == -1) {
      return;
    }
    final zones = appData.gameData.levels[appData.selectedLevel].zones;
    if (index < 0 || index >= zones.length) {
      return;
    }
    final String existingGroupId = zones[index].groupId;
    zones[index] = GameZone(
      name: data.name,
      type: data.type,
      gameplayData: data.gameplayData,
      x: data.x,
      y: data.y,
      width: data.width,
      height: data.height,
      color: _zoneColorForTypeName(appData, data.type),
      groupId: existingGroupId,
    );
    appData.selectedZone = index;
    appData.selectedZoneIndices = <int>{index};
  }

  Future<_ZoneDialogData?> _promptZoneData({
    required String title,
    required EditorEntityFormMode mode,
    required _ZoneDialogData initialData,
    required List<GameZoneType> zoneTypes,
    List<GameZoneGroup> groupOptions = const <GameZoneGroup>[],
    bool showGroupSelector = false,
    String groupFieldLabel = 'Zone Group',
    GlobalKey? anchorKey,
    bool useArrowedPopover = false,
    Future<void> Function(_ZoneDialogData value)? onLiveChanged,
    VoidCallback? onDelete,
  }) async {
    if (Overlay.maybeOf(context) == null) {
      return null;
    }

    final AppData appData = Provider.of<AppData>(context, listen: false);
    final CDKDialogController controller = CDKDialogController();
    final Completer<_ZoneDialogData?> completer = Completer<_ZoneDialogData?>();
    _ZoneDialogData? result;

    final dialogChild = _ZoneFormDialog(
      title: title,
      mode: mode,
      initialData: initialData,
      zoneTypes: zoneTypes,
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

  Future<void> _promptAndAddZone() async {
    final appData = Provider.of<AppData>(context, listen: false);
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    appData.selectedZone = -1;
    appData.selectedZoneIndices = <int>{};
    appData.update();
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    _ensureMainGroupInLevel(level);
    final List<GameZoneType> zoneTypes = _zoneTypes(appData);
    if (zoneTypes.isEmpty) {
      return;
    }
    final data = await _promptZoneData(
      title: "New zone",
      mode: EditorEntityFormMode.add,
      initialData: _ZoneDialogData(
        name: 'Zone ${level.zones.length + 1}',
        type: zoneTypes.first.name,
        gameplayData: '',
        x: 0,
        y: 0,
        width: 50,
        height: 50,
        groupId: GameZoneGroup.mainId,
      ),
      zoneTypes: zoneTypes,
      groupOptions: _zoneGroups(level),
      showGroupSelector: true,
      groupFieldLabel: 'Zone Group',
    );
    if (!mounted || data == null) {
      return;
    }
    await appData.runProjectMutation(
      debugLabel: 'zone-add',
      mutate: () {
        _addZone(appData: appData, data: data);
      },
    );
  }

  Future<void> _deleteZone(AppData appData, int index) async {
    if (appData.selectedLevel == -1) {
      return;
    }
    final zones = appData.gameData.levels[appData.selectedLevel].zones;
    if (index < 0 || index >= zones.length) {
      return;
    }
    await appData.runProjectMutation(
      debugLabel: 'zone-delete',
      mutate: () {
        zones.removeAt(index);
        appData.selectedZone = -1;
        appData.selectedZoneIndices = <int>{};
      },
    );
  }

  Future<bool> confirmAndDeleteSelectedZoneFromKeyboard(
    AppData appData,
  ) async {
    if (appData.selectedLevel == -1 || !mounted) {
      return false;
    }
    final List<GameZone> zones =
        appData.gameData.levels[appData.selectedLevel].zones;
    final int zoneCount = zones.length;
    if (zoneCount <= 0) {
      return false;
    }
    final Set<int> selected = appData.selectedZoneIndices
        .where((index) => index >= 0 && index < zoneCount)
        .toSet();
    if (selected.isEmpty &&
        appData.selectedZone >= 0 &&
        appData.selectedZone < zoneCount) {
      selected.add(appData.selectedZone);
    }
    if (selected.isEmpty) {
      return false;
    }
    final bool isSingle = selected.length == 1;
    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: isSingle ? 'Delete zone' : 'Delete zones',
      message: isSingle
          ? 'Delete this zone? This cannot be undone.'
          : 'Delete ${selected.length} selected zones? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    await appData.runProjectMutation(
      debugLabel: 'zone-delete-selected',
      mutate: () {
        final List<GameZone> currentZones =
            appData.gameData.levels[appData.selectedLevel].zones;
        final List<int> indices = selected.toList(growable: false)
          ..sort((a, b) => b.compareTo(a));
        for (final index in indices) {
          if (index >= 0 && index < currentZones.length) {
            currentZones.removeAt(index);
          }
        }
        appData.selectedZone = -1;
        appData.selectedZoneIndices = <int>{};
      },
    );
    return true;
  }

  int _inlineSelectedZoneIndex(AppData appData) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return -1;
    }
    final int zoneCount =
        appData.gameData.levels[appData.selectedLevel].zones.length;
    if (zoneCount <= 0) {
      return -1;
    }
    if (appData.selectedZone >= 0 && appData.selectedZone < zoneCount) {
      return appData.selectedZone;
    }
    final Set<int> selected = appData.selectedZoneIndices
        .where((index) => index >= 0 && index < zoneCount)
        .toSet();
    if (selected.length != 1) {
      return -1;
    }
    return selected.first;
  }

  String _inlineUndoGroupKeyForZone(int index) {
    if (_inlineEditUndoGroupKey.isNotEmpty &&
        _inlineEditUndoZoneIndex == index) {
      return _inlineEditUndoGroupKey;
    }
    _inlineEditUndoZoneIndex = index;
    _inlineEditUndoGroupKey =
        'zone-inline-$index-${DateTime.now().microsecondsSinceEpoch}';
    return _inlineEditUndoGroupKey;
  }

  Future<void> _applyZoneChange(
    AppData appData, {
    required int index,
    required _ZoneDialogData value,
    required bool groupedUndo,
  }) async {
    await appData.runProjectMutation(
      debugLabel: groupedUndo ? 'zone-inline-live-edit' : 'zone-inline-edit',
      undoGroupKey: groupedUndo ? _inlineUndoGroupKeyForZone(index) : null,
      mutate: () {
        _updateZone(appData: appData, index: index, data: value);
      },
    );
  }

  Widget buildEditToolbarContent(AppData appData) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return const SizedBox.shrink();
    }
    final GameLevel level = appData.gameData.levels[appData.selectedLevel];
    final int index = _inlineSelectedZoneIndex(appData);
    if (index < 0 || index >= level.zones.length) {
      return const SizedBox.shrink();
    }
    final List<GameZoneType> zoneTypes = _zoneTypes(appData);
    if (zoneTypes.isEmpty) {
      return const SizedBox.shrink();
    }
    final GameZone zone = level.zones[index];
    final bool typeExists = zoneTypes.any((type) => type.name == zone.type);
    return _ZoneFormDialog(
      key: ValueKey('zone-inline-editor-$index'),
      title: 'Edit zone',
      mode: EditorEntityFormMode.edit,
      initialData: _ZoneDialogData(
        name: zone.name,
        type: typeExists ? zone.type : zoneTypes.first.name,
        gameplayData: zone.gameplayData,
        x: zone.x,
        y: zone.y,
        width: zone.width,
        height: zone.height,
        groupId: _effectiveZoneGroupId(level, zone),
      ),
      zoneTypes: zoneTypes,
      groupOptions: _zoneGroups(level),
      showGroupSelector: false,
      groupFieldLabel: 'Zone Group',
      minWidth: 280,
      maxWidth: 340,
      onLiveChanged: (value) async {
        await _applyZoneChange(
          appData,
          index: index,
          value: value,
          groupedUndo: true,
        );
      },
      onConfirm: (value) {
        unawaited(
          _applyZoneChange(
            appData,
            index: index,
            value: value,
            groupedUndo: false,
          ),
        );
      },
      onCancel: () {
        _selectZone(appData, index, true);
      },
      onDelete: () {
        unawaited(_deleteZone(appData, index));
      },
    );
  }

  void _selectZone(
    AppData appData,
    int index,
    bool isSelected, {
    bool additive = false,
  }) {
    if (additive &&
        appData.selectedLevel >= 0 &&
        appData.selectedLevel < appData.gameData.levels.length) {
      final int zoneCount =
          appData.gameData.levels[appData.selectedLevel].zones.length;
      final Set<int> nextSelection = appData.selectedZoneIndices
          .where((value) => value >= 0 && value < zoneCount)
          .toSet();
      final int currentPrimary = appData.selectedZone;
      if (currentPrimary >= 0 && currentPrimary < zoneCount) {
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
      appData.selectedZone = nextPrimary;
      appData.selectedZoneIndices = nextSelection;
      appData.update();
      return;
    }
    if (isSelected) {
      appData.selectedZone = -1;
      appData.selectedZoneIndices = <int>{};
      appData.update();
      return;
    }
    appData.selectedZone = index;
    appData.selectedZoneIndices = <int>{index};
    appData.update();
  }

  void selectZone(AppData appData, int index, bool isSelected) {
    _selectZone(appData, index, isSelected);
  }

  Future<void> _toggleGroupCollapsed(AppData appData, String groupId) async {
    if (appData.selectedLevel == -1 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return;
    }
    await appData.runProjectMutation(
      debugLabel: 'zone-group-toggle-collapse',
      mutate: () {
        final GameLevel level = appData.gameData.levels[appData.selectedLevel];
        _ensureMainGroupInLevel(level);
        final int index =
            level.zoneGroups.indexWhere((group) => group.id == groupId);
        if (index == -1) {
          return;
        }
        final GameZoneGroup group = level.zoneGroups[index];
        group.collapsed = !group.collapsed;
        if (group.collapsed &&
            appData.selectedZone >= 0 &&
            appData.selectedZone < level.zones.length &&
            _effectiveZoneGroupId(level, level.zones[appData.selectedZone]) ==
                group.id) {
          appData.selectedZone = -1;
          appData.selectedZoneIndices = <int>{};
        }
      },
    );
  }

  void _moveGroup({
    required GameLevel level,
    required List<_ZoneListRow> rowsWithoutMovedItem,
    required _ZoneListRow movedRow,
    required int targetRowIndex,
  }) {
    final List<GameZoneGroup> groups = level.zoneGroups;
    final int movedGroupIndex =
        groups.indexWhere((group) => group.id == movedRow.groupId);
    if (movedGroupIndex == -1) {
      return;
    }

    int insertGroupIndex;
    if (targetRowIndex >= rowsWithoutMovedItem.length) {
      insertGroupIndex = groups.length;
    } else {
      final _ZoneListRow targetRow = rowsWithoutMovedItem[targetRowIndex];
      insertGroupIndex =
          groups.indexWhere((group) => group.id == targetRow.groupId);
      if (insertGroupIndex == -1) {
        insertGroupIndex = groups.length;
      }
    }

    final GameZoneGroup movedGroup = groups.removeAt(movedGroupIndex);
    if (movedGroupIndex < insertGroupIndex) {
      insertGroupIndex -= 1;
    }
    insertGroupIndex = insertGroupIndex.clamp(0, groups.length);
    groups.insert(insertGroupIndex, movedGroup);
  }

  void _moveZone({
    required AppData appData,
    required GameLevel level,
    required List<_ZoneListRow> rowsWithoutMovedItem,
    required _ZoneListRow movedRow,
    required int targetRowIndex,
  }) {
    final List<GameZone> zones = level.zones;
    final GameZone? movedZone = movedRow.zone;
    if (movedZone == null) {
      return;
    }
    final GameZone? selectedZone =
        appData.selectedZone >= 0 && appData.selectedZone < zones.length
            ? zones[appData.selectedZone]
            : null;

    final int currentIndex = zones.indexOf(movedZone);
    if (currentIndex == -1) {
      return;
    }
    zones.removeAt(currentIndex);

    String targetGroupId = GameZoneGroup.mainId;
    int insertZoneIndex = zones.length;

    if (rowsWithoutMovedItem.isEmpty) {
      targetGroupId = GameZoneGroup.mainId;
      insertZoneIndex = _insertionIndexAtGroupEnd(level, zones, targetGroupId);
    } else if (targetRowIndex <= 0) {
      final _ZoneListRow firstRow = rowsWithoutMovedItem.first;
      targetGroupId = firstRow.groupId;
      if (firstRow.isZone) {
        final int targetZoneIndex = zones.indexOf(firstRow.zone!);
        insertZoneIndex = targetZoneIndex == -1
            ? _insertionIndexAtGroupStart(level, zones, targetGroupId)
            : targetZoneIndex;
      } else {
        insertZoneIndex =
            _insertionIndexAtGroupStart(level, zones, targetGroupId);
      }
    } else if (targetRowIndex >= rowsWithoutMovedItem.length) {
      final _ZoneListRow lastRow = rowsWithoutMovedItem.last;
      targetGroupId = lastRow.groupId;
      if (lastRow.isZone) {
        final int targetZoneIndex = zones.indexOf(lastRow.zone!);
        insertZoneIndex = targetZoneIndex == -1
            ? _insertionIndexAtGroupEnd(level, zones, targetGroupId)
            : targetZoneIndex + 1;
      } else {
        insertZoneIndex =
            _insertionIndexAtGroupEnd(level, zones, targetGroupId);
      }
    } else {
      final _ZoneListRow targetRow = rowsWithoutMovedItem[targetRowIndex];
      if (targetRow.isZone) {
        targetGroupId = targetRow.groupId;
        final int targetZoneIndex = zones.indexOf(targetRow.zone!);
        insertZoneIndex = targetZoneIndex == -1
            ? _insertionIndexAtGroupEnd(level, zones, targetGroupId)
            : targetZoneIndex;
      } else {
        targetGroupId = targetRow.groupId;
        bool groupHasZones(String groupId) {
          return zones.any(
            (zone) => _effectiveZoneGroupId(level, zone) == groupId,
          );
        }

        final bool targetGroupHasZones = groupHasZones(targetGroupId);
        if (targetRowIndex > 0) {
          final _ZoneListRow previousRow =
              rowsWithoutMovedItem[targetRowIndex - 1];
          if (previousRow.isGroup && !groupHasZones(previousRow.groupId)) {
            // Dropping in the gap right after an empty group header should
            // insert into that empty group.
            targetGroupId = previousRow.groupId;
            insertZoneIndex =
                _insertionIndexAtGroupStart(level, zones, targetGroupId);
          } else if (previousRow.isZone && targetGroupHasZones) {
            // Inserting right before a non-empty group's header is interpreted
            // as dropping at the end of the previous group.
            targetGroupId = previousRow.groupId;
            final int previousZoneIndex = zones.indexOf(previousRow.zone!);
            insertZoneIndex = previousZoneIndex == -1
                ? _insertionIndexAtGroupEnd(level, zones, targetGroupId)
                : previousZoneIndex + 1;
          } else {
            // For empty groups (or top-of-list) dropping on header inserts
            // into that group.
            insertZoneIndex =
                _insertionIndexAtGroupStart(level, zones, targetGroupId);
          }
        } else {
          insertZoneIndex =
              _insertionIndexAtGroupStart(level, zones, targetGroupId);
        }
      }
    }

    if (insertZoneIndex < 0 || insertZoneIndex > zones.length) {
      insertZoneIndex = zones.length;
    }
    movedZone.groupId = targetGroupId;
    zones.insert(insertZoneIndex, movedZone);

    if (selectedZone == null) {
      appData.selectedZone = -1;
      appData.selectedZoneIndices = <int>{};
      return;
    }
    appData.selectedZone = zones.indexOf(selectedZone);
    appData.selectedZoneIndices =
        appData.selectedZone >= 0 ? <int>{appData.selectedZone} : <int>{};
  }

  void _onReorder(
    AppData appData,
    List<_ZoneListRow> rows,
    int oldIndex,
    int newIndex,
  ) {
    if (appData.selectedLevel == -1) {
      return;
    }
    if (rows.isEmpty || oldIndex < 0 || oldIndex >= rows.length) {
      return;
    }
    if (newIndex < 0) {
      newIndex = 0;
    }
    if (newIndex > rows.length) {
      newIndex = rows.length;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0) {
      newIndex = 0;
    }

    final List<_ZoneListRow> rowsWithoutMovedItem =
        List<_ZoneListRow>.from(rows);
    final _ZoneListRow movedRow = rowsWithoutMovedItem.removeAt(oldIndex);
    if (newIndex > rowsWithoutMovedItem.length) {
      newIndex = rowsWithoutMovedItem.length;
    }

    unawaited(
      appData.runProjectMutation(
        debugLabel: 'zone-reorder',
        mutate: () {
          final GameLevel level =
              appData.gameData.levels[appData.selectedLevel];
          _ensureMainGroupInLevel(level);
          if (movedRow.isGroup) {
            _moveGroup(
              level: level,
              rowsWithoutMovedItem: rowsWithoutMovedItem,
              movedRow: movedRow,
              targetRowIndex: newIndex,
            );
          } else {
            _moveZone(
              appData: appData,
              level: level,
              rowsWithoutMovedItem: rowsWithoutMovedItem,
              movedRow: movedRow,
              targetRowIndex: newIndex,
            );
          }
        },
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
    final TextStyle listItemTitleStyle = typography.body.copyWith(
      fontSize: (typography.body.fontSize ?? 14) + 2,
      fontWeight: FontWeight.w700,
      height: 1.0,
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
                  'Level Zones',
                  role: CDKTextRole.title,
                  style: sectionTitleStyle,
                ),
                const SizedBox(width: 6),
                const SectionHelpButton(
                  message:
                      'Zones are named rectangular areas within a level used to trigger events or define regions such as spawn points, triggers, or boundaries.',
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: CDKText(
                  'No level selected.\nSelect a Level to edit its zones.',
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
    final zoneRows = _buildZoneRows(level);
    final Set<int> multiSelectedZoneIndices = appData.selectedZoneIndices
        .where((index) => index >= 0 && index < level.zones.length)
        .toSet();
    final zoneTypes = _zoneTypes(appData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              CDKText(
                'Level Zones',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'Zones are named rectangular areas within a level used to trigger events or define regions such as spawn points, triggers, or boundaries.',
              ),
              const Spacer(),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: zoneTypes.isEmpty
                    ? null
                    : () async {
                        await _promptAndAddZone();
                      },
                child: const Text('+ Zone'),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Center(
            child: CDKButton(
              key: _zoneTypesAnchorKey,
              style: CDKButtonStyle.normal,
              onPressed: () async {
                await _showZoneTypesPopover(appData);
              },
              child: const Text('Edit Categories'),
            ),
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
                itemCount: zoneRows.length,
                onReorder: (oldIndex, newIndex) =>
                    _onReorder(appData, zoneRows, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final _ZoneListRow row = zoneRows[index];
                  if (row.isGroup) {
                    final GameZoneGroup group = row.group!;
                    final GlobalKey groupActionsAnchorKey =
                        _groupActionsAnchorKey(group.id);
                    return Container(
                      key: ValueKey('zone-group-${group.id}'),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CDKText(
                                      group.name,
                                      role: CDKTextRole.body,
                                      style: listItemTitleStyle,
                                    ),
                                    if (group.id == GameZoneGroup.mainId) ...[
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
                              ],
                            ),
                          ),
                          CupertinoButton(
                            key: groupActionsAnchorKey,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
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

                  final int zoneIndex = row.zoneIndex!;
                  final bool isSelected =
                      multiSelectedZoneIndices.contains(zoneIndex) ||
                          zoneIndex == appData.selectedZone;
                  final GameZone zone = row.zone!;
                  final String zoneColorName = _zoneColorName(appData, zone);
                  final bool hiddenByCollapse = row.hiddenByCollapse;
                  return AnimatedSize(
                    key: ValueKey('zone-item-$zoneIndex'),
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
                            onTap: () => _selectZone(
                              appData,
                              zoneIndex,
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
                                  Container(
                                    width: 15,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      color: LayoutUtils.getColorFromName(
                                        zoneColorName,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CDKText(
                                          _zoneDisplayName(zone, zoneIndex),
                                          role: CDKTextRole.body,
                                          style: listItemTitleStyle,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        CDKText(
                                          'Category: ${zone.type}',
                                          role: CDKTextRole.caption,
                                          color: cdkColors.colorText
                                              .withValues(alpha: 0.72),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
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

enum _ZoneListRowType { group, zone }

class _ZoneListRow {
  const _ZoneListRow._({
    required this.type,
    required this.groupId,
    this.group,
    this.zone,
    this.zoneIndex,
    this.hiddenByCollapse = false,
  });

  factory _ZoneListRow.group({
    required GameZoneGroup group,
  }) {
    return _ZoneListRow._(
      type: _ZoneListRowType.group,
      groupId: group.id,
      group: group,
    );
  }

  factory _ZoneListRow.zone({
    required String groupId,
    required GameZone zone,
    required int zoneIndex,
    bool hiddenByCollapse = false,
  }) {
    return _ZoneListRow._(
      type: _ZoneListRowType.zone,
      groupId: groupId,
      zone: zone,
      zoneIndex: zoneIndex,
      hiddenByCollapse: hiddenByCollapse,
    );
  }

  final _ZoneListRowType type;
  final String groupId;
  final GameZoneGroup? group;
  final GameZone? zone;
  final int? zoneIndex;
  final bool hiddenByCollapse;

  bool get isGroup => type == _ZoneListRowType.group;
  bool get isZone => type == _ZoneListRowType.zone;
}

class _ZoneDialogData {
  const _ZoneDialogData({
    required this.name,
    required this.type,
    required this.gameplayData,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.groupId,
  });

  final String name;
  final String type;
  final String gameplayData;
  final int x;
  final int y;
  final int width;
  final int height;
  final String groupId;
}

class _ZoneFormDialog extends StatefulWidget {
  const _ZoneFormDialog({
    super.key,
    required this.title,
    required this.mode,
    required this.initialData,
    required this.zoneTypes,
    required this.groupOptions,
    required this.showGroupSelector,
    required this.groupFieldLabel,
    this.onLiveChanged,
    this.onClose,
    this.minWidth = 360,
    this.maxWidth = 500,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
  });

  final String title;
  final EditorEntityFormMode mode;
  final _ZoneDialogData initialData;
  final List<GameZoneType> zoneTypes;
  final List<GameZoneGroup> groupOptions;
  final bool showGroupSelector;
  final String groupFieldLabel;
  final Future<void> Function(_ZoneDialogData value)? onLiveChanged;
  final VoidCallback? onClose;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<_ZoneDialogData> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  State<_ZoneFormDialog> createState() => _ZoneFormDialogState();
}

class _ZoneFormDialogState extends State<_ZoneFormDialog> {
  final GlobalKey _typePickerAnchorKey = GlobalKey();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialData.name,
  );
  late final TextEditingController _xController = TextEditingController(
    text: widget.initialData.x.toString(),
  );
  late final TextEditingController _gameplayDataController =
      TextEditingController(
    text: widget.initialData.gameplayData,
  );
  late final TextEditingController _yController = TextEditingController(
    text: widget.initialData.y.toString(),
  );
  late final TextEditingController _widthController = TextEditingController(
    text: widget.initialData.width.toString(),
  );
  late final TextEditingController _heightController = TextEditingController(
    text: widget.initialData.height.toString(),
  );
  late String _selectedType = _resolveInitialType();
  late String _selectedGroupId = _resolveInitialGroupId();
  EditSession<_ZoneDialogData>? _editSession;

  bool _didInitialDataChange(_ZoneDialogData previous, _ZoneDialogData next) {
    return previous.name != next.name ||
        previous.type != next.type ||
        previous.gameplayData != next.gameplayData ||
        previous.x != next.x ||
        previous.y != next.y ||
        previous.width != next.width ||
        previous.height != next.height ||
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

  String _resolveInitialType() {
    if (widget.zoneTypes.any((type) => type.name == widget.initialData.type)) {
      return widget.initialData.type;
    }
    if (widget.zoneTypes.isNotEmpty) {
      return widget.zoneTypes.first.name;
    }
    return '';
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
    return GameZoneGroup.mainId;
  }

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _selectedType.trim().isNotEmpty &&
      widget.zoneTypes.isNotEmpty;

  _ZoneDialogData _currentData() {
    return _ZoneDialogData(
      name: _nameController.text.trim(),
      type: _selectedType,
      gameplayData: _gameplayDataController.text,
      x: int.tryParse(_xController.text.trim()) ?? 0,
      y: int.tryParse(_yController.text.trim()) ?? 0,
      width: int.tryParse(_widthController.text.trim()) ?? 50,
      height: int.tryParse(_heightController.text.trim()) ?? 50,
      groupId: _selectedGroupId,
    );
  }

  String? _validateData(_ZoneDialogData data) {
    if (data.name.trim().isEmpty) {
      return 'Name is required.';
    }
    if (data.type.trim().isEmpty || widget.zoneTypes.isEmpty) {
      return 'Category is required.';
    }
    return null;
  }

  void _onInputChanged() {
    if (mounted) {
      setState(() {});
    }
    queueEditorLiveEditUpdate(
      mode: widget.mode,
      session: _editSession,
      value: _currentData(),
    );
  }

  GameZoneType? _selectedZoneType() {
    for (final type in widget.zoneTypes) {
      if (type.name == _selectedType) {
        return type;
      }
    }
    return null;
  }

  Future<void> _showTypePickerPopover() async {
    if (widget.zoneTypes.isEmpty || Overlay.maybeOf(context) == null) {
      return;
    }
    final CDKDialogController controller = CDKDialogController();
    CDKDialogsManager.showPopoverArrowed(
      context: context,
      anchorKey: _typePickerAnchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: _ZoneTypePickerPopover(
        zoneTypes: widget.zoneTypes,
        selectedType: _selectedType,
        onSelected: (typeName) {
          setState(() {
            _selectedType = typeName;
          });
          _onInputChanged();
          controller.close();
        },
      ),
    );
  }

  void _confirm() {
    if (!_isValid) {
      return;
    }
    widget.onConfirm(
      _ZoneDialogData(
        name: _nameController.text.trim(),
        type: _selectedType,
        gameplayData: _gameplayDataController.text,
        x: int.tryParse(_xController.text.trim()) ?? 0,
        y: int.tryParse(_yController.text.trim()) ?? 0,
        width: int.tryParse(_widthController.text.trim()) ?? 50,
        height: int.tryParse(_heightController.text.trim()) ?? 50,
        groupId: _selectedGroupId,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _editSession = createEditorLiveEditSession<_ZoneDialogData>(
      mode: widget.mode,
      initialValue: _currentData(),
      validate: _validateData,
      onPersist: widget.onLiveChanged,
      areEqual: (a, b) =>
          a.name == b.name &&
          a.type == b.type &&
          a.gameplayData == b.gameplayData &&
          a.x == b.x &&
          a.y == b.y &&
          a.width == b.width &&
          a.height == b.height &&
          a.groupId == b.groupId,
    );
  }

  @override
  void didUpdateWidget(covariant _ZoneFormDialog oldWidget) {
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
        _widthController,
        widget.initialData.width.toString(),
      );
      _setControllerTextIfNeeded(
        _heightController,
        widget.initialData.height.toString(),
      );
    }

    if (initialDataChanged ||
        !widget.zoneTypes.any((t) => t.name == _selectedType)) {
      final String nextType = _resolveInitialType();
      if (_selectedType != nextType) {
        _selectedType = nextType;
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
    _xController.dispose();
    _gameplayDataController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final GameZoneType? selectedType = _selectedZoneType();
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
              title: 'Delete zone',
              message: 'Delete this zone? This cannot be undone.',
            ),
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabeledField(
            label: 'Name',
            child: CDKFieldText(
              placeholder: 'Zone name',
              controller: _nameController,
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
          EditorLabeledField(
            label: 'Zone Category',
            child: Align(
              alignment: Alignment.centerLeft,
              child: CDKButton(
                key: _typePickerAnchorKey,
                style: CDKButtonStyle.normal,
                enabled: widget.zoneTypes.isNotEmpty,
                onPressed: _showTypePickerPopover,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedType != null) ...[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: LayoutUtils.getColorFromName(
                            selectedType.color,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: CDKText(
                        selectedType?.name ?? 'Select a category',
                        role: CDKTextRole.caption,
                        color: cdkColors.colorText,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 14,
                      color: cdkColors.colorText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: EditorLabeledField(
                  label: 'X (px)',
                  child: CDKFieldText(
                    placeholder: 'X (px)',
                    controller: _xController,
                    keyboardType: TextInputType.number,
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
              SizedBox(width: spacing.sm),
              Expanded(
                child: EditorLabeledField(
                  label: 'Y (px)',
                  child: CDKFieldText(
                    placeholder: 'Y (px)',
                    controller: _yController,
                    keyboardType: TextInputType.number,
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
          Row(
            children: [
              Expanded(
                child: EditorLabeledField(
                  label: 'Width (px)',
                  child: CDKFieldText(
                    placeholder: 'Width (px)',
                    controller: _widthController,
                    keyboardType: TextInputType.number,
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
              SizedBox(width: spacing.sm),
              Expanded(
                child: EditorLabeledField(
                  label: 'Height (px)',
                  child: CDKFieldText(
                    placeholder: 'Height (px)',
                    controller: _heightController,
                    keyboardType: TextInputType.number,
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
                              ? GameZoneGroup.defaultMainName
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

class _ZoneTypePickerPopover extends StatelessWidget {
  const _ZoneTypePickerPopover({
    required this.zoneTypes,
    required this.selectedType,
    required this.onSelected,
  });

  final List<GameZoneType> zoneTypes;
  final String selectedType;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      child: Padding(
        padding: EdgeInsets.all(spacing.xs),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: zoneTypes.length,
            itemBuilder: (context, index) {
              final type = zoneTypes[index];
              final bool isSelected = type.name == selectedType;
              return GestureDetector(
                onTap: () => onSelected(type.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  color: isSelected
                      ? CupertinoColors.systemBlue.withValues(alpha: 0.18)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: LayoutUtils.getColorFromName(type.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CDKText(
                          type.name,
                          role: CDKTextRole.caption,
                          color: cdkColors.colorText,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ZoneTypeDraft {
  const _ZoneTypeDraft({
    required this.key,
    required this.name,
    required this.color,
  });

  final String key;
  final String name;
  final String color;

  _ZoneTypeDraft copyWith({
    String? key,
    String? name,
    String? color,
  }) {
    return _ZoneTypeDraft(
      key: key ?? this.key,
      name: name ?? this.name,
      color: color ?? this.color,
    );
  }
}

class _ZoneTypesPopover extends StatefulWidget {
  const _ZoneTypesPopover({
    required this.initialTypes,
    required this.colorPalette,
    required this.usedTypeKeys,
    required this.onTypesChanged,
  });

  final List<_ZoneTypeDraft> initialTypes;
  final List<String> colorPalette;
  final Set<String> usedTypeKeys;
  final ValueChanged<List<_ZoneTypeDraft>> onTypesChanged;

  @override
  State<_ZoneTypesPopover> createState() => _ZoneTypesPopoverState();
}

class _ZoneTypesPopoverState extends State<_ZoneTypesPopover> {
  late final List<_ZoneTypeDraft> _drafts =
      widget.initialTypes.map((item) => item.copyWith()).toList(growable: true);
  late final List<TextEditingController> _nameControllers = _drafts
      .map((draft) => TextEditingController(text: draft.name))
      .toList(growable: true);
  late final List<GlobalKey> _colorAnchorKeys =
      List.generate(_drafts.length, (_) => GlobalKey(), growable: true);
  int _newKeyCounter = 0;

  void _emitChanged() {
    widget.onTypesChanged(
      _drafts.map((item) => item.copyWith()).toList(growable: false),
    );
  }

  void _updateDraft(int index, {String? name, String? color}) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    final _ZoneTypeDraft current = _drafts[index];
    final String nextName = name ?? current.name;
    final String nextColor = color ?? current.color;
    if (nextName == current.name && nextColor == current.color) {
      return;
    }
    setState(() {
      _drafts[index] = current.copyWith(name: nextName, color: nextColor);
    });
    _emitChanged();
  }

  void _addDraft() {
    final int nextNumber = _drafts.length + 1;
    String candidateName = 'Category $nextNumber';
    final Set<String> existingNames = _drafts.map((d) => d.name.trim()).toSet();
    int suffix = nextNumber;
    while (existingNames.contains(candidateName)) {
      suffix++;
      candidateName = 'Category $suffix';
    }
    setState(() {
      _drafts.add(
        _ZoneTypeDraft(
          key: '__new_${_newKeyCounter++}',
          name: candidateName,
          color: widget.colorPalette.first,
        ),
      );
      _nameControllers.add(TextEditingController(text: candidateName));
      _colorAnchorKeys.add(GlobalKey());
    });
    _emitChanged();
  }

  void _deleteDraft(int index) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    setState(() {
      _drafts.removeAt(index);
      _nameControllers[index].dispose();
      _nameControllers.removeAt(index);
      _colorAnchorKeys.removeAt(index);
    });
    _emitChanged();
  }

  void _reorderDrafts(int oldIndex, int newIndex) {
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
    setState(() {
      final _ZoneTypeDraft movedDraft = _drafts.removeAt(oldIndex);
      _drafts.insert(insertIndex, movedDraft);
      final TextEditingController movedController =
          _nameControllers.removeAt(oldIndex);
      _nameControllers.insert(insertIndex, movedController);
      final GlobalKey movedKey = _colorAnchorKeys.removeAt(oldIndex);
      _colorAnchorKeys.insert(insertIndex, movedKey);
    });
    _emitChanged();
  }

  void _showColorPicker(int index) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    final GlobalKey anchorKey = _colorAnchorKeys[index];
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
      child: _ZoneCategoryColorPicker(
        colorPalette: widget.colorPalette,
        selectedColorName: _drafts[index].color,
        onSelected: (String colorName) {
          _updateDraft(index, color: colorName);
          controller.close();
        },
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 380),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CDKText('Zone Categories', role: CDKTextRole.title),
              SizedBox(height: spacing.sm),
              if (_drafts.isEmpty)
                const CDKText(
                  'No zone categories yet.',
                  role: CDKTextRole.caption,
                  secondary: true,
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Localizations.override(
                  context: context,
                  delegates: const [
                    DefaultMaterialLocalizations.delegate,
                    DefaultWidgetsLocalizations.delegate,
                  ],
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _drafts.length,
                    onReorder: _reorderDrafts,
                    itemBuilder: (context, index) {
                      final _ZoneTypeDraft draft = _drafts[index];
                      final bool isUsed =
                          widget.usedTypeKeys.contains(draft.key);
                      return Container(
                        key: ValueKey(draft.key),
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        color: cdkColors.backgroundSecondary0,
                        child: Row(
                          children: [
                            CDKButton(
                              key: _colorAnchorKeys[index],
                              style: CDKButtonStyle.normal,
                              onPressed: () => _showColorPicker(index),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: LayoutUtils.getColorFromName(
                                          draft.color),
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
                            ),
                            SizedBox(width: spacing.xs),
                            Expanded(
                              child: CDKFieldText(
                                placeholder: 'Category name',
                                controller: _nameControllers[index],
                                onChanged: (value) {
                                  final String trimmed = value.trim();
                                  if (trimmed.isNotEmpty) {
                                    _updateDraft(index, name: trimmed);
                                  }
                                },
                              ),
                            ),
                            SizedBox(width: spacing.xs),
                            SizedBox(
                              width: 24,
                              child: isUsed
                                  ? const SizedBox.shrink()
                                  : CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(20, 20),
                                      onPressed: () => _deleteDraft(index),
                                      child: Icon(
                                        CupertinoIcons.minus_circle,
                                        size: 16,
                                        color: cdkColors.colorText,
                                      ),
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
                    },
                  ),
                ),
              ),
              SizedBox(height: spacing.sm),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: _addDraft,
                child: const Text('Add category'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneCategoryColorPicker extends StatelessWidget {
  const _ZoneCategoryColorPicker({
    required this.colorPalette,
    required this.selectedColorName,
    required this.onSelected,
  });

  final List<String> colorPalette;
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
            const CDKText('Color', role: CDKTextRole.caption),
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
