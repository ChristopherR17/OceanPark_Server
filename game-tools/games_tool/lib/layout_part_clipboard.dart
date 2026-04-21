part of 'layout.dart';

enum _EditorClipboardKind {
  levels,
  layers,
  zones,
  sprites,
  paths,
  media,
  animations,
  tilePattern,
}

class _EditorClipboardPayload {
  const _EditorClipboardPayload({
    required this.kind,
    required this.sourceSection,
    required this.sourceProjectId,
    required this.entries,
    this.sourceLevelIndex,
  });

  final _EditorClipboardKind kind;
  final String sourceSection;
  final String sourceProjectId;
  final int? sourceLevelIndex;
  final List<Map<String, dynamic>> entries;

  int get itemCount => entries.length;
}

class _ClipboardEligibility {
  const _ClipboardEligibility.allow() : reason = null;

  const _ClipboardEligibility.block(this.reason);

  final String? reason;

  bool get isAllowed => reason == null;
}

class _ClipboardBuildResult {
  const _ClipboardBuildResult.success(this.payload) : reason = null;

  const _ClipboardBuildResult.failure(this.reason) : payload = null;

  final _EditorClipboardPayload? payload;
  final String? reason;
}

extension _LayoutClipboard on _LayoutState {
  static const String _clipboardEmptyMessage = 'Clipboard is empty.';

  bool _isClipboardAvailableInSection(String section) {
    return section != 'projects' && section != 'media';
  }

  bool _isTextInputFocused() {
    final BuildContext? focusedContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    if (focusedContext.widget is EditableText) {
      return true;
    }
    return focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  EditableTextState? _focusedEditableTextState() {
    final BuildContext? focusedContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return null;
    }
    final EditableTextState? ancestorState =
        focusedContext.findAncestorStateOfType<EditableTextState>();
    if (ancestorState != null) {
      return ancestorState;
    }
    if (focusedContext is StatefulElement &&
        focusedContext.state is EditableTextState) {
      return focusedContext.state as EditableTextState;
    }
    return null;
  }

