import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_media_asset.dart';
import 'game_media_group.dart';
import 'widgets/edit_session.dart';
import 'widgets/editor_entity_form_mode.dart';
import 'widgets/editor_form_dialog_scaffold.dart';
import 'widgets/editor_header_delete_button.dart';
import 'widgets/editor_labeled_field.dart';
import 'widgets/editor_live_edit_session.dart';
import 'widgets/grouped_list.dart';
import 'widgets/section_help_button.dart';

class LayoutMedia extends StatefulWidget {
  const LayoutMedia({super.key});

  @override
  State<LayoutMedia> createState() => _LayoutMediaState();
}

class _LayoutMediaState extends State<LayoutMedia> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _addGroupAnchorKey = GlobalKey();
  final Map<String, GlobalKey> _groupActionsAnchorKeys = <String, GlobalKey>{};
  int _newGroupCounter = 0;
  String? _hoveredGroupId;

  String _resolveMediaPreviewPath(AppData appData, String fileName) {
    if (fileName.isEmpty) {
      return '';
    }
    final bool isAbsolutePath = fileName.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(fileName);
    if (isAbsolutePath) {
      return fileName;
    }
    if (appData.filePath.isEmpty) {
      return fileName;
    }
    return '${appData.filePath}${Platform.pathSeparator}${fileName.replaceAll('/', Platform.pathSeparator)}';
  }

  Future<Size?> _readImageSize(String path) async {
    if (path.isEmpty) {
      return null;
    }
    try {
      final File file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final Size size = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );
      image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<GameMediaGroup> _mediaGroups(AppData appData) {
    if (appData.gameData.mediaGroups.isEmpty) {
      return <GameMediaGroup>[GameMediaGroup.main()];
    }
    final bool hasMain = appData.gameData.mediaGroups
        .any((group) => group.id == GameMediaGroup.mainId);
    if (hasMain) {
      return appData.gameData.mediaGroups;
    }
    return <GameMediaGroup>[
      GameMediaGroup.main(),
      ...appData.gameData.mediaGroups,
    ];
  }

  void _ensureMainGroup(AppData appData) {
    final List<GameMediaGroup> groups = appData.gameData.mediaGroups;
    final int mainIndex =
        groups.indexWhere((group) => group.id == GameMediaGroup.mainId);
    if (mainIndex == -1) {
      groups.insert(0, GameMediaGroup.main());
      return;
    }
    final GameMediaGroup mainGroup = groups[mainIndex];
    final String normalizedName = mainGroup.name.trim().isEmpty
        ? GameMediaGroup.defaultMainName
        : mainGroup.name.trim();
    if (mainGroup.name != normalizedName) {
      mainGroup.name = normalizedName;
    }
  }

  Set<String> _mediaGroupIds(AppData appData) {
    return _mediaGroups(appData).map((group) => group.id).toSet();
  }

  String _effectiveMediaGroupId(AppData appData, GameMediaAsset asset) {
    final String groupId = asset.groupId.trim();
    if (groupId.isNotEmpty && _mediaGroupIds(appData).contains(groupId)) {
      return groupId;
    }
    return GameMediaGroup.mainId;
  }

  GameMediaGroup? _findMediaGroupById(AppData appData, String groupId) {
    for (final group in _mediaGroups(appData)) {
      if (group.id == groupId) {
        return group;
      }
    }
    return null;
  }

  List<_MediaListRow> _buildMediaRows(AppData appData) {
    final List<_MediaListRow> rows = [];
    final List<GameMediaGroup> groups = _mediaGroups(appData);
    final List<GameMediaAsset> assets = appData.gameData.mediaAssets;
    final Set<String> validGroupIds = groups.map((group) => group.id).toSet();

    for (final group in groups) {
      rows.add(_MediaListRow.group(group: group));
      for (int i = 0; i < assets.length; i++) {
        final GameMediaAsset asset = assets[i];
        final String rawGroupId = asset.groupId.trim();
        final String effectiveGroupId = validGroupIds.contains(rawGroupId)
            ? rawGroupId
            : GameMediaGroup.mainId;
        if (effectiveGroupId != group.id) {
          continue;
        }
        rows.add(
          _MediaListRow.asset(
            groupId: effectiveGroupId,
            asset: asset,
            assetIndex: i,
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

  void _setHoveredGroupId(String? groupId) {
    if (_hoveredGroupId == groupId || !mounted) {
      return;
    }
    setState(() {
      _hoveredGroupId = groupId;
    });
  }

  Set<String> _mediaGroupNames(
    AppData appData, {
    String? excludingId,
  }) {
    return _mediaGroups(appData)
        .where((group) => group.id != excludingId)
        .map((group) => group.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  int _firstAssetIndexForGroup(List<GameMediaAsset> assets, String groupId) {
    for (int i = 0; i < assets.length; i++) {
      if (assets[i].groupId == groupId) {
        return i;
      }
    }
    return -1;
  }

  int _lastAssetIndexForGroup(List<GameMediaAsset> assets, String groupId) {
    for (int i = assets.length - 1; i >= 0; i--) {
      if (assets[i].groupId == groupId) {
        return i;
      }
    }
    return -1;
  }

  int _insertionIndexAtGroupStart(
    AppData appData,
    List<GameMediaAsset> assets,
    String groupId,
  ) {
    final int firstInGroup = _firstAssetIndexForGroup(assets, groupId);
    if (firstInGroup != -1) {
      return firstInGroup;
    }

    final int groupOrderIndex =
        _mediaGroups(appData).indexWhere((group) => group.id == groupId);
    if (groupOrderIndex == -1) {
      return assets.length;
    }

    for (int i = groupOrderIndex - 1; i >= 0; i--) {
      final int lastPrevious =
          _lastAssetIndexForGroup(assets, _mediaGroups(appData)[i].id);
      if (lastPrevious != -1) {
        return lastPrevious + 1;
      }
    }

    for (int i = groupOrderIndex + 1; i < _mediaGroups(appData).length; i++) {
      final int firstNext =
          _firstAssetIndexForGroup(assets, _mediaGroups(appData)[i].id);
      if (firstNext != -1) {
        return firstNext;
      }
    }
    return assets.length;
  }

  int _insertionIndexAtGroupEnd(
    AppData appData,
    List<GameMediaAsset> assets,
    String groupId,
  ) {
    final int lastInGroup = _lastAssetIndexForGroup(assets, groupId);
    if (lastInGroup != -1) {
      return lastInGroup + 1;
    }
    return _insertionIndexAtGroupStart(appData, assets, groupId);
  }

  String _newGroupId() {
    return '__group_${DateTime.now().microsecondsSinceEpoch}_${_newGroupCounter++}';
  }

  Future<bool> _upsertMediaGroup(
    AppData appData,
    GroupedListGroupDraft draft,
  ) async {
    final String nextName = draft.name.trim();
    if (nextName.isEmpty) {
      return false;
    }
    if (_mediaGroupNames(appData, excludingId: draft.id)
        .contains(nextName.toLowerCase())) {
      return false;
    }

    await appData.runProjectMutation(
      debugLabel: 'media-group-upsert',
      mutate: () {
        _ensureMainGroup(appData);
        final List<GameMediaGroup> groups = appData.gameData.mediaGroups;
        final int existingIndex =
            groups.indexWhere((group) => group.id == draft.id);
        if (existingIndex != -1) {
          groups[existingIndex].name = nextName;
          return;
        }
        groups.add(
          GameMediaGroup(
            id: draft.id,
            name: nextName,
            collapsed: false,
          ),
        );
      },
    );
    return true;
  }

  Future<bool> _deleteMediaGroup(AppData appData, String groupId) async {
    if (!mounted) {
      return false;
    }
    if (groupId == GameMediaGroup.mainId) {
      return false;
    }

    final GameMediaGroup? group = _findMediaGroupById(appData, groupId);
    if (group == null) {
      return false;
    }

    final int mediaCount = appData.gameData.mediaAssets
        .where((asset) => _effectiveMediaGroupId(appData, asset) == groupId)
        .length;

    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete group',
      message: mediaCount > 0
          ? 'Delete "${group.name}"? $mediaCount media item(s) will be moved to "Main".'
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
      debugLabel: 'media-group-delete',
      mutate: () {
        _ensureMainGroup(appData);
        GroupedListAlgorithms.reassignItemsToGroup<GameMediaAsset>(
          items: appData.gameData.mediaAssets,
          fromGroupId: groupId,
          toGroupId: GameMediaGroup.mainId,
          itemGroupIdOf: (asset) => asset.groupId,
          setItemGroupId: (asset, nextGroupId) {
            asset.groupId = nextGroupId;
          },
        );
        appData.gameData.mediaGroups.removeWhere((item) => item.id == groupId);
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
      anchorKey: _addGroupAnchorKey,
      isAnimated: true,
      animateContentResize: false,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: false,
      controller: controller,
      child: GroupedListAddGroupPopover(
        title: 'Add Media Group',
        existingNames: _mediaGroups(appData).map((group) => group.name),
        onCancel: controller.close,
        onAdd: (name) async {
          final bool added = await _upsertMediaGroup(
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
    GameMediaGroup group,
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
        existingNames: _mediaGroups(appData)
            .where((candidate) => candidate.id != group.id)
            .map((candidate) => candidate.name),
        onCancel: controller.close,
        onRename: (name) async {
          final bool renamed = await _upsertMediaGroup(
            appData,
            GroupedListGroupDraft(
              id: group.id,
              name: name,
              collapsed: group.collapsed,
            ),
          );
          return renamed;
        },
        onDelete: group.id == GameMediaGroup.mainId
            ? null
            : () async {
                final bool deleted = await _deleteMediaGroup(appData, group.id);
                if (deleted) {
                  controller.close();
                }
                return deleted;
              },
      ),
    );
  }

  void _addMedia({
    required AppData appData,
    required _MediaDialogData data,
  }) {
    _ensureMainGroup(appData);
    final Set<String> validGroupIds = _mediaGroupIds(appData);
    final String targetGroupId = validGroupIds.contains(data.groupId)
        ? data.groupId
        : GameMediaGroup.mainId;
    appData.gameData.mediaAssets.add(
      GameMediaAsset(
        name: data.name,
        fileName: data.fileName,
        mediaType: data.mediaType,
        tileWidth: data.tileWidth,
        tileHeight: data.tileHeight,
        groupId: targetGroupId,
      ),
    );
    appData.selectedMedia = appData.gameData.mediaAssets.length - 1;
  }

  Future<_MediaDialogData?> _promptMediaData({
    required String title,
    required EditorEntityFormMode mode,
    required _MediaDialogData initialData,
    List<GameMediaGroup> groupOptions = const <GameMediaGroup>[],
    bool showGroupSelector = false,
    String groupFieldLabel = 'Media Group',
    GlobalKey? anchorKey,
    bool useArrowedPopover = false,
    Future<void> Function(_MediaDialogData value)? onLiveChanged,
    VoidCallback? onDelete,
  }) async {
    if (Overlay.maybeOf(context) == null) {
      return null;
    }

    final AppData appData = Provider.of<AppData>(context, listen: false);
    final CDKDialogController controller = CDKDialogController();
    final Completer<_MediaDialogData?> completer =
        Completer<_MediaDialogData?>();
    _MediaDialogData? result;

    final dialogChild = _MediaFormDialog(
      title: title,
      mode: mode,
      initialData: initialData,
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

  Future<void> _pickAndPromptAddMedia() async {
    final appData = Provider.of<AppData>(context, listen: false);
    _ensureMainGroup(appData);
    appData.selectedMedia = -1;
    appData.update();
    final String fileName = await appData.pickImageFile();
    if (!mounted || fileName.isEmpty) {
      return;
    }

    final String previewPath = _resolveMediaPreviewPath(appData, fileName);
    final Size? imageSize = await _readImageSize(previewPath);
    if (!mounted) {
      return;
    }
    final int defaultWidth = (() {
      final int value = imageSize?.width.toInt() ?? 32;
      return value < 1 ? 1 : value;
    })();
    final int defaultHeight = (() {
      final int value = imageSize?.height.toInt() ?? 32;
      return value < 1 ? 1 : value;
    })();

    final _MediaDialogData? data = await _promptMediaData(
      title: 'New media',
      mode: EditorEntityFormMode.add,
      initialData: _MediaDialogData(
        name: GameMediaAsset.inferNameFromFileName(fileName),
        fileName: fileName,
        mediaType: 'tileset',
        tileWidth: defaultWidth,
        tileHeight: defaultHeight,
        previewPath: previewPath,
        groupId: GameMediaGroup.mainId,
      ),
      groupOptions: _mediaGroups(appData),
      showGroupSelector: true,
      groupFieldLabel: 'Media Group',
    );

    if (!mounted || data == null) {
      return;
    }

    await appData.runProjectMutation(
      debugLabel: 'media-add',
      mutate: () {
        _addMedia(appData: appData, data: data);
      },
    );
  }

  void _selectMedia(AppData appData, int index, bool isSelected) {
    appData.selectedMedia = isSelected ? -1 : index;
    appData.update();
  }

  Future<bool> confirmAndDeleteSelectedMediaFromKeyboard(
    AppData appData,
  ) async {
    final int index = appData.selectedMedia;
    final List<GameMediaAsset> assets = appData.gameData.mediaAssets;
    if (index < 0 || index >= assets.length || !mounted) {
      return false;
    }

    final String fileName = assets[index].fileName;
    int mediaAssets = 0;
    int animations = 0;
    int layers = 0;
    int sprites = 0;

    for (int i = 0; i < assets.length; i++) {
      if (i == index) {
        continue;
      }
      if (assets[i].fileName == fileName) {
        mediaAssets += 1;
      }
    }
    for (final animation in appData.gameData.animations) {
      if (animation.mediaFile == fileName) {
        animations += 1;
      }
    }
    for (final level in appData.gameData.levels) {
      for (final layer in level.layers) {
        if (layer.tilesSheetFile == fileName) {
          layers += 1;
        }
      }
      for (final sprite in level.sprites) {
        if (sprite.imageFile == fileName) {
          sprites += 1;
        }
      }
    }

    final int totalRefs = mediaAssets + animations + layers + sprites;
    String message = 'Delete this media item? This cannot be undone.';
    if (totalRefs > 0) {
      final List<String> references = <String>[];
      if (mediaAssets > 0) {
        references.add('$mediaAssets other media item(s)');
      }
      if (animations > 0) {
        references.add('$animations animation(s)');
      }
      if (layers > 0) {
        references.add('$layers layer(s)');
      }
      if (sprites > 0) {
        references.add('$sprites sprite(s)');
      }
      message =
          'This file is still used by ${references.join(', ')}. Delete this media entry anyway? The file will only be removed from disk when no references remain.';
    }

    final bool? confirmed = await CDKDialogsManager.showConfirm(
      context: context,
      title: 'Delete media',
      message: message,
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
      showBackgroundShade: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }

    await appData.runProjectMutation(
      debugLabel: 'media-delete',
      mutate: () {
        if (index < 0 || index >= appData.gameData.mediaAssets.length) {
          return;
        }
        appData.gameData.mediaAssets.removeAt(index);
        appData.selectedMedia = -1;
      },
    );
    await appData.deleteProjectMediaFileIfUnreferenced(fileName);
    return true;
  }

  Future<void> _toggleGroupCollapsed(AppData appData, String groupId) async {
    await appData.runProjectMutation(
      debugLabel: 'media-group-toggle-collapse',
      mutate: () {
        _ensureMainGroup(appData);
        final List<GameMediaGroup> groups = appData.gameData.mediaGroups;
        final int index = groups.indexWhere((group) => group.id == groupId);
        if (index == -1) {
          return;
        }
        final GameMediaGroup group = groups[index];
        group.collapsed = !group.collapsed;
        if (group.collapsed &&
            appData.selectedMedia >= 0 &&
            appData.selectedMedia < appData.gameData.mediaAssets.length &&
            _effectiveMediaGroupId(
                  appData,
                  appData.gameData.mediaAssets[appData.selectedMedia],
                ) ==
                groupId) {
          appData.selectedMedia = -1;
        }
      },
    );
  }

  void _moveGroup({
    required AppData appData,
    required List<_MediaListRow> rowsWithoutMovedItem,
    required _MediaListRow movedRow,
    required int targetRowIndex,
  }) {
    final List<GameMediaGroup> groups = appData.gameData.mediaGroups;
    final int movedGroupIndex =
        groups.indexWhere((group) => group.id == movedRow.groupId);
    if (movedGroupIndex == -1) {
      return;
    }

    int insertGroupIndex;
    if (targetRowIndex >= rowsWithoutMovedItem.length) {
      insertGroupIndex = groups.length;
    } else {
      final _MediaListRow targetRow = rowsWithoutMovedItem[targetRowIndex];
      insertGroupIndex =
          groups.indexWhere((group) => group.id == targetRow.groupId);
      if (insertGroupIndex == -1) {
        insertGroupIndex = groups.length;
      }
    }

    final GameMediaGroup movedGroup = groups.removeAt(movedGroupIndex);
    if (movedGroupIndex < insertGroupIndex) {
      insertGroupIndex -= 1;
    }
    insertGroupIndex = insertGroupIndex.clamp(0, groups.length);
    groups.insert(insertGroupIndex, movedGroup);
  }

  void _moveMediaAsset({
    required AppData appData,
    required List<_MediaListRow> rowsWithoutMovedItem,
    required _MediaListRow movedRow,
    required int targetRowIndex,
  }) {
    final List<GameMediaAsset> assets = appData.gameData.mediaAssets;
    final GameMediaAsset? movedAsset = movedRow.asset;
    if (movedAsset == null) {
      return;
    }

    final GameMediaAsset? selectedAsset =
        appData.selectedMedia >= 0 && appData.selectedMedia < assets.length
            ? assets[appData.selectedMedia]
            : null;

    final int currentIndex = assets.indexOf(movedAsset);
    if (currentIndex == -1) {
      return;
    }
    assets.removeAt(currentIndex);

    String targetGroupId = GameMediaGroup.mainId;
    int insertAssetIndex = assets.length;

    if (rowsWithoutMovedItem.isEmpty) {
      targetGroupId = GameMediaGroup.mainId;
      insertAssetIndex =
          _insertionIndexAtGroupEnd(appData, assets, targetGroupId);
    } else if (targetRowIndex <= 0) {
      final _MediaListRow firstRow = rowsWithoutMovedItem.first;
      targetGroupId = firstRow.groupId;
      if (firstRow.isAsset) {
        final int targetAssetIndex = assets.indexOf(firstRow.asset!);
        insertAssetIndex = targetAssetIndex == -1
            ? _insertionIndexAtGroupStart(appData, assets, targetGroupId)
            : targetAssetIndex;
      } else {
        insertAssetIndex =
            _insertionIndexAtGroupStart(appData, assets, targetGroupId);
      }
    } else if (targetRowIndex >= rowsWithoutMovedItem.length) {
      final _MediaListRow lastRow = rowsWithoutMovedItem.last;
      targetGroupId = lastRow.groupId;
      if (lastRow.isAsset) {
        final int targetAssetIndex = assets.indexOf(lastRow.asset!);
        insertAssetIndex = targetAssetIndex == -1
            ? _insertionIndexAtGroupEnd(appData, assets, targetGroupId)
            : targetAssetIndex + 1;
      } else {
        insertAssetIndex =
            _insertionIndexAtGroupEnd(appData, assets, targetGroupId);
      }
    } else {
      final _MediaListRow targetRow = rowsWithoutMovedItem[targetRowIndex];
      if (targetRow.isAsset) {
        targetGroupId = targetRow.groupId;
        final int targetAssetIndex = assets.indexOf(targetRow.asset!);
        insertAssetIndex = targetAssetIndex == -1
            ? _insertionIndexAtGroupEnd(appData, assets, targetGroupId)
            : targetAssetIndex;
      } else {
        bool groupHasAssets(String groupId) {
          return assets.any(
            (asset) => _effectiveMediaGroupId(appData, asset) == groupId,
          );
        }

        targetGroupId = targetRow.groupId;
        final bool targetGroupHasAssets = groupHasAssets(targetGroupId);
        if (targetRowIndex > 0) {
          final _MediaListRow previousRow =
              rowsWithoutMovedItem[targetRowIndex - 1];
          if (previousRow.isGroup && !groupHasAssets(previousRow.groupId)) {
            targetGroupId = previousRow.groupId;
            insertAssetIndex =
                _insertionIndexAtGroupStart(appData, assets, targetGroupId);
          } else if (previousRow.isAsset && targetGroupHasAssets) {
            targetGroupId = previousRow.groupId;
            final int previousAssetIndex = assets.indexOf(previousRow.asset!);
            insertAssetIndex = previousAssetIndex == -1
                ? _insertionIndexAtGroupEnd(appData, assets, targetGroupId)
                : previousAssetIndex + 1;
          } else {
            insertAssetIndex =
                _insertionIndexAtGroupStart(appData, assets, targetGroupId);
          }
        } else {
          insertAssetIndex =
              _insertionIndexAtGroupStart(appData, assets, targetGroupId);
        }
      }
    }

    if (insertAssetIndex < 0 || insertAssetIndex > assets.length) {
      insertAssetIndex = assets.length;
    }
    movedAsset.groupId = targetGroupId;
    assets.insert(insertAssetIndex, movedAsset);

    if (selectedAsset == null) {
      appData.selectedMedia = -1;
      return;
    }
    appData.selectedMedia = assets.indexOf(selectedAsset);
  }

  void _onReorder(
    AppData appData,
    List<_MediaListRow> rows,
    int oldIndex,
    int newIndex,
  ) {
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

    final List<_MediaListRow> rowsWithoutMovedItem =
        List<_MediaListRow>.from(rows);
    final _MediaListRow movedRow = rowsWithoutMovedItem.removeAt(oldIndex);
    if (newIndex > rowsWithoutMovedItem.length) {
      newIndex = rowsWithoutMovedItem.length;
    }

    unawaited(
      appData.runProjectMutation(
        debugLabel: 'media-reorder',
        mutate: () {
          _ensureMainGroup(appData);
          if (movedRow.isGroup) {
            _moveGroup(
              appData: appData,
              rowsWithoutMovedItem: rowsWithoutMovedItem,
              movedRow: movedRow,
              targetRowIndex: newIndex,
            );
          } else {
            _moveMediaAsset(
              appData: appData,
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
    );

    if (appData.selectedProject == null) {
      return const Center(
        child: CDKText(
          'Select a project to manage media.',
          role: CDKTextRole.body,
          secondary: true,
        ),
      );
    }

    final assets = appData.gameData.mediaAssets;
    final mediaRows = _buildMediaRows(appData);

    if (appData.selectedMedia >= assets.length) {
      appData.selectedMedia = assets.isEmpty ? -1 : assets.length - 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              CDKText(
                'Media',
                role: CDKTextRole.title,
                style: sectionTitleStyle,
              ),
              const SizedBox(width: 6),
              const SectionHelpButton(
                message:
                    'Media holds all imported assets: images, spritesheets, and tilesets. Add files here before using them in other sections.',
              ),
              const Spacer(),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: () async {
                  await _pickAndPromptAddMedia();
                },
                child: const Text('+ Media'),
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
          child: mediaRows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: CDKText(
                    '(No media uploaded yet)',
                    role: CDKTextRole.caption,
                    secondary: true,
                  ),
                )
              : CupertinoScrollbar(
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
                      itemCount: mediaRows.length,
                      onReorder: (oldIndex, newIndex) =>
                          _onReorder(appData, mediaRows, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final _MediaListRow row = mediaRows[index];
                        if (row.isGroup) {
                          final GameMediaGroup group = row.group!;
                          final bool showGroupActions =
                              _hoveredGroupId == group.id;
                          final GlobalKey groupActionsAnchorKey =
                              _groupActionsAnchorKey(group.id);
                          return MouseRegion(
                            key: ValueKey('media-group-hover-${group.id}'),
                            onEnter: (_) => _setHoveredGroupId(group.id),
                            onExit: (_) {
                              if (_hoveredGroupId == group.id) {
                                _setHoveredGroupId(null);
                              }
                            },
                            child: Container(
                              key: ValueKey('media-group-${group.id}'),
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
                                            GameMediaGroup.mainId) ...[
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

                        final GameMediaAsset asset = row.asset!;
                        final int assetIndex = row.assetIndex!;
                        final bool isSelected =
                            assetIndex == appData.selectedMedia;
                        final String subtitle = switch (asset.mediaType) {
                          'tileset' => 'Tileset',
                          'spritesheet' => 'Spritesheet',
                          'atlas' => 'Atlas',
                          _ => 'Image',
                        };
                        final bool hiddenByCollapse = row.hiddenByCollapse;
                        return AnimatedSize(
                          key: ValueKey(asset.fileName + index.toString()),
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
                                  onTap: () => _selectMedia(
                                    appData,
                                    assetIndex,
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
                                        Icon(
                                          switch (asset.mediaType) {
                                            'tileset' =>
                                              CupertinoIcons.square_grid_2x2,
                                            'spritesheet' =>
                                              CupertinoIcons.film,
                                            'atlas' =>
                                              CupertinoIcons.rectangle_grid_2x2,
                                            _ => CupertinoIcons.photo,
                                          },
                                          size: 16,
                                          color: cdkColors.colorText,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CDKText(
                                                asset.name,
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
                                        if (isSelected)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: CupertinoButton(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                  ),
                                                  minimumSize:
                                                      const Size(20, 20),
                                                  onPressed: () async {
                                                    await appData
                                                        .reloadMediaFile(
                                                      asset.fileName,
                                                    );
                                                  },
                                                  child: Icon(
                                                    CupertinoIcons
                                                        .arrow_clockwise,
                                                    size: 16,
                                                    color: cdkColors.colorText,
                                                  ),
                                                ),
                                              ),
                                            ],
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

enum _MediaListRowType { group, asset }

class _MediaListRow {
  const _MediaListRow._({
    required this.type,
    required this.groupId,
    this.group,
    this.asset,
    this.assetIndex,
    this.hiddenByCollapse = false,
  });

  factory _MediaListRow.group({
    required GameMediaGroup group,
  }) {
    return _MediaListRow._(
      type: _MediaListRowType.group,
      groupId: group.id,
      group: group,
    );
  }

  factory _MediaListRow.asset({
    required String groupId,
    required GameMediaAsset asset,
    required int assetIndex,
    bool hiddenByCollapse = false,
  }) {
    return _MediaListRow._(
      type: _MediaListRowType.asset,
      groupId: groupId,
      asset: asset,
      assetIndex: assetIndex,
      hiddenByCollapse: hiddenByCollapse,
    );
  }

  final _MediaListRowType type;
  final String groupId;
  final GameMediaGroup? group;
  final GameMediaAsset? asset;
  final int? assetIndex;
  final bool hiddenByCollapse;

  bool get isGroup => type == _MediaListRowType.group;
  bool get isAsset => type == _MediaListRowType.asset;
}

class _MediaDialogData {
  const _MediaDialogData({
    required this.name,
    required this.fileName,
    required this.mediaType,
    required this.tileWidth,
    required this.tileHeight,
    required this.previewPath,
    required this.groupId,
  });

  final String name;
  final String fileName;
  final String mediaType;
  final int tileWidth;
  final int tileHeight;
  final String previewPath;
  final String groupId;
}

class MediaInlineEditPanel extends StatefulWidget {
  const MediaInlineEditPanel({
    super.key,
    required this.mediaIndex,
  });

  final int mediaIndex;

  @override
  State<MediaInlineEditPanel> createState() => _MediaInlineEditPanelState();
}

class _MediaInlineEditPanelState extends State<MediaInlineEditPanel> {
  late final String _undoGroupKey =
      'media-inline-${DateTime.now().microsecondsSinceEpoch}';

  _MediaDeleteUsage _deleteUsageForFileName(
    AppData appData,
    String fileName, {
    required int excludingMediaIndex,
  }) {
    int mediaAssets = 0;
    int animations = 0;
    int layers = 0;
    int sprites = 0;

    for (int i = 0; i < appData.gameData.mediaAssets.length; i++) {
      if (i == excludingMediaIndex) {
        continue;
      }
      if (appData.gameData.mediaAssets[i].fileName == fileName) {
        mediaAssets += 1;
      }
    }
    for (final animation in appData.gameData.animations) {
      if (animation.mediaFile == fileName) {
        animations += 1;
      }
    }
    for (final level in appData.gameData.levels) {
      for (final layer in level.layers) {
        if (layer.tilesSheetFile == fileName) {
          layers += 1;
        }
      }
      for (final sprite in level.sprites) {
        if (sprite.imageFile == fileName) {
          sprites += 1;
        }
      }
    }

    return _MediaDeleteUsage(
      mediaAssets: mediaAssets,
      animations: animations,
      layers: layers,
      sprites: sprites,
    );
  }

  Future<void> _deleteMedia(AppData appData, int index) async {
    final List<GameMediaAsset> assets = appData.gameData.mediaAssets;
    if (index < 0 || index >= assets.length) {
      return;
    }
    final String fileName = assets[index].fileName;
    final _MediaDeleteUsage usage = _deleteUsageForFileName(
      appData,
      fileName,
      excludingMediaIndex: index,
    );

    if (usage.total > 0 && mounted) {
      final List<String> references = <String>[];
      if (usage.mediaAssets > 0) {
        references.add('${usage.mediaAssets} other media item(s)');
      }
      if (usage.animations > 0) {
        references.add('${usage.animations} animation(s)');
      }
      if (usage.layers > 0) {
        references.add('${usage.layers} layer(s)');
      }
      if (usage.sprites > 0) {
        references.add('${usage.sprites} sprite(s)');
      }
      final bool? confirmed = await CDKDialogsManager.showConfirm(
        context: context,
        title: 'Delete media',
        message:
            'This file is still used by ${references.join(', ')}. Delete this media entry anyway? The file will only be removed from disk when no references remain.',
        confirmLabel: 'Delete',
        cancelLabel: 'Cancel',
        isDestructive: true,
        showBackgroundShade: true,
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    await appData.runProjectMutation(
      debugLabel: 'media-delete',
      mutate: () {
        if (index < 0 || index >= appData.gameData.mediaAssets.length) {
          return;
        }
        appData.gameData.mediaAssets.removeAt(index);
        appData.selectedMedia = -1;
      },
    );
    await appData.deleteProjectMediaFileIfUnreferenced(fileName);
  }

  void _ensureMainGroup(AppData appData) {
    if (appData.gameData.mediaGroups.isEmpty) {
      appData.gameData.mediaGroups.add(GameMediaGroup.main());
      return;
    }
    final List<GameMediaGroup> groups = appData.gameData.mediaGroups;
    final int mainIndex =
        groups.indexWhere((group) => group.id == GameMediaGroup.mainId);
    if (mainIndex == -1) {
      groups.insert(0, GameMediaGroup.main());
      return;
    }
    final GameMediaGroup mainGroup = groups[mainIndex];
    groups.removeAt(mainIndex);
    groups.insert(0, mainGroup);
  }

  List<GameMediaGroup> _mediaGroups(AppData appData) {
    _ensureMainGroup(appData);
    return appData.gameData.mediaGroups;
  }

  String _effectiveMediaGroupId(AppData appData, GameMediaAsset asset) {
    final Set<String> validGroupIds =
        _mediaGroups(appData).map((group) => group.id).toSet();
    final String groupId = asset.groupId.trim();
    if (groupId.isNotEmpty && validGroupIds.contains(groupId)) {
      return groupId;
    }
    return GameMediaGroup.mainId;
  }

  String _resolveMediaPreviewPath(AppData appData, String fileName) {
    if (appData.filePath.isEmpty) {
      return fileName;
    }
    return '${appData.filePath}/${AppData.mediaFolderName}/$fileName';
  }

  Future<void> _applyMediaChange(
    AppData appData,
    _MediaDialogData value, {
    required bool groupedUndo,
  }) async {
    await appData.runProjectMutation(
      debugLabel: groupedUndo ? 'media-inline-live-edit' : 'media-inline-edit',
      undoGroupKey: groupedUndo ? _undoGroupKey : null,
      mutate: () {
        _ensureMainGroup(appData);
        final List<GameMediaAsset> assets = appData.gameData.mediaAssets;
        final int index = widget.mediaIndex;
        if (index < 0 || index >= assets.length) {
          return;
        }
        final GameMediaAsset current = assets[index];
        final Set<String> validGroupIds =
            appData.gameData.mediaGroups.map((group) => group.id).toSet();
        final String targetGroupId = validGroupIds.contains(value.groupId)
            ? value.groupId
            : GameMediaGroup.mainId;
        assets[index] = GameMediaAsset(
          name: value.name,
          fileName: value.fileName,
          mediaType: value.mediaType,
          tileWidth: value.tileWidth,
          tileHeight: value.tileHeight,
          selectionColorHex: current.selectionColorHex,
          groupId: targetGroupId,
        );
        appData.selectedMedia = index;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppData appData = Provider.of<AppData>(context);
    final List<GameMediaAsset> assets = appData.gameData.mediaAssets;
    final int index = widget.mediaIndex;
    if (index < 0 || index >= assets.length) {
      return const SizedBox.shrink();
    }
    final GameMediaAsset asset = assets[index];
    final List<GameMediaGroup> groups = _mediaGroups(appData);
    return _MediaFormDialog(
      title: 'Edit media',
      mode: EditorEntityFormMode.edit,
      initialData: _MediaDialogData(
        name: asset.name,
        fileName: asset.fileName,
        mediaType: asset.mediaType,
        tileWidth: asset.tileWidth,
        tileHeight: asset.tileHeight,
        previewPath: _resolveMediaPreviewPath(appData, asset.fileName),
        groupId: _effectiveMediaGroupId(appData, asset),
      ),
      groupOptions: groups,
      showGroupSelector: true,
      groupFieldLabel: 'Media Group',
      minWidth: 280,
      maxWidth: 360,
      onLiveChanged: (value) async {
        await _applyMediaChange(appData, value, groupedUndo: true);
      },
      onConfirm: (value) {
        unawaited(_applyMediaChange(appData, value, groupedUndo: false));
      },
      onCancel: () {
        appData.selectedMedia = -1;
        appData.update();
      },
      onDelete: () {
        unawaited(_deleteMedia(appData, index));
      },
    );
  }
}

class _MediaDeleteUsage {
  const _MediaDeleteUsage({
    required this.mediaAssets,
    required this.animations,
    required this.layers,
    required this.sprites,
  });

  final int mediaAssets;
  final int animations;
  final int layers;
  final int sprites;

  int get total => mediaAssets + animations + layers + sprites;
}

class _MediaFormDialog extends StatefulWidget {
  const _MediaFormDialog({
    required this.title,
    required this.mode,
    required this.initialData,
    required this.groupOptions,
    required this.showGroupSelector,
    required this.groupFieldLabel,
    this.onLiveChanged,
    this.onClose,
    this.minWidth = 420,
    this.maxWidth = 540,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
  });

  final String title;
  final EditorEntityFormMode mode;
  final _MediaDialogData initialData;
  final List<GameMediaGroup> groupOptions;
  final bool showGroupSelector;
  final String groupFieldLabel;
  final Future<void> Function(_MediaDialogData value)? onLiveChanged;
  final VoidCallback? onClose;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<_MediaDialogData> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  @override
  State<_MediaFormDialog> createState() => _MediaFormDialogState();
}

class _MediaFormDialogState extends State<_MediaFormDialog> {
  static const List<String> _typeValues = [
    'tileset',
    'spritesheet',
    'atlas',
  ];

  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialData.name);
  late final TextEditingController _tileWidthController =
      TextEditingController(text: widget.initialData.tileWidth.toString());
  late final TextEditingController _tileHeightController =
      TextEditingController(text: widget.initialData.tileHeight.toString());
  late String _mediaType = _typeValues.contains(widget.initialData.mediaType)
      ? widget.initialData.mediaType
      : 'tileset';
  late String _selectedGroupId = _resolveInitialGroupId();
  String? _sizeError;
  EditSession<_MediaDialogData>? _editSession;

  String _resolveInitialGroupId() {
    for (final group in widget.groupOptions) {
      if (group.id == widget.initialData.groupId) {
        return group.id;
      }
    }
    if (widget.groupOptions.isNotEmpty) {
      return widget.groupOptions.first.id;
    }
    return GameMediaGroup.mainId;
  }

  bool get _hasTileGrid => _typeValues.contains(_mediaType);

  String get _sizeLabelPrefix {
    switch (_mediaType) {
      case 'spritesheet':
        return 'Frame';
      case 'atlas':
        return 'Tile/Frame';
      default:
        return 'Tile';
    }
  }

  bool get _isValid {
    if (_nameController.text.trim().isEmpty) {
      return false;
    }
    if (!_hasTileGrid) {
      return true;
    }
    final int? width = int.tryParse(_tileWidthController.text.trim());
    final int? height = int.tryParse(_tileHeightController.text.trim());
    return width != null && height != null && width > 0 && height > 0;
  }

  _MediaDialogData _currentData() {
    return _MediaDialogData(
      name: _nameController.text.trim(),
      fileName: widget.initialData.fileName,
      mediaType: _mediaType,
      tileWidth: int.tryParse(_tileWidthController.text.trim()) ?? 32,
      tileHeight: int.tryParse(_tileHeightController.text.trim()) ?? 32,
      previewPath: widget.initialData.previewPath,
      groupId: _selectedGroupId,
    );
  }

  String? _validateData(_MediaDialogData value) {
    if (_nameController.text.trim().isEmpty) {
      return 'Name is required.';
    }
    if (!_hasTileGrid) {
      return null;
    }
    final int? width = int.tryParse(_tileWidthController.text.trim());
    final int? height = int.tryParse(_tileHeightController.text.trim());
    if (width == null || height == null || width <= 0 || height <= 0) {
      return '$_sizeLabelPrefix width and height must be positive integers.';
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

  void _validateTileFields() {
    if (!_hasTileGrid || _isValid) {
      setState(() {
        _sizeError = null;
      });
      _onInputChanged();
      return;
    }
    setState(() {
      _sizeError =
          '$_sizeLabelPrefix width and height must be positive integers.';
    });
    _onInputChanged();
  }

  void _confirm() {
    _validateTileFields();
    if (!_isValid) {
      return;
    }

    widget.onConfirm(
      _MediaDialogData(
        name: _nameController.text.trim(),
        fileName: widget.initialData.fileName,
        mediaType: _mediaType,
        tileWidth: int.tryParse(_tileWidthController.text.trim()) ?? 32,
        tileHeight: int.tryParse(_tileHeightController.text.trim()) ?? 32,
        previewPath: widget.initialData.previewPath,
        groupId: _selectedGroupId,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _editSession = createEditorLiveEditSession<_MediaDialogData>(
      mode: widget.mode,
      initialValue: _currentData(),
      validate: _validateData,
      onPersist: widget.onLiveChanged,
      areEqual: (a, b) =>
          a.name == b.name &&
          a.mediaType == b.mediaType &&
          a.tileWidth == b.tileWidth &&
          a.tileHeight == b.tileHeight &&
          a.groupId == b.groupId,
    );
  }

  @override
  void dispose() {
    if (_editSession != null) {
      unawaited(_editSession!.flush());
      _editSession!.dispose();
    }
    _nameController.dispose();
    _tileWidthController.dispose();
    _tileHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
    final String sizeLabelPrefix = _sizeLabelPrefix;

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
              title: 'Delete media',
              message: 'Delete this media item? This cannot be undone.',
            ),
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabeledField(
            label: 'Name',
            child: CDKFieldText(
              placeholder: 'Media name',
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
            label: 'File',
            child: CDKText(
              widget.initialData.fileName,
              role: CDKTextRole.body,
            ),
          ),
          SizedBox(height: spacing.md),
          EditorLabeledField(
            label: 'Kind',
            child: CDKPickerButtonsSegmented(
              selectedIndex: _typeValues
                  .indexOf(_mediaType)
                  .clamp(0, _typeValues.length - 1),
              options: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: CDKText('Tileset', role: CDKTextRole.caption),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: CDKText('Spritesheet', role: CDKTextRole.caption),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: CDKText('Atlas', role: CDKTextRole.caption),
                ),
              ],
              onSelected: (selectedIndex) {
                setState(() {
                  _mediaType = _typeValues[selectedIndex];
                  if (!_hasTileGrid) {
                    _sizeError = null;
                  }
                });
                _onInputChanged();
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            child: _hasTileGrid
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: spacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: EditorLabeledField(
                              label: '$sizeLabelPrefix Width (px)',
                              child: CDKFieldText(
                                placeholder:
                                    '${sizeLabelPrefix.toLowerCase()} width (px)',
                                controller: _tileWidthController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _validateTileFields(),
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
                              label: '$sizeLabelPrefix Height (px)',
                              child: CDKFieldText(
                                placeholder:
                                    '${sizeLabelPrefix.toLowerCase()} height (px)',
                                controller: _tileHeightController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _validateTileFields(),
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
                      if (_sizeError != null) ...[
                        SizedBox(height: spacing.sm),
                        Text(
                          _sizeError!,
                          style: typography.caption.copyWith(
                            color: CDKTheme.red,
                          ),
                        ),
                      ],
                    ],
                  )
                : const SizedBox.shrink(),
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
                            ? GameMediaGroup.defaultMainName
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
