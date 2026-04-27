import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';

enum GroupedListRowType { group, item }

class GroupedListRow<G, I> {
  const GroupedListRow._({
    required this.type,
    required this.groupId,
    this.group,
    this.item,
    this.itemIndex,
    this.hiddenByCollapse = false,
  });

  factory GroupedListRow.group({
    required String groupId,
    required G group,
  }) {
    return GroupedListRow._(
      type: GroupedListRowType.group,
      groupId: groupId,
      group: group,
    );
  }

  factory GroupedListRow.item({
    required String groupId,
    required I item,
    required int itemIndex,
    bool hiddenByCollapse = false,
  }) {
    return GroupedListRow._(
      type: GroupedListRowType.item,
      groupId: groupId,
      item: item,
      itemIndex: itemIndex,
      hiddenByCollapse: hiddenByCollapse,
    );
  }

  final GroupedListRowType type;
  final String groupId;
  final G? group;
  final I? item;
  final int? itemIndex;
  final bool hiddenByCollapse;

  bool get isGroup => type == GroupedListRowType.group;
  bool get isItem => type == GroupedListRowType.item;
}

class GroupedListAlgorithms {
  static List<GroupedListRow<G, I>> buildRows<G, I>({
    required List<G> groups,
    required List<I> items,
    required String mainGroupId,
    required String Function(G group) groupIdOf,
    required bool Function(G group) groupCollapsedOf,
    required String Function(I item) itemGroupIdOf,
  }) {
    final List<GroupedListRow<G, I>> rows = <GroupedListRow<G, I>>[];
    final Set<String> validGroupIds = groups.map(groupIdOf).toSet();
    final Map<String, List<int>> itemIndicesByGroupId = <String, List<int>>{};

    for (int i = 0; i < items.length; i++) {
      final I item = items[i];
      final String rawGroupId = itemGroupIdOf(item).trim();
      final String effectiveGroupId =
          validGroupIds.contains(rawGroupId) ? rawGroupId : mainGroupId;
      itemIndicesByGroupId.putIfAbsent(effectiveGroupId, () => <int>[]).add(i);
    }

    for (final G group in groups) {
      final String groupId = groupIdOf(group);
      rows.add(GroupedListRow<G, I>.group(groupId: groupId, group: group));
      final List<int> indices = itemIndicesByGroupId[groupId] ?? const <int>[];
      for (final int itemIndex in indices) {
        rows.add(
          GroupedListRow<G, I>.item(
            groupId: groupId,
            item: items[itemIndex],
            itemIndex: itemIndex,
            hiddenByCollapse: groupCollapsedOf(group),
          ),
        );
      }
    }

    return rows;
  }

  static int normalizeTargetIndex({
    required int oldIndex,
    required int newIndex,
    required int rowCount,
  }) {
    int next = newIndex;
    if (next < 0) {
      next = 0;
    }
    if (next > rowCount) {
      next = rowCount;
    }
    if (oldIndex < next) {
      next -= 1;
    }
    if (next < 0) {
      next = 0;
    }
    return next;
  }

  static int _firstItemIndexForGroup<I>(
    List<I> items,
    String groupId,
    String Function(I item) effectiveGroupIdOfItem,
  ) {
    for (int i = 0; i < items.length; i++) {
      if (effectiveGroupIdOfItem(items[i]) == groupId) {
        return i;
      }
    }
    return -1;
  }

  static int _lastItemIndexForGroup<I>(
    List<I> items,
    String groupId,
    String Function(I item) effectiveGroupIdOfItem,
  ) {
    for (int i = items.length - 1; i >= 0; i--) {
      if (effectiveGroupIdOfItem(items[i]) == groupId) {
        return i;
      }
    }
    return -1;
  }