  bool _shouldDeferCopyShortcutToTextField() {
    final EditableTextState? state = _focusedEditableTextState();
    if (state == null) {
      return false;
    }
    final TextSelection selection = state.textEditingValue.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  bool _shouldDeferPasteShortcutToTextField(AppData appData) {
    final EditableTextState? state = _focusedEditableTextState();
    if (state == null) {
      return false;
    }
    final _EditorClipboardPayload? payload = _clipboardPayload;
    if (payload == null) {
      return true;
    }
    final _ClipboardEligibility eligibility = _pasteEligibility(appData);
    if (!eligibility.isAllowed) {
      return true;
    }
    final TextSelection selection = state.textEditingValue.selection;
    final bool hasSelection = selection.isValid && !selection.isCollapsed;
    return hasSelection;
  }

  void _showClipboardStatusMessage(
    String message, {
    bool isError = true,
    bool isWarning = false,
  }) {
    _clipboardStatusTimer?.cancel();
    _safeSetState(() {
      _clipboardStatusMessage = message;
      _clipboardStatusIsWarning = isWarning;
      _clipboardStatusIsError = isWarning ? false : isError;
    });
    _clipboardStatusTimer = Timer(const Duration(milliseconds: 2400), () {
      _safeSetState(() {
        _clipboardStatusMessage = '';
        _clipboardStatusIsError = false;
        _clipboardStatusIsWarning = false;
      });
    });
  }

  void _handleCopyShortcut(AppData appData) {
    final _ClipboardEligibility eligibility = _copyEligibility(appData);
    if (!eligibility.isAllowed) {
      _showClipboardStatusMessage(eligibility.reason ?? 'Nothing to copy.');
      return;
    }

    final _ClipboardBuildResult result =
        _buildClipboardPayloadFromSelection(appData);
    if (result.payload == null) {
      _showClipboardStatusMessage(result.reason ?? 'Nothing to copy.');
      return;
    }
    _safeSetState(() {
      _clipboardPayload = result.payload;
      _clipboardStatusMessage = '';
      _clipboardStatusIsError = false;
      _clipboardStatusIsWarning = false;
    });
  }

  Future<void> _handlePasteShortcut(AppData appData) async {
    final _ClipboardEligibility eligibility = _pasteEligibility(appData);
    if (!eligibility.isAllowed) {
      final String message = eligibility.reason ?? 'Cannot paste here.';
      final bool isEmptyClipboard = message == _clipboardEmptyMessage;
      _showClipboardStatusMessage(
        message,
        isError: !isEmptyClipboard,
        isWarning: isEmptyClipboard,
      );
      return;
    }
    final _EditorClipboardPayload? payload = _clipboardPayload;
    if (payload == null) {
      _showClipboardStatusMessage(
        _clipboardEmptyMessage,
        isError: false,
        isWarning: true,
      );
      return;
    }
    final bool applied = await _pasteClipboardPayload(appData, payload);
    if (!applied) {
      _showClipboardStatusMessage('Paste failed.');
      return;
    }
    _safeSetState(() {
      _clipboardStatusMessage = '';
      _clipboardStatusIsError = false;
      _clipboardStatusIsWarning = false;
    });
  }

  void _clearClipboardPayload() {
    _showClipboardStatusMessage(
      _clipboardEmptyMessage,
      isError: false,
      isWarning: true,
    );
    _safeSetState(() {
      _clipboardPayload = null;
    });
  }

  Widget _buildClipboardStatusRow(AppData appData, BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final _ClipboardEligibility copyEligibility = _copyEligibility(appData);
    final _ClipboardEligibility pasteEligibility = _pasteEligibility(appData);
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    final bool isLightTheme = brightness == Brightness.light;

    final bool hasStatusMessage = _clipboardStatusMessage.trim().isNotEmpty;
    final bool showErrorMessage = hasStatusMessage && _clipboardStatusIsError;
    final bool showWarningMessage =
        hasStatusMessage && _clipboardStatusIsWarning;
    final bool isEmptyClipboard =
        !hasStatusMessage && _clipboardPayload == null;
    final bool canClearClipboard = _clipboardPayload != null;
    final String clipboardSummary = hasStatusMessage
        ? _clipboardStatusMessage
        : _clipboardSummaryText(appData);
    final Color chipColor = showErrorMessage
        ? CupertinoColors.systemRed
        : (showWarningMessage
            ? CupertinoColors.systemOrange
            : (isEmptyClipboard
                ? (isLightTheme ? CupertinoColors.black : CupertinoColors.white)
                : cdkColors.colorText));
    final Color chipBackground = showErrorMessage
        ? CupertinoColors.systemRed.withValues(alpha: 0.18)
        : (showWarningMessage
            ? CupertinoColors.systemOrange.withValues(alpha: 0.18)
            : (isLightTheme
                ? CupertinoColors.systemGrey6
                : cdkColors.backgroundSecondary1));
    final Color chipBorder = showErrorMessage
        ? CupertinoColors.systemRed.withValues(alpha: 0.70)
        : (showWarningMessage
            ? CupertinoColors.systemOrange.withValues(alpha: 0.70)
            : (isLightTheme
                ? CupertinoColors.systemGrey4.withValues(alpha: 0.75)
                : cdkColors.colorTextSecondary.withValues(alpha: 0.30)));
    final String pasteTooltip = pasteEligibility.reason == null
        ? 'Paste (${_shortcutLabel("V")})'
        : 'Paste unavailable: ${pasteEligibility.reason}';
    final String copyTooltip = copyEligibility.reason == null
        ? 'Copy (${_shortcutLabel("C")})'
        : 'Copy unavailable: ${copyEligibility.reason}';

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: chipBackground,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: chipBorder),
            ),
            child: Row(
              children: [
                Icon(
                  showErrorMessage || showWarningMessage
                      ? CupertinoIcons.exclamationmark_triangle
                      : CupertinoIcons.doc_text,
                  size: 12,
                  color: chipColor,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: CDKText(
                    clipboardSummary,
                    role: CDKTextRole.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: chipColor,
                  ),
                ),
                if (canClearClipboard) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Clear clipboard',
                    waitDuration: const Duration(milliseconds: 220),
                    child: CupertinoButton(
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      onPressed: _clearClipboardPayload,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 12,
                        color: chipColor.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _buildClipboardActionButton(
          context: context,
          icon: CupertinoIcons.doc_on_doc,
          enabled: copyEligibility.isAllowed,
          tooltip: copyTooltip,
          onPressed: copyEligibility.isAllowed
              ? () => _handleCopyShortcut(appData)
              : null,
        ),
        const SizedBox(width: 4),
        _buildClipboardActionButton(
          context: context,
          icon: CupertinoIcons.doc_on_clipboard,
          enabled: pasteEligibility.isAllowed,
          tooltip: pasteTooltip,
          onPressed: pasteEligibility.isAllowed
              ? () => unawaited(_handlePasteShortcut(appData))
              : null,
        ),
      ],
    );
  }