  static int _insertionIndexAtGroupStart<G, I>({
    required List<G> groups,
    required List<I> items,
    required String groupId,
    required String Function(G group) groupIdOf,
    required String Function(I item) effectiveGroupIdOfItem,
  }) {
    final int firstInGroup =
        _firstItemIndexForGroup(items, groupId, effectiveGroupIdOfItem);
    if (firstInGroup != -1) {
      return firstInGroup;
    }

    final int groupOrderIndex =
        groups.indexWhere((g) => groupIdOf(g) == groupId);
    if (groupOrderIndex == -1) {
      return items.length;
    }

    for (int i = groupOrderIndex - 1; i >= 0; i--) {
      final int lastPrevious = _lastItemIndexForGroup(
        items,
        groupIdOf(groups[i]),
        effectiveGroupIdOfItem,
      );
      if (lastPrevious != -1) {
        return lastPrevious + 1;
      }
    }

    for (int i = groupOrderIndex + 1; i < groups.length; i++) {
      final int firstNext = _firstItemIndexForGroup(
        items,
        groupIdOf(groups[i]),
        effectiveGroupIdOfItem,
      );
      if (firstNext != -1) {
        return firstNext;
      }
    }

    return items.length;
  }

  static int _insertionIndexAtGroupEnd<G, I>({
    required List<G> groups,
    required List<I> items,
    required String groupId,
    required String Function(G group) groupIdOf,
    required String Function(I item) effectiveGroupIdOfItem,
  }) {
    final int lastInGroup =
        _lastItemIndexForGroup(items, groupId, effectiveGroupIdOfItem);
    if (lastInGroup != -1) {
      return lastInGroup + 1;
    }
    return _insertionIndexAtGroupStart(
      groups: groups,
      items: items,
      groupId: groupId,
      groupIdOf: groupIdOf,
      effectiveGroupIdOfItem: effectiveGroupIdOfItem,
    );
  }

  static void moveGroup<G, I>({
    required List<G> groups,
    required List<GroupedListRow<G, I>> rowsWithoutMovedItem,
    required GroupedListRow<G, I> movedRow,
    required int targetRowIndex,
    required String Function(G group) groupIdOf,
  }) {
    final int movedGroupIndex =
        groups.indexWhere((group) => groupIdOf(group) == movedRow.groupId);
    if (movedGroupIndex == -1) {
      return;
    }

    int insertGroupIndex;
    if (targetRowIndex >= rowsWithoutMovedItem.length) {
      insertGroupIndex = groups.length;
    } else {
      final GroupedListRow<G, I> targetRow =
          rowsWithoutMovedItem[targetRowIndex];
      insertGroupIndex =
          groups.indexWhere((group) => groupIdOf(group) == targetRow.groupId);
      if (insertGroupIndex == -1) {
        insertGroupIndex = groups.length;
      }
    }

    final G movedGroup = groups.removeAt(movedGroupIndex);
    if (movedGroupIndex < insertGroupIndex) {
      insertGroupIndex -= 1;
    }
    insertGroupIndex = insertGroupIndex.clamp(0, groups.length);
    groups.insert(insertGroupIndex, movedGroup);
  }

  static int moveItemAndReturnSelectedIndex<G, I>({
    required List<G> groups,
    required List<I> items,
    required List<GroupedListRow<G, I>> rowsWithoutMovedItem,
    required GroupedListRow<G, I> movedRow,
    required int targetRowIndex,
    required String mainGroupId,
    required String Function(G group) groupIdOf,
    required String Function(I item) effectiveGroupIdOfItem,
    required void Function(I item, String groupId) setItemGroupId,
    required int selectedIndex,
  }) {
    final I? movedItem = movedRow.item;
    if (movedItem == null) {
      return selectedIndex;
    }

    final I? selectedItem = selectedIndex >= 0 && selectedIndex < items.length
        ? items[selectedIndex]
        : null;

    final int currentIndex = items.indexOf(movedItem);
    if (currentIndex == -1) {
      return selectedIndex;
    }
    items.removeAt(currentIndex);

    String targetGroupId = mainGroupId;
    int insertItemIndex = items.length;

    if (rowsWithoutMovedItem.isEmpty) {
      targetGroupId = mainGroupId;
      insertItemIndex = _insertionIndexAtGroupEnd(
        groups: groups,
        items: items,
        groupId: targetGroupId,
        groupIdOf: groupIdOf,
        effectiveGroupIdOfItem: effectiveGroupIdOfItem,
      );
    } else if (targetRowIndex <= 0) {
      final GroupedListRow<G, I> firstRow = rowsWithoutMovedItem.first;
      targetGroupId = firstRow.groupId;
      if (firstRow.isItem) {
        final int targetItemIndex = items.indexOf(firstRow.item as I);
        insertItemIndex = targetItemIndex == -1
            ? _insertionIndexAtGroupStart(
                groups: groups,
                items: items,
                groupId: targetGroupId,
                groupIdOf: groupIdOf,
                effectiveGroupIdOfItem: effectiveGroupIdOfItem,
              )
            : targetItemIndex;
      } else {
        insertItemIndex = _insertionIndexAtGroupStart(
          groups: groups,
          items: items,
          groupId: targetGroupId,
          groupIdOf: groupIdOf,
          effectiveGroupIdOfItem: effectiveGroupIdOfItem,
        );
      }
    } else if (targetRowIndex >= rowsWithoutMovedItem.length) {
      final GroupedListRow<G, I> lastRow = rowsWithoutMovedItem.last;
      targetGroupId = lastRow.groupId;
      if (lastRow.isItem) {
        final int targetItemIndex = items.indexOf(lastRow.item as I);
        insertItemIndex = targetItemIndex == -1
            ? _insertionIndexAtGroupEnd(
                groups: groups,
                items: items,
                groupId: targetGroupId,
                groupIdOf: groupIdOf,
                effectiveGroupIdOfItem: effectiveGroupIdOfItem,
              )
            : targetItemIndex + 1;
      } else {
        insertItemIndex = _insertionIndexAtGroupEnd(
          groups: groups,
          items: items,
          groupId: targetGroupId,
          groupIdOf: groupIdOf,
          effectiveGroupIdOfItem: effectiveGroupIdOfItem,
        );
      }
    } else {
      final GroupedListRow<G, I> targetRow =
          rowsWithoutMovedItem[targetRowIndex];
      if (targetRow.isItem) {
        targetGroupId = targetRow.groupId;
        final int targetItemIndex = items.indexOf(targetRow.item as I);
        insertItemIndex = targetItemIndex == -1
            ? _insertionIndexAtGroupEnd(
                groups: groups,
                items: items,
                groupId: targetGroupId,
                groupIdOf: groupIdOf,
                effectiveGroupIdOfItem: effectiveGroupIdOfItem,
              )
            : targetItemIndex;
      } else {
        bool groupHasItems(String groupId) {
          return items.any((item) => effectiveGroupIdOfItem(item) == groupId);
        }

        targetGroupId = targetRow.groupId;
        if (targetRowIndex > 0) {
          final GroupedListRow<G, I> previousRow =
              rowsWithoutMovedItem[targetRowIndex - 1];
          if (previousRow.isGroup && !groupHasItems(previousRow.groupId)) {
            targetGroupId = previousRow.groupId;
            insertItemIndex = _insertionIndexAtGroupStart(
              groups: groups,
              items: items,
              groupId: targetGroupId,
              groupIdOf: groupIdOf,
              effectiveGroupIdOfItem: effectiveGroupIdOfItem,
            );
          } else if (previousRow.isItem) {
            targetGroupId = previousRow.groupId;
            final int previousItemIndex = items.indexOf(previousRow.item as I);
            insertItemIndex = previousItemIndex == -1
                ? _insertionIndexAtGroupEnd(
                    groups: groups,
                    items: items,
                    groupId: targetGroupId,
                    groupIdOf: groupIdOf,
                    effectiveGroupIdOfItem: effectiveGroupIdOfItem,
                  )
                : previousItemIndex + 1;
          } else {
            insertItemIndex = _insertionIndexAtGroupStart(
              groups: groups,
              items: items,
              groupId: targetGroupId,
              groupIdOf: groupIdOf,
              effectiveGroupIdOfItem: effectiveGroupIdOfItem,
            );
          }
        } else {
          insertItemIndex = _insertionIndexAtGroupStart(
            groups: groups,
            items: items,
            groupId: targetGroupId,
            groupIdOf: groupIdOf,
            effectiveGroupIdOfItem: effectiveGroupIdOfItem,
          );
        }
      }
    }

    if (insertItemIndex < 0 || insertItemIndex > items.length) {
      insertItemIndex = items.length;
    }
    setItemGroupId(movedItem, targetGroupId);
    items.insert(insertItemIndex, movedItem);

    if (selectedItem == null) {
      return -1;
    }
    return items.indexOf(selectedItem);
  }