  Widget _buildClipboardActionButton({
    required BuildContext context,
    required IconData icon,
    required bool enabled,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 220),
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cdkColors.backgroundSecondary1.withValues(
              alpha: enabled ? 1.0 : 0.7,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: cdkColors.colorTextSecondary.withValues(
                alpha: enabled ? 0.35 : 0.20,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 12,
            color: enabled
                ? cdkColors.colorText
                : cdkColors.colorTextSecondary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  _ClipboardEligibility _copyEligibility(AppData appData) {
    final String section = appData.selectedSection;
    if (!_isClipboardAvailableInSection(section)) {
      return _ClipboardEligibility.block(
        'Clipboard is unavailable in ${_sectionLabel(section)}.',
      );
    }
    final _ClipboardBuildResult result = _buildClipboardPayloadFromSelection(
      appData,
      dryRun: true,
    );
    if (result.payload == null) {
      return _ClipboardEligibility.block(
        result.reason ?? 'Nothing selected to copy.',
      );
    }
    return const _ClipboardEligibility.allow();
  }

  _ClipboardEligibility _pasteEligibility(AppData appData) {
    final String section = appData.selectedSection;
    if (!_isClipboardAvailableInSection(section)) {
      return _ClipboardEligibility.block(
        'Clipboard is unavailable in ${_sectionLabel(section)}.',
      );
    }
    final _EditorClipboardPayload? payload = _clipboardPayload;
    if (payload == null) {
      return const _ClipboardEligibility.block(_clipboardEmptyMessage);
    }
    if (payload.entries.isEmpty) {
      return const _ClipboardEligibility.block('Clipboard has no items.');
    }
    if (payload.sourceProjectId.trim().isNotEmpty &&
        payload.sourceProjectId != appData.selectedProjectId) {
      return const _ClipboardEligibility.block(
        'Clipboard data comes from a different project.',
      );
    }

    if (!_isSectionCompatibleWithClipboard(section, payload.kind)) {
      return _ClipboardEligibility.block(
        'Cannot paste ${_clipboardKindLabel(payload.kind)} into ${_sectionLabel(section)}.',
      );
    }

    switch (payload.kind) {
      case _EditorClipboardKind.levels:
        break;
      case _EditorClipboardKind.layers:
      case _EditorClipboardKind.zones:
      case _EditorClipboardKind.sprites:
      case _EditorClipboardKind.paths:
      case _EditorClipboardKind.tilePattern:
        if (!_hasSelectedLevel(appData)) {
          return const _ClipboardEligibility.block(
            'Select a level before pasting.',
          );
        }
        break;
      case _EditorClipboardKind.media:
        final Set<String> existing =
            appData.gameData.mediaAssets.map((item) => item.fileName).toSet();
        for (final entry in payload.entries) {
          final String fileName = (entry['fileName'] as String? ?? '').trim();
          if (fileName.isNotEmpty && existing.contains(fileName)) {
            return _ClipboardEligibility.block(
              'Media "$fileName" already exists.',
            );
          }
        }
        break;
      case _EditorClipboardKind.animations:
        break;
    }
    return const _ClipboardEligibility.allow();
  }

  _ClipboardBuildResult _buildClipboardPayloadFromSelection(
    AppData appData, {
    bool dryRun = false,
  }) {
    final String section = appData.selectedSection;
    final String projectId = appData.selectedProjectId;
    switch (section) {
      case 'levels':
        final int index = appData.selectedLevel;
        if (!_isValidIndex(index, appData.gameData.levels.length)) {
          return const _ClipboardBuildResult.failure('Select a level to copy.');
        }
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.levels,
            sourceSection: section,
            sourceProjectId: projectId,
            entries: <Map<String, dynamic>>[
              appData.gameData.levels[index].toJson(),
            ],
          ),
        );
      case 'layers':
        final GameLevel? level = _selectedLevel(appData);
        if (level == null) {
          return const _ClipboardBuildResult.failure('Select a level first.');
        }
        final List<int> selected = _selectedLayerIndicesForCopy(appData);
        if (selected.isEmpty) {
          return const _ClipboardBuildResult.failure(
              'Select at least one layer.');
        }
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.layers,
            sourceSection: section,
            sourceProjectId: projectId,
            sourceLevelIndex: appData.selectedLevel,
            entries: selected
                .map((index) => level.layers[index].toJson())
                .toList(growable: false),
          ),
        );
      case 'tilemap':
        if (appData.selectedTilePattern.isEmpty) {
          return const _ClipboardBuildResult.failure(
            'Select a tile pattern to copy.',
          );
        }
        final List<List<int>> clonedPattern =
            _cloneTilePattern(appData.selectedTilePattern);
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.tilePattern,
            sourceSection: section,
            sourceProjectId: projectId,
            sourceLevelIndex: appData.selectedLevel,
            entries: <Map<String, dynamic>>[
              <String, dynamic>{'pattern': clonedPattern},
            ],
          ),
        );
      case 'zones':
        final GameLevel? level = _selectedLevel(appData);
        if (level == null) {
          return const _ClipboardBuildResult.failure('Select a level first.');
        }
        final List<int> selected = _selectedZoneIndicesForCopy(appData);
        if (selected.isEmpty) {
          return const _ClipboardBuildResult.failure(
              'Select at least one zone.');
        }
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.zones,
            sourceSection: section,
            sourceProjectId: projectId,
            sourceLevelIndex: appData.selectedLevel,
            entries: selected
                .map((index) => level.zones[index].toJson())
                .toList(growable: false),
          ),
        );
      case 'sprites':
        final GameLevel? level = _selectedLevel(appData);
        if (level == null) {
          return const _ClipboardBuildResult.failure('Select a level first.');
        }
        final List<int> selected = _selectedSpriteIndicesForCopy(appData);
        if (selected.isEmpty) {
          return const _ClipboardBuildResult.failure(
            'Select at least one sprite.',
          );
        }
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.sprites,
            sourceSection: section,
            sourceProjectId: projectId,
            sourceLevelIndex: appData.selectedLevel,
            entries: selected
                .map((index) => level.sprites[index].toJson())
                .toList(growable: false),
          ),
        );
      case 'paths':
        final GameLevel? level = _selectedLevel(appData);
        if (level == null) {
          return const _ClipboardBuildResult.failure('Select a level first.');
        }
        if (!_isValidIndex(appData.selectedPath, level.paths.length)) {
          return const _ClipboardBuildResult.failure('Select a path to copy.');
        }
        final GamePath path = level.paths[appData.selectedPath];
        final List<Map<String, dynamic>> bindings = level.pathBindings
            .where((binding) => binding.pathId == path.id)
            .map((binding) => binding.toJson())
            .toList(growable: false);
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.paths,
            sourceSection: section,
            sourceProjectId: projectId,
            sourceLevelIndex: appData.selectedLevel,
            entries: <Map<String, dynamic>>[
              <String, dynamic>{
                'path': path.toJson(),
                'bindings': bindings,
              },
            ],
          ),
        );
      case 'media':
        return _ClipboardBuildResult.failure(
          dryRun
              ? 'Clipboard is unavailable in ${_sectionLabel(section)}.'
              : 'Clipboard is unavailable in this section.',
        );
      case 'animations':
      case 'animation_rigs':
        if (!_isValidIndex(
          appData.selectedAnimation,
          appData.gameData.animations.length,
        )) {
          return const _ClipboardBuildResult.failure(
            'Select an animation to copy.',
          );
        }
        return _ClipboardBuildResult.success(
          _EditorClipboardPayload(
            kind: _EditorClipboardKind.animations,
            sourceSection: section,
            sourceProjectId: projectId,
            entries: <Map<String, dynamic>>[
              appData.gameData.animations[appData.selectedAnimation].toJson(),
            ],
          ),
        );
      default:
        return _ClipboardBuildResult.failure(
          dryRun
              ? 'Copy is unavailable in ${_sectionLabel(section)}.'
              : 'Copy is unavailable in this section.',
        );
    }
  }

  Future<bool> _pasteClipboardPayload(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    switch (payload.kind) {
      case _EditorClipboardKind.levels:
        return _pasteLevels(appData, payload);
      case _EditorClipboardKind.layers:
        return _pasteLayers(appData, payload);
      case _EditorClipboardKind.zones:
        return _pasteZones(appData, payload);
      case _EditorClipboardKind.sprites:
        return _pasteSprites(appData, payload);
      case _EditorClipboardKind.paths:
        return _pastePaths(appData, payload);
      case _EditorClipboardKind.media:
        return _pasteMedia(appData, payload);
      case _EditorClipboardKind.animations:
        return _pasteAnimations(appData, payload);
      case _EditorClipboardKind.tilePattern:
        return _pasteTilePattern(appData, payload);
    }
  }

  Future<bool> _pasteLevels(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final int selectedLevel = appData.selectedLevel;
    final List<int> insertedIndices = <int>[];
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-levels',
      mutate: () {
        _ensureMainListGroup(appData.gameData.levelGroups);
        int insertAt =
            _isValidIndex(selectedLevel, appData.gameData.levels.length)
                ? selectedLevel + 1
                : appData.gameData.levels.length;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GameLevel level = GameLevel.fromJson(_asJsonMap(entry));
          level.groupId =
              _adoptListGroupId(appData.gameData.levelGroups, level.groupId);
          appData.gameData.levels.insert(insertAt, level);
          insertedIndices.add(insertAt);
          insertAt += 1;
        }
        if (insertedIndices.isNotEmpty) {
          appData.selectedLevel = insertedIndices.first;
          appData.selectedLayer = -1;
          appData.selectedLayerIndices = <int>{};
          appData.selectedZone = -1;
          appData.selectedZoneIndices = <int>{};
          appData.selectedSprite = -1;
          appData.selectedSpriteIndices = <int>{};
          appData.selectedPath = -1;
        }
      },
    );
  }

  Future<bool> _pasteLayers(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return false;
    }
    final List<int> insertedIndices = <int>[];
    final int insertAt = _insertionAfterSelection(
      length: level.layers.length,
      selected: _selectedLayerIndicesForCopy(appData),
      primary: appData.selectedLayer,
    );
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-layers',
      mutate: () {
        _ensureMainListGroup(level.layerGroups);
        int index = insertAt;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GameLayer layer = GameLayer.fromJson(_asJsonMap(entry));
          layer.groupId = _adoptListGroupId(level.layerGroups, layer.groupId);
          level.layers.insert(index, layer);
          insertedIndices.add(index);
          index += 1;
        }
        if (insertedIndices.isNotEmpty) {
          appData.selectedLayer = insertedIndices.first;
          appData.selectedLayerIndices = insertedIndices.toSet();
        }
      },
    );
  }

  Future<bool> _pasteZones(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return false;
    }
    final List<int> insertedIndices = <int>[];
    final int insertAt = _insertionAfterSelection(
      length: level.zones.length,
      selected: _selectedZoneIndicesForCopy(appData),
      primary: appData.selectedZone,
    );
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-zones',
      mutate: () {
        _ensureMainZoneGroup(level.zoneGroups);
        int index = insertAt;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GameZone zone = GameZone.fromJson(_asJsonMap(entry));
          zone.groupId = _adoptZoneGroupId(level.zoneGroups, zone.groupId);
          level.zones.insert(index, zone);
          insertedIndices.add(index);
          index += 1;
        }
        if (insertedIndices.isNotEmpty) {
          appData.selectedZone = insertedIndices.first;
          appData.selectedZoneIndices = insertedIndices.toSet();
        }
      },
    );
  }

  Future<bool> _pasteSprites(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return false;
    }
    final List<int> insertedIndices = <int>[];
    final int insertAt = _insertionAfterSelection(
      length: level.sprites.length,
      selected: _selectedSpriteIndicesForCopy(appData),
      primary: appData.selectedSprite,
    );
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-sprites',
      mutate: () {
        _ensureMainListGroup(level.spriteGroups);
        int index = insertAt;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GameSprite sprite = GameSprite.fromJson(_asJsonMap(entry));
          sprite.groupId =
              _adoptListGroupId(level.spriteGroups, sprite.groupId);
          level.sprites.insert(index, sprite);
          insertedIndices.add(index);
          index += 1;
        }
        if (insertedIndices.isNotEmpty) {
          appData.selectedSprite = insertedIndices.first;
          appData.selectedSpriteIndices = insertedIndices.toSet();
        }
      },
    );
  }

  Future<bool> _pastePaths(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return false;
    }
    final List<int> insertedIndices = <int>[];
    final int insertAt = _insertionAfterSelection(
      length: level.paths.length,
      selected: _isValidIndex(appData.selectedPath, level.paths.length)
          ? <int>[appData.selectedPath]
          : const <int>[],
      primary: appData.selectedPath,
    );
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-paths',
      mutate: () {
        _ensureMainListGroup(level.pathGroups);
        final Set<String> usedPathIds = level.paths
            .map((path) => path.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        final Set<String> usedBindingIds = level.pathBindings
            .map((binding) => binding.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();

        int index = insertAt;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GamePath path = GamePath.fromJson(_asJsonMap(entry['path']));
          path.id = _nextPathId(usedPathIds);
          path.groupId = _adoptListGroupId(level.pathGroups, path.groupId);
          level.paths.insert(index, path);
          insertedIndices.add(index);
          index += 1;

          final List<dynamic> rawBindings =
              (entry['bindings'] as List<dynamic>?) ?? const <dynamic>[];
          for (final dynamic rawBinding in rawBindings) {
            final GamePathBinding binding =
                GamePathBinding.fromJson(_asJsonMap(rawBinding));
            binding.id = _nextPathBindingId(usedBindingIds);
            binding.pathId = path.id;
            if (_isPathBindingTargetValid(level, binding)) {
              level.pathBindings.add(binding);
            }
          }
        }

        if (insertedIndices.isNotEmpty) {
          appData.selectedPath = insertedIndices.first;
        }
      },
    );
  }

  Future<bool> _pasteMedia(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final List<int> insertedIndices = <int>[];
    final int selectedMedia = appData.selectedMedia;
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-media',
      mutate: () {
        _ensureMainMediaGroup(appData.gameData.mediaGroups);
        final Set<String> fileNames =
            appData.gameData.mediaAssets.map((asset) => asset.fileName).toSet();
        int insertAt =
            _isValidIndex(selectedMedia, appData.gameData.mediaAssets.length)
                ? selectedMedia + 1
                : appData.gameData.mediaAssets.length;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GameMediaAsset asset =
              GameMediaAsset.fromJson(_asJsonMap(entry));
          if (fileNames.contains(asset.fileName)) {
            continue;
          }
          fileNames.add(asset.fileName);
          asset.groupId =
              _adoptMediaGroupId(appData.gameData.mediaGroups, asset.groupId);
          appData.gameData.mediaAssets.insert(insertAt, asset);
          insertedIndices.add(insertAt);
          insertAt += 1;
        }
        if (insertedIndices.isNotEmpty) {
          appData.selectedMedia = insertedIndices.first;
        }
      },
    );
  }

  Future<bool> _pasteAnimations(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    final List<int> insertedIndices = <int>[];
    final int selectedAnimation = appData.selectedAnimation;
    return appData.runProjectMutation(
      debugLabel: 'clipboard-paste-animations',
      mutate: () {
        _ensureMainListGroup(appData.gameData.animationGroups);
        final Set<String> usedAnimationIds = appData.gameData.animations
            .map((animation) => animation.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        int insertAt =
            _isValidIndex(selectedAnimation, appData.gameData.animations.length)
                ? selectedAnimation + 1
                : appData.gameData.animations.length;
        for (final Map<String, dynamic> entry in payload.entries) {
          final GameAnimation animation =
              GameAnimation.fromJson(_asJsonMap(entry));
          animation.id = _nextAnimationId(usedAnimationIds);
          animation.groupId = _adoptListGroupId(
            appData.gameData.animationGroups,
            animation.groupId,
          );
          appData.gameData.animations.insert(insertAt, animation);
          insertedIndices.add(insertAt);
          insertAt += 1;
        }
        if (insertedIndices.isNotEmpty) {
          appData.selectedAnimation = insertedIndices.first;
          appData.selectedAnimationHitBox = -1;
        }
      },
    );
  }

  Future<bool> _pasteTilePattern(
    AppData appData,
    _EditorClipboardPayload payload,
  ) async {
    if (payload.entries.isEmpty) {
      return false;
    }
    final Map<String, dynamic> first = payload.entries.first;
    final List<List<int>> pattern = _cloneTilePattern(
      _asMatrix(first['pattern']),
    );
    if (pattern.isEmpty || pattern.first.isEmpty) {
      return false;
    }
    appData.selectedTilePattern = pattern;
    appData.selectedTileIndex = pattern.first.first;
    appData.tilemapEraserEnabled = false;
    appData.tilesetSelectionColStart = -1;
    appData.tilesetSelectionRowStart = -1;
    appData.tilesetSelectionColEnd = -1;
    appData.tilesetSelectionRowEnd = -1;
    appData.update();
    return true;
  }

  bool _isSectionCompatibleWithClipboard(
    String section,
    _EditorClipboardKind kind,
  ) {
    return switch (kind) {
      _EditorClipboardKind.levels => section == 'levels',
      _EditorClipboardKind.layers => section == 'layers',
      _EditorClipboardKind.zones => section == 'zones',
      _EditorClipboardKind.sprites => section == 'sprites',
      _EditorClipboardKind.paths => section == 'paths',
      _EditorClipboardKind.media => false,
      _EditorClipboardKind.animations =>
        section == 'animations' || section == 'animation_rigs',
      _EditorClipboardKind.tilePattern => section == 'tilemap',
    };
  }

  String _clipboardSummaryText(AppData appData) {
    if (!_isClipboardAvailableInSection(appData.selectedSection)) {
      return 'Clipboard unavailable in ${_sectionLabel(appData.selectedSection)}.';
    }
    final _EditorClipboardPayload? payload = _clipboardPayload;
    if (payload == null) {
      return 'Clipboard: Empty';
    }
    final String label = _clipboardKindLabel(payload.kind);
    final int count = payload.itemCount;
    final String countLabel = count == 1 ? 'item' : 'items';
    final _ClipboardEligibility pasteEligibility = _pasteEligibility(appData);
    if (!pasteEligibility.isAllowed) {
      return "Cannot paste '$label' here.";
    }
    return 'Clipboard: $count "$label" $countLabel';
  }

  String _clipboardKindLabel(_EditorClipboardKind kind) {
    return switch (kind) {
      _EditorClipboardKind.levels => 'Level',
      _EditorClipboardKind.layers => 'Layer',
      _EditorClipboardKind.zones => 'Zone',
      _EditorClipboardKind.sprites => 'Sprite',
      _EditorClipboardKind.paths => 'Path',
      _EditorClipboardKind.media => 'Media',
      _EditorClipboardKind.animations => 'Animation',
      _EditorClipboardKind.tilePattern => 'Tile Pattern',
    };
  }

  String _shortcutLabel(String letter) {
    final TargetPlatform platform = defaultTargetPlatform;
    final bool usesCmd = platform == TargetPlatform.macOS;
    return '${usesCmd ? "Cmd" : "Ctrl"}+$letter';
  }

  bool _hasSelectedLevel(AppData appData) {
    return _isValidIndex(appData.selectedLevel, appData.gameData.levels.length);
  }

  GameLevel? _selectedLevel(AppData appData) {
    if (!_hasSelectedLevel(appData)) {
      return null;
    }
    return appData.gameData.levels[appData.selectedLevel];
  }

  bool _isValidIndex(int index, int length) {
    return index >= 0 && index < length;
  }

  List<int> _selectedLayerIndicesForCopy(AppData appData) {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return <int>[];
    }
    final Set<int> selected =
        _validatedLayerSelection(appData, appData.selectedLayerIndices);
    if (_isValidIndex(appData.selectedLayer, level.layers.length)) {
      selected.add(appData.selectedLayer);
    }
    final List<int> result = selected.toList(growable: false)..sort();
    return result;
  }

  List<int> _selectedZoneIndicesForCopy(AppData appData) {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return <int>[];
    }
    final Set<int> selected =
        _validatedZoneSelection(appData, appData.selectedZoneIndices);
    if (_isValidIndex(appData.selectedZone, level.zones.length)) {
      selected.add(appData.selectedZone);
    }
    final List<int> result = selected.toList(growable: false)..sort();
    return result;
  }

  List<int> _selectedSpriteIndicesForCopy(AppData appData) {
    final GameLevel? level = _selectedLevel(appData);
    if (level == null) {
      return <int>[];
    }
    final Set<int> selected =
        _validatedSpriteSelection(appData, appData.selectedSpriteIndices);
    if (_isValidIndex(appData.selectedSprite, level.sprites.length)) {
      selected.add(appData.selectedSprite);
    }
    final List<int> result = selected.toList(growable: false)..sort();
    return result;
  }

  int _insertionAfterSelection({
    required int length,
    required Iterable<int> selected,
    required int primary,
  }) {
    final List<int> valid = selected
        .where((index) => index >= 0 && index < length)
        .toList(growable: false)
      ..sort();
    if (valid.isNotEmpty) {
      return valid.last + 1;
    }
    if (_isValidIndex(primary, length)) {
      return primary + 1;
    }
    return length;
  }

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  List<List<int>> _asMatrix(dynamic value) {
    if (value is! List) {
      return <List<int>>[];
    }
    return value
        .whereType<List<dynamic>>()
        .map((row) => row.map((cell) => (cell as num?)?.toInt() ?? -1).toList())
        .toList(growable: true);
  }

  List<List<int>> _cloneTilePattern(List<List<int>> source) {
    return source.map((row) => List<int>.from(row)).toList(growable: true);
  }

  void _ensureMainListGroup(List<GameListGroup> groups) {
    if (!groups.any((group) => group.id == GameListGroup.mainId)) {
      groups.insert(0, GameListGroup.main());
    }
    if (groups.isEmpty) {
      groups.add(GameListGroup.main());
    }
  }

  void _ensureMainZoneGroup(List<GameZoneGroup> groups) {
    if (!groups.any((group) => group.id == GameZoneGroup.mainId)) {
      groups.insert(0, GameZoneGroup.main());
    }
    if (groups.isEmpty) {
      groups.add(GameZoneGroup.main());
    }
  }

  void _ensureMainMediaGroup(List<GameMediaGroup> groups) {
    if (!groups.any((group) => group.id == GameMediaGroup.mainId)) {
      groups.insert(0, GameMediaGroup.main());
    }
    if (groups.isEmpty) {
      groups.add(GameMediaGroup.main());
    }
  }

  String _adoptListGroupId(List<GameListGroup> groups, String rawGroupId) {
    _ensureMainListGroup(groups);
    final String groupId = rawGroupId.trim();
    if (groupId.isEmpty) {
      return GameListGroup.mainId;
    }
    if (!groups.any((group) => group.id == groupId)) {
      groups.add(GameListGroup(id: groupId, name: groupId, collapsed: false));
    }
    return groupId;
  }

  String _adoptZoneGroupId(List<GameZoneGroup> groups, String rawGroupId) {
    _ensureMainZoneGroup(groups);
    final String groupId = rawGroupId.trim();
    if (groupId.isEmpty) {
      return GameZoneGroup.mainId;
    }
    if (!groups.any((group) => group.id == groupId)) {
      groups.add(GameZoneGroup(id: groupId, name: groupId, collapsed: false));
    }
    return groupId;
  }

  String _adoptMediaGroupId(List<GameMediaGroup> groups, String rawGroupId) {
    _ensureMainMediaGroup(groups);
    final String groupId = rawGroupId.trim();
    if (groupId.isEmpty) {
      return GameMediaGroup.mainId;
    }
    if (!groups.any((group) => group.id == groupId)) {
      groups.add(GameMediaGroup(id: groupId, name: groupId, collapsed: false));
    }
    return groupId;
  }

  String _nextPathId(Set<String> used) {
    int index = 1;
    while (used.contains('path_$index')) {
      index += 1;
    }
    final String id = 'path_$index';
    used.add(id);
    return id;
  }

  String _nextPathBindingId(Set<String> used) {
    int index = 1;
    while (used.contains('path_binding_$index')) {
      index += 1;
    }
    final String id = 'path_binding_$index';
    used.add(id);
    return id;
  }

  String _nextAnimationId(Set<String> used) {
    int index = 1;
    while (used.contains('anim_$index')) {
      index += 1;
    }
    final String id = 'anim_$index';
    used.add(id);
    return id;
  }

  bool _isPathBindingTargetValid(GameLevel level, GamePathBinding binding) {
    final int index = binding.targetIndex;
    switch (binding.targetType) {
      case GamePathBinding.targetTypeLayer:
        return _isValidIndex(index, level.layers.length);
      case GamePathBinding.targetTypeZone:
        return _isValidIndex(index, level.zones.length);
      case GamePathBinding.targetTypeSprite:
        return _isValidIndex(index, level.sprites.length);
      default:
        return false;
    }
  }
}