  static int reassignItemsToGroup<I>({
    required List<I> items,
    required String fromGroupId,
    required String toGroupId,
    required String Function(I item) itemGroupIdOf,
    required void Function(I item, String groupId) setItemGroupId,
  }) {
    int reassignedCount = 0;
    for (final I item in items) {
      if (itemGroupIdOf(item).trim() != fromGroupId) {
        continue;
      }
      setItemGroupId(item, toGroupId);
      reassignedCount += 1;
    }
    return reassignedCount;
  }
}

class GroupedListGroupDraft {
  const GroupedListGroupDraft({
    required this.id,
    required this.name,
    required this.collapsed,
  });

  final String id;
  final String name;
  final bool collapsed;

  GroupedListGroupDraft copyWith({
    String? id,
    String? name,
    bool? collapsed,
  }) {
    return GroupedListGroupDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      collapsed: collapsed ?? this.collapsed,
    );
  }
}

class GroupedListAddGroupPopover extends StatefulWidget {
  const GroupedListAddGroupPopover({
    super.key,
    required this.existingNames,
    required this.onAdd,
    required this.onCancel,
    this.title = 'Add Group',
    this.placeholder = 'Group name',
    this.actionLabel = 'Add group',
  });

  final Iterable<String> existingNames;
  final Future<bool> Function(String name) onAdd;
  final VoidCallback onCancel;
  final String title;
  final String placeholder;
  final String actionLabel;

  @override
  State<GroupedListAddGroupPopover> createState() =>
      _GroupedListAddGroupPopoverState();
}

class _GroupedListAddGroupPopoverState
    extends State<GroupedListAddGroupPopover> {
  final TextEditingController _nameController = TextEditingController();
  String? _error;
  bool _busy = false;

  Set<String> get _normalizedExistingNames {
    return widget.existingNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String nextName = _nameController.text.trim();
    if (nextName.isEmpty) {
      setState(() {
        _error = 'Group name is required.';
      });
      return;
    }
    if (_normalizedExistingNames.contains(nextName.toLowerCase())) {
      setState(() {
        _error = 'A group with this name already exists.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final bool added = await widget.onAdd(nextName);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (!added) {
        _error = 'Could not add group.';
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CDKText(widget.title, role: CDKTextRole.title),
            SizedBox(height: spacing.sm),
            CDKText(
              'Name',
              role: CDKTextRole.caption,
              color: cdkColors.colorText,
            ),
            const SizedBox(height: 4),
            CDKFieldText(
              placeholder: widget.placeholder,
              controller: _nameController,
              onChanged: (_) {
                if (_error != null) {
                  setState(() {
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) {
                unawaited(_submit());
              },
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 18,
              child: _error == null
                  ? const SizedBox.shrink()
                  : CDKText(
                      _error!,
                      role: CDKTextRole.caption,
                      color: CDKTheme.red,
                    ),
            ),
            SizedBox(height: spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CDKButton(
                  style: CDKButtonStyle.normal,
                  enabled: !_busy,
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                SizedBox(width: spacing.sm),
                CDKButton(
                  style: CDKButtonStyle.action,
                  enabled: !_busy,
                  onPressed: _submit,
                  child: Text(widget.actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GroupedListEditGroupPopover extends StatefulWidget {
  const GroupedListEditGroupPopover({
    super.key,
    required this.initialName,
    required this.existingNames,
    required this.onRename,
    required this.onCancel,
    this.onDelete,
    this.title = 'Edit Group',
    this.placeholder = 'Group name',
  });

  final String initialName;
  final Iterable<String> existingNames;
  final Future<bool> Function(String name) onRename;
  final Future<bool> Function()? onDelete;
  final VoidCallback onCancel;
  final String title;
  final String placeholder;

  @override
  State<GroupedListEditGroupPopover> createState() =>
      _GroupedListEditGroupPopoverState();
}

class _GroupedListEditGroupPopoverState
    extends State<GroupedListEditGroupPopover> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late String _lastAppliedName = widget.initialName.trim();
  Timer? _renameDebounce;
  String? _queuedName;
  String? _error;
  bool _busy = false;

  Set<String> get _normalizedExistingNames {
    return widget.existingNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  bool _isDuplicateName(String name) {
    return _normalizedExistingNames.contains(name.toLowerCase());
  }

  void _requestRename({required bool immediate}) {
    final String nextName = _nameController.text.trim();
    if (nextName.isEmpty || nextName == _lastAppliedName) {
      _renameDebounce?.cancel();
      return;
    }
    if (_isDuplicateName(nextName)) {
      _renameDebounce?.cancel();
      if (_error != 'A group with this name already exists.') {
        setState(() {
          _error = 'A group with this name already exists.';
        });
      }
      return;
    }

    if (_error != null) {
      setState(() {
        _error = null;
      });
    }

    if (immediate) {
      _renameDebounce?.cancel();
      unawaited(_renameTo(nextName));
      return;
    }
    _renameDebounce?.cancel();
    _renameDebounce = Timer(
      const Duration(milliseconds: 240),
      () => unawaited(_renameTo(nextName)),
    );
  }

  Future<void> _renameTo(String nextName) async {
    if (_busy) {
      _queuedName = nextName;
      return;
    }
    if (nextName.isEmpty || nextName == _lastAppliedName) {
      return;
    }
    if (_isDuplicateName(nextName)) {
      if (_error != 'A group with this name already exists.' && mounted) {
        setState(() {
          _error = 'A group with this name already exists.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    final bool renamed = await widget.onRename(nextName);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (renamed) {
        _lastAppliedName = nextName;
      } else {
        _error = 'Could not update group.';
      }
    });

    final String queuedName = _queuedName ?? _nameController.text.trim();
    _queuedName = null;
    if (queuedName != _lastAppliedName) {
      _requestRename(immediate: true);
    }
  }

  Future<void> _delete() async {
    if (_busy || widget.onDelete == null) {
      return;
    }
    widget.onCancel();
    await widget.onDelete!();
  }

  @override
  void dispose() {
    _renameDebounce?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final double headerToNameSpacing = spacing.sm + 22;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CDKText(widget.title, role: CDKTextRole.title),
                ),
                if (widget.onDelete != null)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(20, 20),
                    onPressed: _busy ? null : _delete,
                    child: const Icon(
                      CupertinoIcons.trash,
                      size: 16,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
              ],
            ),
            SizedBox(height: headerToNameSpacing),
            CDKText(
              'Name',
              role: CDKTextRole.caption,
              color: cdkColors.colorText,
            ),
            const SizedBox(height: 4),
            CDKFieldText(
              placeholder: widget.placeholder,
              controller: _nameController,
              onChanged: (_) {
                _requestRename(immediate: false);
              },
              onSubmitted: (_) {
                _requestRename(immediate: true);
              },
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 18,
              child: _error == null
                  ? const SizedBox.shrink()
                  : CDKText(
                      _error!,
                      role: CDKTextRole.caption,
                      color: CDKTheme.red,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
