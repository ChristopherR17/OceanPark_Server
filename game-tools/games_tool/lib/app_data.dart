import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'game_animation.dart';
import 'game_data.dart';
import 'game_layer.dart';
import 'game_media_asset.dart';

typedef ProjectMutation = void Function();
typedef ProjectMutationValidator = String? Function();

class StoredProject {
  final String id;
  final String folderPath;
  String name;
  String description;
  String updatedAt;

  StoredProject({
    required this.id,
    required this.name,
    this.description = '',
    required this.folderPath,
    required this.updatedAt,
  });

  factory StoredProject.fromPath({
    required String folderPath,
    required String name,
    String description = '',
    String? updatedAt,
  }) {
    final String normalizedPath = Directory(folderPath).absolute.path;
    return StoredProject(
      id: normalizedPath,
      folderPath: normalizedPath,
      name: name,
      description: description,
      updatedAt: updatedAt ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  Map<String, dynamic> toIndexJson() {
    return {
      'path': folderPath,
    };
  }

  String get folderName {
    final List<String> parts = folderPath
        .split(Platform.pathSeparator)
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? folderPath : parts.last;
  }
}

class AppData extends ChangeNotifier {
  static const MethodChannel _securityBookmarksChannel =
      MethodChannel('games_tool/security_bookmarks');
  static const String appFolderName = "GamesTool";
  static const String projectsFolderName = "projects";
  static const String projectsIndexFileName = "projects_index.json";
  static const String mediaFolderName = "media";
  static const String tilemapsFolderName = "tilemaps";
  static const String zonesFolderName = "zones";
  static const String pathsFolderName = "paths";
  static const String animationsFolderName = "animations";
  static const String tileMapFileFieldName = "tileMapFile";
  static const String zonesFileFieldName = "zonesFile";
  static const String pathsFileFieldName = "pathsFile";
  static const String animationsFileFieldName = "animationsFile";
  static const Color defaultTilesetSelectionColor = Color(0xFFFFCC00);
  int frame = 0;
  final gameFileName = "game_data.json";

  GameData gameData = GameData(name: "", levels: []);
  String filePath = "";
  String fileName = "";
  bool storageReady = false;
  String storagePath = "";
  String projectsPath = "";
  String selectedProjectId = "";
  List<String> _knownProjectPaths = [];
  Map<String, String> _projectBookmarksByPath = <String, String>{};
  Map<String, String> _knownProjectNamesByPath = <String, String>{};
  List<String> missingProjectPaths = [];
  String projectStatusMessage = "";
  String autosaveInlineMessage = "";
  bool autosaveHasError = false;
  List<StoredProject> projects = [];

  Map<String, ui.Image> imagesCache = {};

  String selectedSection = "projects";
  int selectedLevel = -1;
  int selectedLayer = -1;
  Set<int> selectedLayerIndices = <int>{};
  int selectedZone = -1;
  Set<int> selectedZoneIndices = <int>{};
  int selectedSprite = -1;
  Set<int> selectedSpriteIndices = <int>{};
  int selectedPath = -1;
  int selectedAnimation = -1;
  int selectedAnimationHitBox = -1;
  bool animationRigShowPixelGrid = true;
  String animationRigSelectionAnimationId = "";
  List<int> animationRigSelectedFrames = <int>[];
  int animationRigSelectionStartFrame = -1;
  int animationRigSelectionEndFrame = -1;
  int animationRigActiveFrame = -1;
  int selectedMedia = -1;
  int animationSelectionStartFrame = -1;
  int animationSelectionEndFrame = -1;

  static const Duration _autosaveDebounceDelay = Duration(milliseconds: 320);
  static const Duration _autosaveFollowupDelay = Duration(milliseconds: 80);
  static const Duration _autosaveRetryMinDelay = Duration(seconds: 1);
  static const Duration _autosaveRetryMaxDelay = Duration(seconds: 8);
  Timer? _autosaveDebounceTimer;
  Timer? _autosaveRetryTimer;
  bool _autosaveQueued = false;
  bool _autosaveRunning = false;
  int _autosaveRetryAttempt = 0;
  Completer<void>? _autosaveDrainCompleter;

  bool dragging = false;
  DragUpdateDetails? dragUpdateDetails;
  DragStartDetails? dragStartDetails;
  DragEndDetails? dragEndDetails;
  Offset draggingOffset = Offset.zero;

  // Relació entre la imatge dibuixada i el canvas de dibuix
  late Offset imageOffset;
  late double scaleFactor;

  // "tilemap", relació entre el "tilemap" i la imatge dibuixada al canvas
  late Offset tilemapOffset;
  late double tilemapScaleFactor;

  // "tilemap", relació entre el "tileset" i la imatge dibuixada al canvas
  late Offset tilesetOffset;
  late double tilesetScaleFactor;
  int draggingTileIndex = -1;
  int selectedTileIndex = -1;
  List<List<int>> selectedTilePattern = [];
  bool tilemapEraserEnabled = false;
  int tilesetSelectionColStart = -1;
  int tilesetSelectionRowStart = -1;
  int tilesetSelectionColEnd = -1;
  int tilesetSelectionRowEnd = -1;

  // Drag offsets
  late Offset zoneDragOffset = Offset.zero;
  late Offset spriteDragOffset = Offset.zero;

  // Viewport drag state
  Offset viewportDragOffset = Offset.zero;
  Offset viewportResizeOffset = Offset.zero;
  bool viewportIsDragging = false;
  bool viewportIsResizing = false;
  int viewportPreviewX = 0;
  int viewportPreviewY = 0;
  int viewportPreviewWidth = 320;
  int viewportPreviewHeight = 180;
  int viewportPreviewLevel = -1;

  // Layers canvas viewport (zoom + pan)
  double layersViewScale = 1.0;
  Offset layersViewOffset = Offset.zero;
  Offset layerDragOffset = Offset.zero;

  // Undo / redo stacks (JSON snapshots of gameData)
  final List<Map<String, dynamic>> _undoStack = [];
  final List<Map<String, dynamic>> _redoStack = [];
  static const int _maxUndoSteps = 50;
  static const Duration _defaultUndoGroupWindow = Duration(seconds: 2);
  final Map<String, DateTime> _undoGroupCheckpointAt = {};

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  List<ui.Image> _uniqueImages(Iterable<ui.Image> images) {
    final List<ui.Image> unique = <ui.Image>[];
    for (final ui.Image image in images) {
      bool seen = false;
      for (final ui.Image candidate in unique) {
        if (identical(candidate, image)) {
          seen = true;
          break;
        }
      }
      if (!seen) {
        unique.add(image);
      }
    }
    return unique;
  }

  void _safeDisposeImage(ui.Image image) {
    try {
      image.dispose();
    } catch (_) {
      // Ignore disposal failures from already-disposed platform image handles.
    }
  }

  void _disposeAndClearImageCache() {
    final List<ui.Image> images = _uniqueImages(imagesCache.values);
    for (final ui.Image image in images) {
      _safeDisposeImage(image);
    }
    imagesCache.clear();
  }

  void _removeImagesFromCache(Iterable<String> keys) {
    final List<ui.Image> removedImages = <ui.Image>[];
    for (final String key in keys) {
      if (key.isEmpty) {
        continue;
      }
      final ui.Image? removed = imagesCache.remove(key);
      if (removed == null) {
        continue;
      }
      bool tracked = false;
      for (final ui.Image candidate in removedImages) {
        if (identical(candidate, removed)) {
          tracked = true;
          break;
        }
      }
      if (!tracked) {
        removedImages.add(removed);
      }
    }

    for (final ui.Image removed in removedImages) {
      bool stillReferenced = false;
      for (final ui.Image candidate in imagesCache.values) {
        if (identical(candidate, removed)) {
          stillReferenced = true;
          break;
        }
      }
      if (!stillReferenced) {
        _safeDisposeImage(removed);
      }
    }
  }

  Map<String, dynamic> _captureSelectionSnapshot() {
    return <String, dynamic>{
      'selectedSection': selectedSection,
      'selectedLevel': selectedLevel,
      'selectedLayer': selectedLayer,
      'selectedLayerIndices': selectedLayerIndices.toList(growable: false),
      'selectedZone': selectedZone,
      'selectedZoneIndices': selectedZoneIndices.toList(growable: false),
      'selectedSprite': selectedSprite,
      'selectedSpriteIndices': selectedSpriteIndices.toList(growable: false),
      'selectedPath': selectedPath,
      'selectedAnimation': selectedAnimation,
      'selectedAnimationHitBox': selectedAnimationHitBox,
      'animationRigSelectionAnimationId': animationRigSelectionAnimationId,
      'animationRigSelectedFrames':
          animationRigSelectedFrames.toList(growable: false),
      'animationRigSelectionStartFrame': animationRigSelectionStartFrame,
      'animationRigSelectionEndFrame': animationRigSelectionEndFrame,
      'animationRigActiveFrame': animationRigActiveFrame,
      'selectedMedia': selectedMedia,
      'animationSelectionStartFrame': animationSelectionStartFrame,
      'animationSelectionEndFrame': animationSelectionEndFrame,
      'selectedTileIndex': selectedTileIndex,
      'selectedTilePattern': selectedTilePattern
          .map((row) => row.toList(growable: false))
          .toList(growable: false),
      'tilemapEraserEnabled': tilemapEraserEnabled,
      'tilesetSelectionColStart': tilesetSelectionColStart,
      'tilesetSelectionRowStart': tilesetSelectionRowStart,
      'tilesetSelectionColEnd': tilesetSelectionColEnd,
      'tilesetSelectionRowEnd': tilesetSelectionRowEnd,
    };
  }

  Map<String, dynamic> _captureUndoSnapshot() {
    return <String, dynamic>{
      'gameData': gameData.toJson(),
      'selection': _captureSelectionSnapshot(),
    };
  }

  int _snapshotInt(dynamic value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  String _snapshotString(dynamic value, String fallback) {
    if (value is String) {
      return value;
    }
    return fallback;
  }

  bool _snapshotBool(dynamic value, bool fallback) {
    if (value is bool) {
      return value;
    }
    return fallback;
  }

  Set<int> _snapshotIntSet(dynamic value) {
    if (value is! List) {
      return <int>{};
    }
    final Set<int> result = <int>{};
    for (final dynamic item in value) {
      if (item is int) {
        result.add(item);
      } else if (item is num) {
        result.add(item.toInt());
      }
    }
    return result;
  }

  List<int> _snapshotIntList(dynamic value) {
    if (value is! List) {
      return <int>[];
    }
    final List<int> result = <int>[];
    for (final dynamic item in value) {
      if (item is int) {
        result.add(item);
      } else if (item is num) {
        result.add(item.toInt());
      }
    }
    return result;
  }

  List<List<int>> _snapshotIntMatrix(dynamic value) {
    if (value is! List) {
      return <List<int>>[];
    }
    final List<List<int>> result = <List<int>>[];
    for (final dynamic row in value) {
      if (row is! List) {
        continue;
      }
      final List<int> parsedRow = <int>[];
      for (final dynamic cell in row) {
        if (cell is int) {
          parsedRow.add(cell);
        } else if (cell is num) {
          parsedRow.add(cell.toInt());
        }
      }
      result.add(parsedRow);
    }
    return result;
  }

  void _restoreSelectionSnapshot(dynamic snapshot) {
    if (snapshot is! Map) {
      return;
    }
    final Map<dynamic, dynamic> selection = snapshot;
    selectedSection =
        _snapshotString(selection['selectedSection'], selectedSection);
    selectedLevel = _snapshotInt(selection['selectedLevel'], selectedLevel);
    selectedLayer = _snapshotInt(selection['selectedLayer'], selectedLayer);
    selectedLayerIndices = _snapshotIntSet(selection['selectedLayerIndices']);
    selectedZone = _snapshotInt(selection['selectedZone'], selectedZone);
    selectedZoneIndices = _snapshotIntSet(selection['selectedZoneIndices']);
    selectedSprite = _snapshotInt(selection['selectedSprite'], selectedSprite);
    selectedSpriteIndices = _snapshotIntSet(selection['selectedSpriteIndices']);
    selectedPath = _snapshotInt(selection['selectedPath'], selectedPath);
    selectedAnimation =
        _snapshotInt(selection['selectedAnimation'], selectedAnimation);
    selectedAnimationHitBox = _snapshotInt(
        selection['selectedAnimationHitBox'], selectedAnimationHitBox);
    animationRigSelectionAnimationId = _snapshotString(
      selection['animationRigSelectionAnimationId'],
      animationRigSelectionAnimationId,
    );
    animationRigSelectedFrames =
        _snapshotIntList(selection['animationRigSelectedFrames']);
    animationRigSelectionStartFrame = _snapshotInt(
      selection['animationRigSelectionStartFrame'],
      animationRigSelectionStartFrame,
    );
    animationRigSelectionEndFrame = _snapshotInt(
      selection['animationRigSelectionEndFrame'],
      animationRigSelectionEndFrame,
    );
    animationRigActiveFrame = _snapshotInt(
      selection['animationRigActiveFrame'],
      animationRigActiveFrame,
    );
    selectedMedia = _snapshotInt(selection['selectedMedia'], selectedMedia);
    animationSelectionStartFrame = _snapshotInt(
      selection['animationSelectionStartFrame'],
      animationSelectionStartFrame,
    );
    animationSelectionEndFrame = _snapshotInt(
      selection['animationSelectionEndFrame'],
      animationSelectionEndFrame,
    );
    selectedTileIndex =
        _snapshotInt(selection['selectedTileIndex'], selectedTileIndex);
    selectedTilePattern = _snapshotIntMatrix(selection['selectedTilePattern']);
    tilemapEraserEnabled =
        _snapshotBool(selection['tilemapEraserEnabled'], tilemapEraserEnabled);
    tilesetSelectionColStart = _snapshotInt(
      selection['tilesetSelectionColStart'],
      tilesetSelectionColStart,
    );
    tilesetSelectionRowStart = _snapshotInt(
      selection['tilesetSelectionRowStart'],
      tilesetSelectionRowStart,
    );
    tilesetSelectionColEnd = _snapshotInt(
      selection['tilesetSelectionColEnd'],
      tilesetSelectionColEnd,
    );
    tilesetSelectionRowEnd = _snapshotInt(
      selection['tilesetSelectionRowEnd'],
      tilesetSelectionRowEnd,
    );
  }

  void _restoreUndoSnapshot(Map<String, dynamic> snapshot) {
    final dynamic gameDataSnapshot = snapshot['gameData'];
    if (gameDataSnapshot is Map) {
      gameData = GameData.fromJson(Map<String, dynamic>.from(gameDataSnapshot));
      _restoreSelectionSnapshot(snapshot['selection']);
      return;
    }
    // Backward compatibility with old undo checkpoints containing only gameData.
    gameData = GameData.fromJson(snapshot);
  }

  /// Call this BEFORE mutating gameData to record a checkpoint.
  void pushUndo() {
    _undoStack.add(_captureUndoSnapshot());
    if (_undoStack.length > _maxUndoSteps) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _clearUndoGroupingState() {
    _undoGroupCheckpointAt.clear();
  }

  bool _shouldPushUndoCheckpoint({
    required String? undoGroupKey,
    required Duration undoGroupWindow,
  }) {
    final String key = undoGroupKey?.trim() ?? '';
    if (key.isEmpty) {
      // Ungrouped mutations are "major" by default and must start a fresh
      // checkpoint sequence.
      _clearUndoGroupingState();
      return true;
    }

    final DateTime now = DateTime.now();
    final DateTime? lastCheckpointAt = _undoGroupCheckpointAt[key];
    if (lastCheckpointAt == null ||
        now.difference(lastCheckpointAt) > undoGroupWindow) {
      _undoGroupCheckpointAt[key] = now;
      return true;
    }
    return false;
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_captureUndoSnapshot());
    _restoreUndoSnapshot(_undoStack.removeLast());
    _clearUndoGroupingState();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_captureUndoSnapshot());
    _restoreUndoSnapshot(_redoStack.removeLast());
    _clearUndoGroupingState();
    notifyListeners();
  }

  void update() {
    notifyListeners();
  }

  Duration _autosaveRetryDelay(int attempt) {
    final int cappedAttempt = attempt < 1 ? 1 : (attempt > 6 ? 6 : attempt);
    final int factor = 1 << (cappedAttempt - 1);
    final int nextMs = _autosaveRetryMinDelay.inMilliseconds * factor;
    final int clampedMs = nextMs < _autosaveRetryMinDelay.inMilliseconds
        ? _autosaveRetryMinDelay.inMilliseconds
        : (nextMs > _autosaveRetryMaxDelay.inMilliseconds
            ? _autosaveRetryMaxDelay.inMilliseconds
            : nextMs);
    return Duration(
      milliseconds: clampedMs,
    );
  }

  void queueAutosave({Duration debounce = _autosaveDebounceDelay}) {
    if (selectedProject == null) {
      return;
    }
    _autosaveQueued = true;
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = Timer(debounce, () {
      unawaited(_drainAutosaveQueue());
    });
  }

  Future<void> flushPendingAutosave() async {
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = null;
    _autosaveRetryTimer?.cancel();
    _autosaveRetryTimer = null;

    if (!_autosaveQueued && !_autosaveRunning) {
      return;
    }

    _autosaveQueued = true;
    await _drainAutosaveQueue(force: true);
  }

  Future<void> _drainAutosaveQueue({bool force = false}) async {
    if (selectedProject == null) {
      _autosaveQueued = false;
      return;
    }

    if (_autosaveRunning) {
      if (force) {
        await _autosaveDrainCompleter?.future;
        if (_autosaveQueued) {
          await _drainAutosaveQueue(force: true);
        }
      }
      return;
    }

    if (!_autosaveQueued && !force) {
      return;
    }

    _autosaveRunning = true;
    final Completer<void> drainCompleter = Completer<void>();
    _autosaveDrainCompleter = drainCompleter;
    _autosaveQueued = false;

    try {
      await _saveGameInternal(
        notifyOnSuccess: false,
      );

      if (autosaveInlineMessage.isNotEmpty || autosaveHasError) {
        autosaveInlineMessage = '';
        autosaveHasError = false;
        notifyListeners();
      }
      _autosaveRetryAttempt = 0;
    } catch (e) {
      _autosaveQueued = true;
      _autosaveRetryAttempt += 1;
      final Duration delay = _autosaveRetryDelay(_autosaveRetryAttempt);
      autosaveInlineMessage =
          'Autosave failed. Retrying in ${delay.inSeconds}s.';
      autosaveHasError = true;
      notifyListeners();

      _autosaveRetryTimer?.cancel();
      _autosaveRetryTimer = Timer(delay, () {
        _autosaveRetryTimer = null;
        _autosaveDebounceTimer?.cancel();
        _autosaveDebounceTimer = Timer(_autosaveFollowupDelay, () {
          unawaited(_drainAutosaveQueue());
        });
      });
    } finally {
      _autosaveRunning = false;
      if (!drainCompleter.isCompleted) {
        drainCompleter.complete();
      }
    }

    if (_autosaveQueued && _autosaveRetryTimer == null) {
      _autosaveDebounceTimer?.cancel();
      _autosaveDebounceTimer = Timer(_autosaveFollowupDelay, () {
        unawaited(_drainAutosaveQueue());
      });
    }
  }

  void _clearAutosaveState() {
    _autosaveDebounceTimer?.cancel();
    _autosaveDebounceTimer = null;
    _autosaveRetryTimer?.cancel();
    _autosaveRetryTimer = null;
    _autosaveQueued = false;
    _autosaveRunning = false;
    _autosaveRetryAttempt = 0;
    _autosaveDrainCompleter = null;
    autosaveInlineMessage = '';
    autosaveHasError = false;
  }

  Future<void> setSelectedSection(String value) async {
    if (selectedSection == value) {
      return;
    }
    await flushPendingAutosave();
    selectedSection = value;
    notifyListeners();
  }

  /// Canonical pathway for persisted editor mutations.
  ///
  /// Contract:
  /// - Optional validation gate before applying.
  /// - Optional undo checkpoint before data mutation.
  /// - UI refresh after mutation.
  /// - Optional autosave of project data.
  Future<bool> runProjectMutation({
    required ProjectMutation mutate,
    ProjectMutationValidator? validate,
    bool requireSelectedProject = true,
    bool pushUndoCheckpoint = true,
    String? undoGroupKey,
    Duration undoGroupWindow = _defaultUndoGroupWindow,
    bool refreshUi = true,
    bool autosave = true,
    bool notifyOnValidationFailure = true,
    String? debugLabel,
  }) async {
    if (requireSelectedProject && selectedProject == null) {
      return false;
    }

    final String? validationError = validate?.call();
    if (validationError != null) {
      projectStatusMessage = validationError;
      if (notifyOnValidationFailure) {
        notifyListeners();
      }
      return false;
    }

    try {
      if (pushUndoCheckpoint &&
          _shouldPushUndoCheckpoint(
            undoGroupKey: undoGroupKey,
            undoGroupWindow: undoGroupWindow,
          )) {
        pushUndo();
      }
      mutate();
      if (refreshUi) {
        update();
      }
      if (autosave && selectedProject != null) {
        queueAutosave();
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("Error in runProjectMutation(${debugLabel ?? 'unnamed'}): $e");
      }
      projectStatusMessage = "Update failed: $e";
      notifyListeners();
      return false;
    }
  }

  StoredProject? _findProjectById(String projectId) {
    for (final project in projects) {
      if (project.id == projectId) {
        return project;
      }
    }
    return null;
  }

  StoredProject? get selectedProject {
    return _findProjectById(selectedProjectId);
  }

  bool get hasMissingProjectPaths => missingProjectPaths.isNotEmpty;

  String? get nextMissingProjectPath {
    if (missingProjectPaths.isEmpty) {
      return null;
    }
    return missingProjectPaths.first;
  }

  String projectDisplayNameForPath(String path) {
    final String normalizedPath = _normalizeProjectFolderPath(path);
    final String explicitName =
        (_knownProjectNamesByPath[normalizedPath] ?? '').trim();
    if (explicitName.isNotEmpty) {
      return explicitName;
    }
    final StoredProject? project = _findProjectById(normalizedPath);
    final String projectName = project?.name.trim() ?? '';
    if (projectName.isNotEmpty) {
      return projectName;
    }
    if (normalizedPath.isNotEmpty) {
      return _lastPathSegment(normalizedPath);
    }
    return _lastPathSegment(path);
  }

  String _normalizeKnownProjectPath(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    String normalized = Directory(trimmed).absolute.path;
    while (
        normalized.length > 1 && normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _normalizeProjectFolderPath(String value) {
    final String normalized = _normalizeKnownProjectPath(value);
    if (normalized.isEmpty) {
      return '';
    }
    final String parentPath = Directory(normalized).parent.path;
    if (_lastPathSegment(parentPath).toLowerCase() ==
        _lastPathSegment(normalized).toLowerCase()) {
      return _normalizeKnownProjectPath(parentPath);
    }
    return normalized;
  }

  bool get _supportsSecurityBookmarks =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<String?> _createSecurityBookmarkForPath(String path) async {
    if (!_supportsSecurityBookmarks) {
      return null;
    }
    try {
      final dynamic result = await _securityBookmarksChannel.invokeMethod(
        'createBookmark',
        <String, dynamic>{'path': path},
      );
      if (result is String && result.isNotEmpty) {
        return result;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, String>?> _resolveSecurityBookmark(
    String bookmark,
  ) async {
    if (!_supportsSecurityBookmarks || bookmark.trim().isEmpty) {
      return null;
    }
    try {
      final dynamic result = await _securityBookmarksChannel.invokeMethod(
        'resolveBookmark',
        <String, dynamic>{'bookmark': bookmark},
      );
      if (result is! Map) {
        return null;
      }
      final Map<String, dynamic> payload = Map<String, dynamic>.from(result);
      final dynamic rawPath = payload['path'];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        return null;
      }
      final dynamic rawBookmark = payload['bookmark'];
      return <String, String>{
        'path': rawPath,
        'bookmark': rawBookmark is String && rawBookmark.isNotEmpty
            ? rawBookmark
            : bookmark,
      };
    } catch (_) {}
    return null;
  }

  Future<void> _restoreSecurityScopedAccessForKnownPaths() async {
    if (!_supportsSecurityBookmarks) {
      return;
    }
    final Set<String> uniquePaths = <String>{};
    final List<String> normalizedPaths = <String>[];
    final Map<String, String> nextBookmarks = <String, String>{};
    final Map<String, String> nextProjectNames = <String, String>{};
    final Map<String, String> resolvedPathByRawPath = <String, String>{};

    for (final String rawPath in _knownProjectPaths) {
      final String normalizedRawPath = _normalizeProjectFolderPath(rawPath);
      if (normalizedRawPath.isEmpty) {
        continue;
      }
      final String bookmark = _projectBookmarksByPath[normalizedRawPath] ??
          _projectBookmarksByPath[rawPath] ??
          '';
      String resolvedPath = normalizedRawPath;
      String? resolvedBookmark;

      if (bookmark.isNotEmpty) {
        final Map<String, String>? resolved =
            await _resolveSecurityBookmark(bookmark);
        if (resolved != null) {
          resolvedPath = _normalizeProjectFolderPath(resolved['path'] ?? '');
          resolvedBookmark = resolved['bookmark'];
        }
      }

      resolvedPath = resolvedPath.isEmpty ? normalizedRawPath : resolvedPath;
      resolvedPathByRawPath[normalizedRawPath] = resolvedPath;
      final String projectName = (_knownProjectNamesByPath[normalizedRawPath] ??
              _knownProjectNamesByPath[rawPath] ??
              '')
          .trim();
      if (!uniquePaths.add(resolvedPath)) {
        if (projectName.isNotEmpty &&
            (nextProjectNames[resolvedPath] ?? '').trim().isEmpty) {
          nextProjectNames[resolvedPath] = projectName;
        }
        continue;
      }
      normalizedPaths.add(resolvedPath);
      if (projectName.isNotEmpty) {
        nextProjectNames[resolvedPath] = projectName;
      }

      final String finalBookmark = resolvedBookmark ??
          (bookmark.isNotEmpty
              ? bookmark
              : (await _createSecurityBookmarkForPath(resolvedPath) ?? ''));
      if (finalBookmark.isNotEmpty) {
        nextBookmarks[resolvedPath] = finalBookmark;
      }
    }

    _knownProjectPaths = normalizedPaths;
    _projectBookmarksByPath = nextBookmarks;
    _knownProjectNamesByPath = nextProjectNames;
    final String normalizedSelectedPath =
        _normalizeProjectFolderPath(selectedProjectId);
    if (normalizedSelectedPath.isNotEmpty) {
      selectedProjectId = resolvedPathByRawPath[normalizedSelectedPath] ??
          normalizedSelectedPath;
    }
  }

  Future<void> initializeStorage() async {
    try {
      final Directory appSupportDirectory =
          await getApplicationSupportDirectory();
      final Directory appStorageDirectory = Directory(
          "${appSupportDirectory.path}${Platform.pathSeparator}$appFolderName");
      if (!await appStorageDirectory.exists()) {
        await appStorageDirectory.create(recursive: true);
      }
      storagePath = appStorageDirectory.path;
      projectsPath = "$storagePath${Platform.pathSeparator}$projectsFolderName";

      await _loadProjectsIndex();
      await _restoreSecurityScopedAccessForKnownPaths();

      final Directory projectsDirectory = Directory(projectsPath);
      if (!await projectsDirectory.exists()) {
        await projectsDirectory.create(recursive: true);
      }

      await _syncProjectsWithDisk();

      if (selectedProjectId != "" && selectedProject != null) {
        await openProject(selectedProjectId, notify: false);
      } else {
        gameData = GameData(name: "", levels: []);
        filePath = "";
        fileName = "";
      }

      storageReady = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print("Error initializing storage: $e");
      }
      projectStatusMessage = "Storage initialization failed: $e";
      notifyListeners();
    }
  }

  Future<void> _loadProjectsIndex() async {
    projects = [];
    selectedProjectId = "";
    _knownProjectPaths = [];
    _projectBookmarksByPath = <String, String>{};
    _knownProjectNamesByPath = <String, String>{};
    missingProjectPaths = [];

    final File indexFile = File(
      "$storagePath${Platform.pathSeparator}$projectsIndexFileName",
    );
    if (!await indexFile.exists()) {
      return;
    }

    final String raw = await indexFile.readAsString();
    if (raw.trim().isEmpty) {
      return;
    }

    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final Set<String> uniquePaths = <String>{};
    final List<String> knownPaths = <String>[];
    final Map<String, String> legacyIdToPath = <String, String>{};
    final Map<String, String> parsedProjectNamesByPath = <String, String>{};

    void addKnownPath(String? candidate) {
      if (candidate == null) {
        return;
      }
      final String normalized = _normalizeProjectFolderPath(candidate);
      if (normalized.isEmpty || !uniquePaths.add(normalized)) {
        return;
      }
      knownPaths.add(normalized);
    }

    final dynamic projectPathsDynamic = decoded['projectPaths'];
    if (projectPathsDynamic is List) {
      for (final dynamic item in projectPathsDynamic) {
        if (item is String) {
          addKnownPath(item);
        }
      }
    }

    final dynamic projectNamesDynamic = decoded['projectNames'];
    if (projectNamesDynamic is Map) {
      for (final MapEntry<dynamic, dynamic> entry
          in projectNamesDynamic.entries) {
        if (entry.key is! String || entry.value is! String) {
          continue;
        }
        final String normalizedPath =
            _normalizeProjectFolderPath(entry.key as String);
        final String name = (entry.value as String).trim();
        if (normalizedPath.isEmpty || name.isEmpty) {
          continue;
        }
        parsedProjectNamesByPath[normalizedPath] = name;
      }
    }

    final dynamic legacyProjectsDynamic = decoded['projects'];
    if (legacyProjectsDynamic is List) {
      for (final dynamic item in legacyProjectsDynamic) {
        if (item is! Map) {
          continue;
        }
        final Map<String, dynamic> map = Map<String, dynamic>.from(item);
        String? pathFromLegacy;
        final dynamic rawFolderPath = map['folderPath'];
        if (rawFolderPath is String && rawFolderPath.trim().isNotEmpty) {
          pathFromLegacy = rawFolderPath;
        } else {
          final dynamic rawFolderName = map['folderName'];
          if (rawFolderName is String && rawFolderName.trim().isNotEmpty) {
            pathFromLegacy =
                "$projectsPath${Platform.pathSeparator}${rawFolderName.trim()}";
          }
        }
        if (pathFromLegacy == null) {
          continue;
        }
        final String normalizedProjectPath =
            _normalizeProjectFolderPath(pathFromLegacy);
        if (normalizedProjectPath.isEmpty) {
          continue;
        }
        addKnownPath(normalizedProjectPath);
        final dynamic rawName = map['name'];
        if (rawName is String && rawName.trim().isNotEmpty) {
          parsedProjectNamesByPath[normalizedProjectPath] = rawName.trim();
        }
        final dynamic rawLegacyId = map['id'];
        if (rawLegacyId is String && rawLegacyId.isNotEmpty) {
          legacyIdToPath[rawLegacyId] = normalizedProjectPath;
        }
      }
    }

    String selectedPath = '';
    final dynamic rawSelectedPath = decoded['selectedProjectPath'];
    if (rawSelectedPath is String) {
      selectedPath = _normalizeProjectFolderPath(rawSelectedPath);
    }
    if (selectedPath.isEmpty) {
      final String rawLegacySelectedId =
          (decoded['selectedProjectId'] as String?) ?? "";
      if (rawLegacySelectedId.isNotEmpty) {
        selectedPath = legacyIdToPath[rawLegacySelectedId] ??
            _normalizeProjectFolderPath(rawLegacySelectedId);
      }
    }

    _knownProjectPaths = knownPaths;
    _knownProjectNamesByPath = <String, String>{};
    for (final String path in _knownProjectPaths) {
      final String name = (parsedProjectNamesByPath[path] ?? '').trim();
      if (name.isNotEmpty) {
        _knownProjectNamesByPath[path] = name;
      }
    }
    final dynamic rawBookmarksDynamic = decoded['projectBookmarks'];
    if (rawBookmarksDynamic is Map) {
      final Map<String, String> parsedBookmarks = <String, String>{};
      for (final MapEntry<dynamic, dynamic> entry
          in rawBookmarksDynamic.entries) {
        if (entry.key is! String || entry.value is! String) {
          continue;
        }
        final String normalizedKey =
            _normalizeProjectFolderPath(entry.key as String);
        final String value = (entry.value as String).trim();
        if (normalizedKey.isEmpty || value.isEmpty) {
          continue;
        }
        parsedBookmarks[normalizedKey] = value;
      }
      _projectBookmarksByPath = parsedBookmarks;
    }
    if (selectedPath.isNotEmpty) {
      selectedProjectId = selectedPath;
    }
  }

  Future<void> _saveProjectsIndex() async {
    if (storagePath == "") {
      return;
    }
    final File indexFile =
        File("$storagePath${Platform.pathSeparator}$projectsIndexFileName");
    final Map<String, String> persistedBookmarks = <String, String>{};
    final Map<String, String> persistedProjectNames = <String, String>{};
    for (final String path in _knownProjectPaths) {
      final String bookmark = _projectBookmarksByPath[path] ?? '';
      if (bookmark.isNotEmpty) {
        persistedBookmarks[path] = bookmark;
      }
      final String projectName = (_knownProjectNamesByPath[path] ?? '').trim();
      if (projectName.isNotEmpty) {
        persistedProjectNames[path] = projectName;
      }
    }
    final String content = const JsonEncoder.withIndent("  ").convert({
      'version': 4,
      'selectedProjectPath': selectedProjectId,
      'projectPaths': _knownProjectPaths,
      'projectBookmarks': persistedBookmarks,
      'projectNames': persistedProjectNames,
    });
    await indexFile.writeAsString(content);
  }

  Future<void> _syncProjectsWithDisk() async {
    final Set<String> uniqueKnown = <String>{};
    final List<String> normalizedKnown = <String>[];
    final Map<String, String> normalizedBookmarks = <String, String>{};
    final Map<String, String> normalizedNames = <String, String>{};
    for (final String rawPath in _knownProjectPaths) {
      final String normalized = _normalizeProjectFolderPath(rawPath);
      if (normalized.isEmpty || !uniqueKnown.add(normalized)) {
        continue;
      }
      normalizedKnown.add(normalized);
      final String bookmark = _projectBookmarksByPath[normalized] ??
          _projectBookmarksByPath[rawPath] ??
          '';
      if (bookmark.isNotEmpty) {
        normalizedBookmarks[normalized] = bookmark;
      }
      final String projectName = _knownProjectNamesByPath[normalized] ??
          _knownProjectNamesByPath[rawPath] ??
          '';
      if (projectName.trim().isNotEmpty) {
        normalizedNames[normalized] = projectName.trim();
      }
    }
    _knownProjectPaths = normalizedKnown;
    _projectBookmarksByPath = normalizedBookmarks;
    _knownProjectNamesByPath = normalizedNames;
    final Map<String, String> nextKnownProjectNames =
        Map<String, String>.from(_knownProjectNamesByPath);

    final List<StoredProject> loadedProjects = <StoredProject>[];
    final List<String> missingPaths = <String>[];
    for (final String folderPath in _knownProjectPaths) {
      if (!await _ensureProjectSecurityAccess(folderPath)) {
        nextKnownProjectNames.putIfAbsent(
          folderPath,
          () => _lastPathSegment(folderPath),
        );
        missingPaths.add(folderPath);
        continue;
      }
      final File gameFile =
          File("$folderPath${Platform.pathSeparator}$gameFileName");
      if (!await gameFile.exists()) {
        nextKnownProjectNames.putIfAbsent(
          folderPath,
          () => _lastPathSegment(folderPath),
        );
        missingPaths.add(folderPath);
        continue;
      }
      final ({String? name, String description}) summary =
          await _readProjectSummaryFromDisk(gameFile);
      final String inferredName = summary.name ?? _lastPathSegment(folderPath);
      nextKnownProjectNames[folderPath] = inferredName;
      String updatedAt = DateTime.now().toUtc().toIso8601String();
      try {
        updatedAt = (await gameFile.lastModified()).toUtc().toIso8601String();
      } catch (_) {}
      loadedProjects.add(
        StoredProject.fromPath(
          folderPath: folderPath,
          name: inferredName,
          description: summary.description,
          updatedAt: updatedAt,
        ),
      );
    }

    // Legacy compatibility: discover projects stored under app support.
    final Directory projectsDirectory = Directory(projectsPath);
    if (await projectsDirectory.exists()) {
      await for (final FileSystemEntity entity
          in projectsDirectory.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final String normalizedPath = _normalizeProjectFolderPath(entity.path);
        if (normalizedPath.isEmpty || uniqueKnown.contains(normalizedPath)) {
          continue;
        }
        final File gameFile =
            File("${entity.path}${Platform.pathSeparator}$gameFileName");
        if (!await gameFile.exists()) {
          continue;
        }
        uniqueKnown.add(normalizedPath);
        _knownProjectPaths.add(normalizedPath);
        final String? bookmark =
            await _createSecurityBookmarkForPath(normalizedPath);
        if (bookmark != null && bookmark.isNotEmpty) {
          _projectBookmarksByPath[normalizedPath] = bookmark;
        }
        final ({String? name, String description}) summary =
            await _readProjectSummaryFromDisk(gameFile);
        final String inferredName =
            summary.name ?? _lastPathSegment(normalizedPath);
        nextKnownProjectNames[normalizedPath] = inferredName;
        String updatedAt = DateTime.now().toUtc().toIso8601String();
        try {
          updatedAt = (await gameFile.lastModified()).toUtc().toIso8601String();
        } catch (_) {}
        loadedProjects.add(
          StoredProject.fromPath(
            folderPath: normalizedPath,
            name: inferredName,
            description: summary.description,
            updatedAt: updatedAt,
          ),
        );
      }
    }

    projects = loadedProjects;
    _knownProjectNamesByPath = nextKnownProjectNames;
    missingProjectPaths = missingPaths;
    await _saveProjectsIndex();
  }

  Future<({String? name, String description})> _readProjectSummaryFromDisk(
    File gameFile,
  ) async {
    try {
      final dynamic decoded = jsonDecode(await gameFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        final dynamic name = decoded['name'];
        final dynamic description = decoded['description'];
        return (
          name: name is String && name.trim().isNotEmpty ? name.trim() : null,
          description: description is String ? description.trim() : '',
        );
      }
    } catch (_) {}
    return (name: null, description: '');
  }

  Future<String?> _readProjectNameFromDisk(File gameFile) async {
    final ({String? name, String description}) summary =
        await _readProjectSummaryFromDisk(gameFile);
    return summary.name;
  }

  String _lastPathSegment(String value) {
    final List<String> parts = value
        .split(Platform.pathSeparator)
        .where((item) => item != "")
        .toList();
    return parts.isEmpty ? value : parts.last;
  }

  Future<String> _buildUniqueFileNameInDirectory(
    String directoryPath,
    String originalFileName,
  ) async {
    final int dotIndex = originalFileName.lastIndexOf('.');
    final String baseName = dotIndex <= 0
        ? originalFileName
        : originalFileName.substring(0, dotIndex);
    final String extension =
        dotIndex <= 0 ? "" : originalFileName.substring(dotIndex);

    String candidate = originalFileName;
    int cnt = 2;
    while (await File(
      "$directoryPath${Platform.pathSeparator}$candidate",
    ).exists()) {
      candidate = "${baseName}_$cnt$extension";
      cnt++;
    }
    return candidate;
  }

  String _normalizeProjectRelativePath(String value) {
    String normalized = value.trim().replaceAll('\\', '/');
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.isEmpty) {
      return '';
    }
    final List<String> segments = normalized.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        return '';
      }
    }
    return segments.join('/');
  }

  String _defaultTileMapRelativePath(int levelIndex, int layerIndex) {
    final String level = levelIndex.toString().padLeft(3, '0');
    final String layer = layerIndex.toString().padLeft(3, '0');
    return '$tilemapsFolderName/level_${level}_layer_$layer.json';
  }

  String _defaultZonesRelativePath(int levelIndex) {
    final String level = levelIndex.toString().padLeft(3, '0');
    return '$zonesFolderName/level_${level}_zones.json';
  }

  String _defaultPathsRelativePath(int levelIndex) {
    final String level = levelIndex.toString().padLeft(3, '0');
    return '$pathsFolderName/level_${level}_paths.json';
  }

  String _defaultAnimationsRelativePath() {
    return '$animationsFolderName/animations.json';
  }

  bool _isMediaRelativePath(String value) {
    final String normalized = _normalizeProjectRelativePath(value);
    if (normalized.isEmpty) {
      return false;
    }
    return normalized == mediaFolderName ||
        normalized.startsWith('$mediaFolderName/');
  }

  String _mediaRelativePathForBaseName(String baseName) {
    return '$mediaFolderName/$baseName';
  }

  Future<void> _moveFileWithinProject({
    required String sourceAbsolutePath,
    required String destinationAbsolutePath,
  }) async {
    if (sourceAbsolutePath == destinationAbsolutePath) {
      return;
    }
    final File sourceFile = File(sourceAbsolutePath);
    if (!await sourceFile.exists()) {
      return;
    }
    final File destinationFile = File(destinationAbsolutePath);
    await destinationFile.parent.create(recursive: true);
    try {
      await sourceFile.rename(destinationAbsolutePath);
    } catch (_) {
      await sourceFile.copy(destinationAbsolutePath);
      try {
        await sourceFile.delete();
      } catch (_) {}
    }
  }

  String _normalizedTileMapRelativePath(
    dynamic rawValue, {
    required int levelIndex,
    required int layerIndex,
  }) {
    final String candidate = rawValue is String ? rawValue : '';
    final String normalized = _normalizeProjectRelativePath(candidate);
    if (normalized.isNotEmpty && normalized.toLowerCase().endsWith('.json')) {
      return normalized;
    }
    return _defaultTileMapRelativePath(levelIndex, layerIndex);
  }

  String _normalizedZonesRelativePath(
    dynamic rawValue, {
    required int levelIndex,
  }) {
    final String candidate = rawValue is String ? rawValue : '';
    final String normalized = _normalizeProjectRelativePath(candidate);
    if (normalized.isNotEmpty && normalized.toLowerCase().endsWith('.json')) {
      return normalized;
    }
    return _defaultZonesRelativePath(levelIndex);
  }

  String _normalizedPathsRelativePath(
    dynamic rawValue, {
    required int levelIndex,
  }) {
    final String candidate = rawValue is String ? rawValue : '';
    final String normalized = _normalizeProjectRelativePath(candidate);
    if (normalized.isNotEmpty && normalized.toLowerCase().endsWith('.json')) {
      return normalized;
    }
    return _defaultPathsRelativePath(levelIndex);
  }

  String _normalizedAnimationsRelativePath(dynamic rawValue) {
    final String candidate = rawValue is String ? rawValue : '';
    final String normalized = _normalizeProjectRelativePath(candidate);
    if (normalized.isNotEmpty && normalized.toLowerCase().endsWith('.json')) {
      return normalized;
    }
    return _defaultAnimationsRelativePath();
  }

  String _relativePathFromProjectAbsolutePath(
    String projectDirectoryPath,
    String absolutePath,
  ) {
    final String projectPrefix =
        '$projectDirectoryPath${Platform.pathSeparator}';
    if (!absolutePath.startsWith(projectPrefix)) {
      return '';
    }
    return _normalizeProjectRelativePath(
      absolutePath.substring(projectPrefix.length),
    );
  }

  List<List<int>> _parseTileMapRows(dynamic value) {
    if (value is! List) {
      return <List<int>>[];
    }
    final List<List<int>> rows = <List<int>>[];
    for (final dynamic row in value) {
      if (row is! List) {
        continue;
      }
      rows.add(
        row
            .map<int>(
              (dynamic cell) => cell is num ? cell.toInt() : -1,
            )
            .toList(growable: false),
      );
    }
    return rows;
  }

  List<Map<String, dynamic>> _parseObjectList(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }
    final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
    for (final dynamic item in value) {
      if (item is Map<String, dynamic>) {
        entries.add(item);
      } else if (item is Map) {
        entries.add(Map<String, dynamic>.from(item));
      }
    }
    return entries;
  }

  Future<List<List<int>>> _readExternalTileMapRows(String absolutePath) async {
    final File file = File(absolutePath);
    if (!await file.exists()) {
      throw Exception("Missing tilemap file: ${file.path}");
    }
    final dynamic decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return _parseTileMapRows(decoded['tileMap']);
    }
    return _parseTileMapRows(decoded);
  }

  Future<Map<String, dynamic>> _readExternalZonesData(
      String absolutePath) async {
    final File file = File(absolutePath);
    if (!await file.exists()) {
      throw Exception("Missing zones file: ${file.path}");
    }
    final dynamic decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return <String, dynamic>{
        'zones': _parseObjectList(decoded['zones']),
        'zoneGroups': _parseObjectList(decoded['zoneGroups']),
      };
    }
    if (decoded is Map) {
      final Map<String, dynamic> asMap = Map<String, dynamic>.from(decoded);
      return <String, dynamic>{
        'zones': _parseObjectList(asMap['zones']),
        'zoneGroups': _parseObjectList(asMap['zoneGroups']),
      };
    }
    if (decoded is List) {
      return <String, dynamic>{
        'zones': _parseObjectList(decoded),
        'zoneGroups': <Map<String, dynamic>>[],
      };
    }
    return <String, dynamic>{
      'zones': <Map<String, dynamic>>[],
      'zoneGroups': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _readExternalPathsData(
      String absolutePath) async {
    final File file = File(absolutePath);
    if (!await file.exists()) {
      throw Exception("Missing paths file: ${file.path}");
    }
    final dynamic decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return <String, dynamic>{
        'pathGroups': _parseObjectList(decoded['pathGroups']),
        'paths': _parseObjectList(decoded['paths']),
        'pathBindings': _parseObjectList(decoded['pathBindings']),
      };
    }
    if (decoded is Map) {
      final Map<String, dynamic> asMap = Map<String, dynamic>.from(decoded);
      return <String, dynamic>{
        'pathGroups': _parseObjectList(asMap['pathGroups']),
        'paths': _parseObjectList(asMap['paths']),
        'pathBindings': _parseObjectList(asMap['pathBindings']),
      };
    }
    return <String, dynamic>{
      'pathGroups': <Map<String, dynamic>>[],
      'paths': <Map<String, dynamic>>[],
      'pathBindings': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> _readExternalAnimationsData(
    String absolutePath,
  ) async {
    final File file = File(absolutePath);
    if (!await file.exists()) {
      throw Exception("Missing animations file: ${file.path}");
    }
    final dynamic decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return <String, dynamic>{
        'animations': _parseObjectList(decoded['animations']),
        'animationGroups': _parseObjectList(decoded['animationGroups']),
      };
    }
    if (decoded is Map) {
      final Map<String, dynamic> asMap = Map<String, dynamic>.from(decoded);
      return <String, dynamic>{
        'animations': _parseObjectList(asMap['animations']),
        'animationGroups': _parseObjectList(asMap['animationGroups']),
      };
    }
    if (decoded is List) {
      return <String, dynamic>{
        'animations': _parseObjectList(decoded),
        'animationGroups': <Map<String, dynamic>>[],
      };
    }
    return <String, dynamic>{
      'animations': <Map<String, dynamic>>[],
      'animationGroups': <Map<String, dynamic>>[],
    };
  }

  Future<bool> _migrateProjectMediaToMediaFolder({
    required String projectDirectoryPath,
  }) async {
    final Set<String> references = <String>{};
    void addReference(String value) {
      final String normalized = _normalizeProjectRelativePath(value);
      if (normalized.isNotEmpty && _hasSupportedImageExtension(normalized)) {
        references.add(normalized);
      }
    }

    for (final asset in gameData.mediaAssets) {
      addReference(asset.fileName);
    }
    for (final animation in gameData.animations) {
      addReference(animation.mediaFile);
    }
    for (final level in gameData.levels) {
      for (final layer in level.layers) {
        addReference(layer.tilesSheetFile);
      }
      for (final sprite in level.sprites) {
        addReference(sprite.imageFile);
      }
    }

    if (references.isEmpty) {
      return false;
    }

    final Directory mediaDirectory = Directory(
      '$projectDirectoryPath${Platform.pathSeparator}$mediaFolderName',
    );
    await mediaDirectory.create(recursive: true);

    final Map<String, String> migratedByOriginal = <String, String>{};
    bool changed = false;

    for (final String original in references) {
      String migrated = original;
      if (!_isMediaRelativePath(original)) {
        final String baseName = _lastPathSegment(original);
        final String sourceAbsolutePath =
            _projectAbsolutePathForRelativePath(projectDirectoryPath, original);
        final File sourceFile = File(sourceAbsolutePath);
        final bool sourceExists = await sourceFile.exists();
        if (baseName.isNotEmpty) {
          String destinationRelativePath =
              _mediaRelativePathForBaseName(baseName);
          String destinationAbsolutePath = _projectAbsolutePathForRelativePath(
            projectDirectoryPath,
            destinationRelativePath,
          );
          final File destinationFile = File(destinationAbsolutePath);
          if (sourceExists) {
            bool shouldMoveSource = true;
            if (await destinationFile.exists()) {
              final bool sameContent = await _filesHaveSameContent(
                sourceAbsolutePath,
                destinationAbsolutePath,
              );
              if (sameContent) {
                shouldMoveSource = false;
                if (sourceAbsolutePath != destinationAbsolutePath) {
                  try {
                    await sourceFile.delete();
                  } catch (_) {}
                }
              } else {
                final String uniqueBaseName =
                    await _buildUniqueFileNameInDirectory(
                  mediaDirectory.path,
                  baseName,
                );
                destinationRelativePath =
                    _mediaRelativePathForBaseName(uniqueBaseName);
                destinationAbsolutePath = _projectAbsolutePathForRelativePath(
                  projectDirectoryPath,
                  destinationRelativePath,
                );
              }
            }
            if (shouldMoveSource) {
              await _moveFileWithinProject(
                sourceAbsolutePath: sourceAbsolutePath,
                destinationAbsolutePath: destinationAbsolutePath,
              );
            }
            migrated = destinationRelativePath;
          } else if (await destinationFile.exists()) {
            migrated = destinationRelativePath;
          }
        }
      }
      migratedByOriginal[original] = migrated;
      if (migrated != original) {
        changed = true;
      }
    }

    String migratedValue(String value) {
      final String normalized = _normalizeProjectRelativePath(value);
      if (normalized.isEmpty) {
        return value;
      }
      return migratedByOriginal[normalized] ?? normalized;
    }

    for (final asset in gameData.mediaAssets) {
      final String next = migratedValue(asset.fileName);
      if (next != asset.fileName) {
        asset.fileName = next;
        changed = true;
      }
    }
    for (final animation in gameData.animations) {
      final String next = migratedValue(animation.mediaFile);
      if (next != animation.mediaFile) {
        animation.mediaFile = next;
        changed = true;
      }
    }
    for (final level in gameData.levels) {
      for (int layerIndex = 0; layerIndex < level.layers.length; layerIndex++) {
        final GameLayer layer = level.layers[layerIndex];
        final String next = migratedValue(layer.tilesSheetFile);
        if (next != layer.tilesSheetFile) {
          level.layers[layerIndex] = GameLayer(
            name: layer.name,
            gameplayData: layer.gameplayData,
            x: layer.x,
            y: layer.y,
            depth: layer.depth,
            tilesSheetFile: next,
            tilesWidth: layer.tilesWidth,
            tilesHeight: layer.tilesHeight,
            tileMap: layer.tileMap,
            visible: layer.visible,
            groupId: layer.groupId,
          );
          changed = true;
        }
      }
      for (final sprite in level.sprites) {
        final String next = migratedValue(sprite.imageFile);
        if (next != sprite.imageFile) {
          sprite.imageFile = next;
          changed = true;
        }
      }
    }

    if (changed) {
      _disposeAndClearImageCache();
    }
    return changed;
  }

  String _canonicalJsonValue(dynamic value) {
    if (value is Map) {
      final List<String> keys = value.keys.map((k) => k.toString()).toList()
        ..sort();
      final List<String> parts = <String>[];
      for (final key in keys) {
        parts.add('${jsonEncode(key)}:${_canonicalJsonValue(value[key])}');
      }
      return '{${parts.join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJsonValue).join(',')}]';
    }
    return jsonEncode(value);
  }

  bool _projectNeedsStructureMigration({
    required Map<String, dynamic> decoded,
  }) {
    final Map<String, dynamic> normalized = gameData.toJson();
    return _canonicalJsonValue(decoded) != _canonicalJsonValue(normalized);
  }

  bool _decodedGameplayDataMigrationNeeded({
    required Map<String, dynamic> decoded,
  }) {
    final dynamic rawLevels = decoded['levels'];
    if (rawLevels is! List) {
      return false;
    }
    for (final dynamic rawLevel in rawLevels) {
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }
      if (rawLevel['gameplayData'] is! String) {
        return true;
      }

      final dynamic rawLayers = rawLevel['layers'];
      if (rawLayers is List) {
        for (final dynamic rawLayer in rawLayers) {
          if (rawLayer is! Map) {
            continue;
          }
          if (rawLayer['gameplayData'] is! String) {
            return true;
          }
        }
      }

      final dynamic rawSprites = rawLevel['sprites'];
      if (rawSprites is List) {
        for (final dynamic rawSprite in rawSprites) {
          if (rawSprite is! Map) {
            continue;
          }
          if (rawSprite['gameplayData'] is! String) {
            return true;
          }
        }
      }

      final dynamic rawZones = rawLevel['zones'];
      if (rawZones is! List) {
        continue;
      }
      for (final dynamic rawZone in rawZones) {
        if (rawZone is! Map) {
          continue;
        }
        final dynamic gameplayData = rawZone['gameplayData'];
        if (gameplayData is! String) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _hydrateExternalTileMapsIntoDecodedGameData({
    required Map<String, dynamic> decoded,
    required String projectDirectoryPath,
  }) async {
    final dynamic rawLevels = decoded['levels'];
    if (rawLevels is! List) {
      return;
    }
    for (int levelIndex = 0; levelIndex < rawLevels.length; levelIndex++) {
      final dynamic rawLevel = rawLevels[levelIndex];
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }
      final dynamic rawLayers = rawLevel['layers'];
      if (rawLayers is! List) {
        continue;
      }
      for (int layerIndex = 0; layerIndex < rawLayers.length; layerIndex++) {
        final dynamic rawLayer = rawLayers[layerIndex];
        if (rawLayer is! Map<String, dynamic>) {
          continue;
        }
        final dynamic rawReference = rawLayer[tileMapFileFieldName];
        if (rawReference is! String) {
          throw Exception(
            'Unsupported project format: layer tilemaps must use "$tileMapFileFieldName".',
          );
        }
        final String relativePath = _normalizeProjectRelativePath(rawReference);
        if (relativePath.isEmpty ||
            !relativePath.toLowerCase().endsWith('.json')) {
          throw Exception(
            'Invalid "$tileMapFileFieldName" value for level $levelIndex, layer $layerIndex.',
          );
        }
        final List<List<int>> tileMapRows = await _readExternalTileMapRows(
          _projectAbsolutePathForRelativePath(
            projectDirectoryPath,
            relativePath,
          ),
        );
        rawLayer[tileMapFileFieldName] = relativePath;
        rawLayer['tileMap'] = tileMapRows;
      }
    }
  }

  Future<void> _hydrateExternalZonesIntoDecodedGameData({
    required Map<String, dynamic> decoded,
    required String projectDirectoryPath,
  }) async {
    final dynamic rawLevels = decoded['levels'];
    if (rawLevels is! List) {
      return;
    }

    for (int levelIndex = 0; levelIndex < rawLevels.length; levelIndex++) {
      final dynamic rawLevel = rawLevels[levelIndex];
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }

      final dynamic rawReference = rawLevel[zonesFileFieldName];
      if (rawReference is! String) {
        throw Exception(
          'Unsupported project format: level zones must use "$zonesFileFieldName".',
        );
      }
      final String relativePath = _normalizeProjectRelativePath(rawReference);
      if (relativePath.isEmpty ||
          !relativePath.toLowerCase().endsWith('.json')) {
        throw Exception(
          'Invalid "$zonesFileFieldName" value for level $levelIndex.',
        );
      }

      final Map<String, dynamic> zonesData = await _readExternalZonesData(
        _projectAbsolutePathForRelativePath(
          projectDirectoryPath,
          relativePath,
        ),
      );
      rawLevel[zonesFileFieldName] = relativePath;
      rawLevel['zones'] = zonesData['zones'];
      rawLevel['zoneGroups'] = zonesData['zoneGroups'];
    }
  }

  Future<bool> _hydrateExternalPathsIntoDecodedGameData({
    required Map<String, dynamic> decoded,
    required String projectDirectoryPath,
  }) async {
    final dynamic rawLevels = decoded['levels'];
    if (rawLevels is! List) {
      return false;
    }

    bool needsPathsExternalization = false;
    for (int levelIndex = 0; levelIndex < rawLevels.length; levelIndex++) {
      final dynamic rawLevel = rawLevels[levelIndex];
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }

      final dynamic rawReference = rawLevel[pathsFileFieldName];
      if (rawReference is String) {
        final String relativePath = _normalizeProjectRelativePath(rawReference);
        if (relativePath.isEmpty ||
            !relativePath.toLowerCase().endsWith('.json')) {
          throw Exception(
            'Invalid "$pathsFileFieldName" value for level $levelIndex.',
          );
        }
        final Map<String, dynamic> pathsData = await _readExternalPathsData(
          _projectAbsolutePathForRelativePath(
            projectDirectoryPath,
            relativePath,
          ),
        );
        rawLevel[pathsFileFieldName] = relativePath;
        rawLevel['pathGroups'] = pathsData['pathGroups'];
        rawLevel['paths'] = pathsData['paths'];
        rawLevel['pathBindings'] = pathsData['pathBindings'];
        continue;
      }

      if (rawReference == null) {
        final List<Map<String, dynamic>> pathGroups = _parseObjectList(
          rawLevel['pathGroups'],
        );
        final List<Map<String, dynamic>> paths = _parseObjectList(
          rawLevel['paths'],
        );
        final List<Map<String, dynamic>> pathBindings = _parseObjectList(
          rawLevel['pathBindings'],
        );
        rawLevel[pathsFileFieldName] = _defaultPathsRelativePath(levelIndex);
        rawLevel['pathGroups'] = pathGroups;
        rawLevel['paths'] = paths;
        rawLevel['pathBindings'] = pathBindings;
        needsPathsExternalization = true;
        continue;
      }

      throw Exception(
        'Unsupported project format: "$pathsFileFieldName" must be a string.',
      );
    }
    return needsPathsExternalization;
  }

  Future<bool> _hydrateExternalAnimationsIntoDecodedGameData({
    required Map<String, dynamic> decoded,
    required String projectDirectoryPath,
  }) async {
    final dynamic rawReference = decoded[animationsFileFieldName];
    if (rawReference is String) {
      final String relativePath = _normalizeProjectRelativePath(rawReference);
      if (relativePath.isEmpty ||
          !relativePath.toLowerCase().endsWith('.json')) {
        throw Exception('Invalid "$animationsFileFieldName" value.');
      }
      final Map<String, dynamic> animationsData =
          await _readExternalAnimationsData(
        _projectAbsolutePathForRelativePath(
          projectDirectoryPath,
          relativePath,
        ),
      );
      decoded[animationsFileFieldName] = relativePath;
      decoded['animations'] = animationsData['animations'];
      decoded['animationGroups'] = animationsData['animationGroups'];
      return false;
    }
    if (rawReference != null) {
      throw Exception(
        'Unsupported project format: "$animationsFileFieldName" must be a string.',
      );
    }

    if (!decoded.containsKey('animations')) {
      decoded['animations'] = <Map<String, dynamic>>[];
    }
    if (!decoded.containsKey('animationGroups')) {
      decoded['animationGroups'] = <Map<String, dynamic>>[];
    }
    return true;
  }

  Future<Set<String>> _writeExternalTileMapsAndStripInlineFromGameData({
    required Map<String, dynamic> encoded,
    required String projectDirectoryPath,
  }) async {
    final Set<String> writtenRelativePaths = <String>{};
    final dynamic rawLevels = encoded['levels'];
    if (rawLevels is! List) {
      return writtenRelativePaths;
    }
    for (int levelIndex = 0; levelIndex < rawLevels.length; levelIndex++) {
      final dynamic rawLevel = rawLevels[levelIndex];
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }
      final dynamic rawLayers = rawLevel['layers'];
      if (rawLayers is! List) {
        continue;
      }
      for (int layerIndex = 0; layerIndex < rawLayers.length; layerIndex++) {
        final dynamic rawLayer = rawLayers[layerIndex];
        if (rawLayer is! Map<String, dynamic>) {
          continue;
        }
        final List<List<int>> tileMapRows =
            _parseTileMapRows(rawLayer['tileMap']);
        final String relativePath = _normalizedTileMapRelativePath(
          rawLayer[tileMapFileFieldName],
          levelIndex: levelIndex,
          layerIndex: layerIndex,
        );
        final String absolutePath = _projectAbsolutePathForRelativePath(
          projectDirectoryPath,
          relativePath,
        );
        final File tileMapFile = File(absolutePath);
        await tileMapFile.parent.create(recursive: true);
        final String tileMapOutput = await _formatMapAsGameJson(
          <String, dynamic>{'tileMap': tileMapRows},
        );
        await tileMapFile.writeAsString(tileMapOutput);
        writtenRelativePaths.add(relativePath);
        rawLayer[tileMapFileFieldName] = relativePath;
        rawLayer.remove('tileMap');
      }
    }
    return writtenRelativePaths;
  }

  Future<Set<String>> _writeExternalZonesAndStripInlineFromGameData({
    required Map<String, dynamic> encoded,
    required String projectDirectoryPath,
  }) async {
    final Set<String> writtenRelativePaths = <String>{};
    final dynamic rawLevels = encoded['levels'];
    if (rawLevels is! List) {
      return writtenRelativePaths;
    }

    for (int levelIndex = 0; levelIndex < rawLevels.length; levelIndex++) {
      final dynamic rawLevel = rawLevels[levelIndex];
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }

      final List<Map<String, dynamic>> zones =
          _parseObjectList(rawLevel['zones']);
      final List<Map<String, dynamic>> zoneGroups =
          _parseObjectList(rawLevel['zoneGroups']);
      final String relativePath = _normalizedZonesRelativePath(
        rawLevel[zonesFileFieldName],
        levelIndex: levelIndex,
      );
      final String absolutePath = _projectAbsolutePathForRelativePath(
        projectDirectoryPath,
        relativePath,
      );
      final File zonesFile = File(absolutePath);
      await zonesFile.parent.create(recursive: true);
      final String zonesOutput = await _formatMapAsGameJson(
        <String, dynamic>{
          'zoneGroups': zoneGroups,
          'zones': zones,
        },
      );
      await zonesFile.writeAsString(zonesOutput);
      writtenRelativePaths.add(relativePath);
      rawLevel[zonesFileFieldName] = relativePath;
      rawLevel.remove('zones');
      rawLevel.remove('zoneGroups');
    }

    return writtenRelativePaths;
  }

  Future<Set<String>> _writeExternalPathsAndStripInlineFromGameData({
    required Map<String, dynamic> encoded,
    required String projectDirectoryPath,
  }) async {
    final Set<String> writtenRelativePaths = <String>{};
    final dynamic rawLevels = encoded['levels'];
    if (rawLevels is! List) {
      return writtenRelativePaths;
    }

    for (int levelIndex = 0; levelIndex < rawLevels.length; levelIndex++) {
      final dynamic rawLevel = rawLevels[levelIndex];
      if (rawLevel is! Map<String, dynamic>) {
        continue;
      }

      final List<Map<String, dynamic>> pathGroups = _parseObjectList(
        rawLevel['pathGroups'],
      );
      final List<Map<String, dynamic>> paths = _parseObjectList(
        rawLevel['paths'],
      );
      final List<Map<String, dynamic>> pathBindings = _parseObjectList(
        rawLevel['pathBindings'],
      );
      final String relativePath = _normalizedPathsRelativePath(
        rawLevel[pathsFileFieldName],
        levelIndex: levelIndex,
      );
      final String absolutePath = _projectAbsolutePathForRelativePath(
        projectDirectoryPath,
        relativePath,
      );
      final File pathsFile = File(absolutePath);
      await pathsFile.parent.create(recursive: true);
      final String pathsOutput = await _formatMapAsGameJson(
        <String, dynamic>{
          'pathGroups': pathGroups,
          'paths': paths,
          'pathBindings': pathBindings,
        },
      );
      await pathsFile.writeAsString(pathsOutput);
      writtenRelativePaths.add(relativePath);
      rawLevel[pathsFileFieldName] = relativePath;
      rawLevel.remove('pathGroups');
      rawLevel.remove('paths');
      rawLevel.remove('pathBindings');
    }

    return writtenRelativePaths;
  }

  Future<String> _writeExternalAnimationsAndStripInlineFromGameData({
    required Map<String, dynamic> encoded,
    required String projectDirectoryPath,
  }) async {
    final List<Map<String, dynamic>> animations =
        _parseObjectList(encoded['animations']);
    final List<Map<String, dynamic>> animationGroups =
        _parseObjectList(encoded['animationGroups']);
    final String relativePath = _normalizedAnimationsRelativePath(
      encoded[animationsFileFieldName],
    );
    final String absolutePath = _projectAbsolutePathForRelativePath(
      projectDirectoryPath,
      relativePath,
    );
    final File animationsFile = File(absolutePath);
    await animationsFile.parent.create(recursive: true);
    final String animationsOutput = await _formatMapAsGameJson(
      <String, dynamic>{
        'animationGroups': animationGroups,
        'animations': animations,
      },
    );
    await animationsFile.writeAsString(animationsOutput);
    encoded[animationsFileFieldName] = relativePath;
    encoded.remove('animations');
    encoded.remove('animationGroups');
    return relativePath;
  }

  Future<void> _cleanupStaleExternalTileMapFiles({
    required String projectDirectoryPath,
    required Set<String> keepRelativePaths,
  }) async {
    final Directory tileMapsDirectory = Directory(
      '$projectDirectoryPath${Platform.pathSeparator}$tilemapsFolderName',
    );
    if (!await tileMapsDirectory.exists()) {
      return;
    }
    await for (final FileSystemEntity entity
        in tileMapsDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final String relativePath = _relativePathFromProjectAbsolutePath(
        projectDirectoryPath,
        entity.path,
      );
      if (relativePath.isEmpty || keepRelativePaths.contains(relativePath)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  Future<void> _cleanupStaleExternalZoneFiles({
    required String projectDirectoryPath,
    required Set<String> keepRelativePaths,
  }) async {
    final Directory zonesDirectory = Directory(
      '$projectDirectoryPath${Platform.pathSeparator}$zonesFolderName',
    );
    if (!await zonesDirectory.exists()) {
      return;
    }
    await for (final FileSystemEntity entity
        in zonesDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final String relativePath = _relativePathFromProjectAbsolutePath(
        projectDirectoryPath,
        entity.path,
      );
      if (relativePath.isEmpty || keepRelativePaths.contains(relativePath)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  Future<void> _cleanupStaleExternalPathFiles({
    required String projectDirectoryPath,
    required Set<String> keepRelativePaths,
  }) async {
    final Directory pathsDirectory = Directory(
      '$projectDirectoryPath${Platform.pathSeparator}$pathsFolderName',
    );
    if (!await pathsDirectory.exists()) {
      return;
    }
    await for (final FileSystemEntity entity
        in pathsDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final String relativePath = _relativePathFromProjectAbsolutePath(
        projectDirectoryPath,
        entity.path,
      );
      if (relativePath.isEmpty || keepRelativePaths.contains(relativePath)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  Future<void> _cleanupStaleExternalAnimationFiles({
    required String projectDirectoryPath,
    required Set<String> keepRelativePaths,
  }) async {
    final Directory animationsDirectory = Directory(
      '$projectDirectoryPath${Platform.pathSeparator}$animationsFolderName',
    );
    if (!await animationsDirectory.exists()) {
      return;
    }
    await for (final FileSystemEntity entity
        in animationsDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final String relativePath = _relativePathFromProjectAbsolutePath(
        projectDirectoryPath,
        entity.path,
      );
      if (relativePath.isEmpty || keepRelativePaths.contains(relativePath)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  String _projectAbsolutePathForRelativePath(
    String projectDirectoryPath,
    String relativePath,
  ) {
    return '$projectDirectoryPath${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}';
  }

  bool _hasSupportedImageExtension(String fileName) {
    final String lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }

  Future<bool> _filesHaveSameContent(String pathA, String pathB) async {
    final File fileA = File(pathA);
    final File fileB = File(pathB);
    if (!await fileA.exists() || !await fileB.exists()) {
      return false;
    }
    final int lengthA = await fileA.length();
    final int lengthB = await fileB.length();
    if (lengthA != lengthB) {
      return false;
    }
    final List<int> bytesA = await fileA.readAsBytes();
    final List<int> bytesB = await fileB.readAsBytes();
    if (bytesA.length != bytesB.length) {
      return false;
    }
    for (int i = 0; i < bytesA.length; i++) {
      if (bytesA[i] != bytesB[i]) {
        return false;
      }
    }
    return true;
  }

  Set<String> referencedMediaFileNames() {
    final Set<String> references = <String>{};

    void addReference(String value) {
      final String normalized = _normalizeProjectRelativePath(value);
      if (normalized.isNotEmpty) {
        references.add(normalized);
      }
    }

    for (final asset in gameData.mediaAssets) {
      addReference(asset.fileName);
    }
    for (final animation in gameData.animations) {
      addReference(animation.mediaFile);
    }
    for (final level in gameData.levels) {
      for (final layer in level.layers) {
        addReference(layer.tilesSheetFile);
      }
      for (final sprite in level.sprites) {
        addReference(sprite.imageFile);
      }
    }

    return references;
  }

  Future<void> deleteProjectMediaFileIfUnreferenced(String fileName) async {
    if (selectedProject == null || filePath == "") {
      return;
    }

    final String normalized = _normalizeProjectRelativePath(fileName);
    if (normalized.isEmpty || !_hasSupportedImageExtension(normalized)) {
      return;
    }
    if (referencedMediaFileNames().contains(normalized)) {
      return;
    }

    final String absolutePath =
        _projectAbsolutePathForRelativePath(filePath, normalized);
    final File mediaFile = File(absolutePath);
    if (!await mediaFile.exists()) {
      return;
    }

    try {
      await mediaFile.delete();
      _removeImagesFromCache(<String>[
        fileName,
        normalized,
      ]);
    } catch (e) {
      if (kDebugMode) {
        print("Error deleting orphan media file \"$normalized\": $e");
      }
    }
  }

  void _resetWorkingProjectData() {
    _clearAutosaveState();
    selectedProjectId = "";
    gameData = GameData(name: "", levels: []);
    filePath = "";
    fileName = "";
    selectedLevel = -1;
    selectedLayer = -1;
    selectedLayerIndices = <int>{};
    selectedZone = -1;
    selectedZoneIndices = <int>{};
    selectedSprite = -1;
    selectedSpriteIndices = <int>{};
    selectedPath = -1;
    selectedAnimation = -1;
    selectedAnimationHitBox = -1;
    animationRigSelectionAnimationId = "";
    animationRigSelectedFrames = <int>[];
    animationRigSelectionStartFrame = -1;
    animationRigSelectionEndFrame = -1;
    animationRigActiveFrame = -1;
    selectedMedia = -1;
    animationSelectionStartFrame = -1;
    animationSelectionEndFrame = -1;
    selectedTileIndex = -1;
    selectedTilePattern = [];
    tilemapEraserEnabled = false;
    tilesetSelectionColStart = -1;
    tilesetSelectionRowStart = -1;
    tilesetSelectionColEnd = -1;
    tilesetSelectionRowEnd = -1;
    layersViewScale = 1.0;
    layersViewOffset = Offset.zero;
    layerDragOffset = Offset.zero;
    viewportDragOffset = Offset.zero;
    viewportResizeOffset = Offset.zero;
    viewportIsDragging = false;
    viewportIsResizing = false;
    viewportPreviewX = 0;
    viewportPreviewY = 0;
    viewportPreviewWidth = 320;
    viewportPreviewHeight = 180;
    viewportPreviewLevel = -1;
    _undoStack.clear();
    _redoStack.clear();
    _clearUndoGroupingState();
    _disposeAndClearImageCache();
  }

  Future<String> _formatMapAsGameJson(Map<String, dynamic> data) async {
    final String jsonData = jsonEncode(data);
    final String prettyJson =
        const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonData));

    final numberArrayRegex = RegExp(r'\[\s*((?:-?\d+\s*,\s*)*-?\d+\s*)\]');
    return prettyJson.replaceAllMapped(numberArrayRegex, (match) {
      final numbers = match.group(1)!;
      return '[${numbers.replaceAll(RegExp(r'\s+'), ' ').trim()}]';
    });
  }

  Future<String?> pickDirectory({
    required String dialogTitle,
    String? initialDirectory,
  }) async {
    final String? selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );
    if (selectedPath == null) {
      return null;
    }
    final String normalized = _normalizeProjectFolderPath(selectedPath);
    return normalized.isEmpty ? null : normalized;
  }

  Future<String> createProject({
    required String workingDirectoryPath,
    String? projectName,
    String? projectDescription,
  }) async {
    await flushPendingAutosave();
    if (projectsPath == "") {
      await initializeStorage();
    }

    final String normalizedProjectPath =
        _normalizeProjectFolderPath(workingDirectoryPath);
    if (normalizedProjectPath.isEmpty) {
      throw Exception("Invalid project folder path");
    }
    final Directory projectDirectory = Directory(normalizedProjectPath);
    await projectDirectory.create(recursive: true);
    final File existingProjectFile = File(
      "$normalizedProjectPath${Platform.pathSeparator}$gameFileName",
    );
    if (await existingProjectFile.exists()) {
      throw Exception(
        "A project already exists in \"$normalizedProjectPath\". "
        "Use Add Existing instead.",
      );
    }

    final String defaultName = projectName?.trim().isNotEmpty == true
        ? projectName!.trim()
        : "New Project";
    final String defaultDescription = projectDescription?.trim() ?? '';
    final String projectPath = normalizedProjectPath;
    final StoredProject newProject = StoredProject.fromPath(
      folderPath: projectPath,
      name: defaultName,
      description: defaultDescription,
    );
    projects.removeWhere((StoredProject item) => item.id == projectPath);
    projects.add(newProject);
    _knownProjectPaths.remove(projectPath);
    _knownProjectPaths.add(projectPath);
    _knownProjectNamesByPath[projectPath] = defaultName;
    final String? bookmark = await _createSecurityBookmarkForPath(projectPath);
    if (bookmark != null && bookmark.isNotEmpty) {
      _projectBookmarksByPath[projectPath] = bookmark;
    }
    missingProjectPaths.remove(projectPath);
    selectedProjectId = newProject.id;

    gameData = GameData(
      name: defaultName,
      description: defaultDescription,
      levels: [],
    );
    selectedLevel = -1;
    selectedLayer = -1;
    selectedLayerIndices = <int>{};
    selectedZone = -1;
    selectedZoneIndices = <int>{};
    selectedSprite = -1;
    selectedSpriteIndices = <int>{};
    selectedPath = -1;
    selectedAnimation = -1;
    selectedAnimationHitBox = -1;
    animationRigSelectionAnimationId = "";
    animationRigSelectedFrames = <int>[];
    animationRigSelectionStartFrame = -1;
    animationRigSelectionEndFrame = -1;
    animationRigActiveFrame = -1;
    selectedMedia = -1;
    animationSelectionStartFrame = -1;
    animationSelectionEndFrame = -1;
    selectedTileIndex = -1;
    selectedTilePattern = [];
    tilemapEraserEnabled = false;
    tilesetSelectionColStart = -1;
    tilesetSelectionRowStart = -1;
    tilesetSelectionColEnd = -1;
    tilesetSelectionRowEnd = -1;
    _undoStack.clear();
    _redoStack.clear();
    _clearUndoGroupingState();
    _clearAutosaveState();
    _disposeAndClearImageCache();
    viewportDragOffset = Offset.zero;
    viewportResizeOffset = Offset.zero;
    viewportIsDragging = false;
    viewportIsResizing = false;
    viewportPreviewX = 0;
    viewportPreviewY = 0;
    viewportPreviewWidth = 320;
    viewportPreviewHeight = 180;
    viewportPreviewLevel = -1;

    filePath = projectPath;
    fileName = gameFileName;
    await saveGame();
    await _syncProjectsWithDisk();
    projectStatusMessage = "Created project \"$defaultName\"";
    notifyListeners();
    return newProject.id;
  }

  Future<String?> addExistingProjectFromFolder({
    String? initialDirectory,
  }) async {
    final String? projectFolderPath = await pickDirectory(
      dialogTitle: "Select existing project folder",
      initialDirectory: initialDirectory ?? projectsPath,
    );
    if (projectFolderPath == null) {
      return null;
    }
    return addExistingProjectFromPath(projectFolderPath);
  }

  Future<String?> addExistingProjectFromPath(String projectFolderPath) async {
    await flushPendingAutosave();
    final String normalizedPath =
        _normalizeProjectFolderPath(projectFolderPath);
    if (normalizedPath.isEmpty) {
      projectStatusMessage = "Invalid project folder path";
      notifyListeners();
      return null;
    }

    final File gameFile =
        File("$normalizedPath${Platform.pathSeparator}$gameFileName");
    if (!await gameFile.exists()) {
      projectStatusMessage =
          "No $gameFileName found in selected folder: $normalizedPath";
      notifyListeners();
      return null;
    }

    if (!_knownProjectPaths.contains(normalizedPath)) {
      _knownProjectPaths.add(normalizedPath);
    }
    final String inferredName = await _readProjectNameFromDisk(gameFile) ??
        _lastPathSegment(normalizedPath);
    _knownProjectNamesByPath[normalizedPath] = inferredName;
    final String? bookmark =
        await _createSecurityBookmarkForPath(normalizedPath);
    if (bookmark != null && bookmark.isNotEmpty) {
      _projectBookmarksByPath[normalizedPath] = bookmark;
    }
    missingProjectPaths.remove(normalizedPath);
    await _syncProjectsWithDisk();
    selectedProjectId = normalizedPath;
    await openProject(normalizedPath, notify: false);
    projectStatusMessage = "Added existing project from \"$normalizedPath\"";
    notifyListeners();
    return normalizedPath;
  }

  Future<void> removeKnownProjectPath(String projectFolderPath) async {
    final String normalizedPath =
        _normalizeProjectFolderPath(projectFolderPath);
    if (normalizedPath.isEmpty) {
      return;
    }
    _knownProjectPaths.removeWhere((path) => path == normalizedPath);
    _projectBookmarksByPath.remove(normalizedPath);
    _knownProjectNamesByPath.remove(normalizedPath);
    missingProjectPaths.removeWhere((path) => path == normalizedPath);
    projects.removeWhere((project) => project.id == normalizedPath);
    if (selectedProjectId == normalizedPath) {
      _resetWorkingProjectData();
    }
    await _saveProjectsIndex();
    notifyListeners();
  }

  Future<void> removeMissingProjectPath(String projectFolderPath) async {
    await removeKnownProjectPath(projectFolderPath);
  }

  Future<bool> relinkMissingProjectPath({
    required String missingProjectPath,
    required String replacementProjectPath,
  }) async {
    final String normalizedMissingPath =
        _normalizeProjectFolderPath(missingProjectPath);
    final String normalizedReplacementPath =
        _normalizeProjectFolderPath(replacementProjectPath);
    if (normalizedMissingPath.isEmpty || normalizedReplacementPath.isEmpty) {
      return false;
    }
    final File replacementGameFile = File(
      "$normalizedReplacementPath${Platform.pathSeparator}$gameFileName",
    );
    if (!await replacementGameFile.exists()) {
      return false;
    }
    if (normalizedMissingPath != normalizedReplacementPath &&
        _knownProjectPaths.contains(normalizedReplacementPath)) {
      return false;
    }

    final int index = _knownProjectPaths.indexOf(normalizedMissingPath);
    if (index >= 0) {
      _knownProjectPaths[index] = normalizedReplacementPath;
    } else {
      _knownProjectPaths.add(normalizedReplacementPath);
    }
    final String preservedName =
        (_knownProjectNamesByPath[normalizedMissingPath] ?? '').trim();
    final String replacementName =
        await _readProjectNameFromDisk(replacementGameFile) ??
            (preservedName.isNotEmpty
                ? preservedName
                : _lastPathSegment(normalizedReplacementPath));
    _knownProjectNamesByPath.remove(normalizedMissingPath);
    _knownProjectNamesByPath[normalizedReplacementPath] = replacementName;
    _projectBookmarksByPath.remove(normalizedMissingPath);
    final String? bookmark =
        await _createSecurityBookmarkForPath(normalizedReplacementPath);
    if (bookmark != null && bookmark.isNotEmpty) {
      _projectBookmarksByPath[normalizedReplacementPath] = bookmark;
    }
    missingProjectPaths.remove(normalizedMissingPath);
    if (selectedProjectId == normalizedMissingPath) {
      selectedProjectId = normalizedReplacementPath;
    }

    await _syncProjectsWithDisk();
    selectedProjectId = normalizedReplacementPath;
    await openProject(normalizedReplacementPath, notify: false);
    projectStatusMessage = "Project relinked to \"$normalizedReplacementPath\"";
    notifyListeners();
    return true;
  }

  Future<bool> renameProject(String projectId, String newName) async {
    return updateProjectInfo(
      projectId,
      newName: newName,
    );
  }

  Future<bool> updateProjectInfo(
    String projectId, {
    required String newName,
    String? newDescription,
  }) async {
    final String cleanName = newName.trim();
    if (cleanName.isEmpty) {
      return false;
    }
    final StoredProject? project = _findProjectById(projectId);
    if (project == null) {
      return false;
    }
    final String cleanDescription = newDescription == null
        ? project.description.trim()
        : newDescription.trim();

    project.name = cleanName;
    project.description = cleanDescription;
    project.updatedAt = DateTime.now().toUtc().toIso8601String();
    _knownProjectNamesByPath[project.folderPath] = cleanName;

    final String projectPath = project.folderPath;
    final File file =
        File("$projectPath${Platform.pathSeparator}$gameFileName");
    if (await file.exists()) {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        decoded['name'] = cleanName;
        decoded['description'] = cleanDescription;
        final String output = await _formatMapAsGameJson(decoded);
        await file.writeAsString(output);
      }
    }

    if (selectedProjectId == projectId) {
      gameData = GameData(
        name: cleanName,
        description: cleanDescription,
        levels: gameData.levels,
        levelGroups: gameData.levelGroups,
        mediaAssets: gameData.mediaAssets,
        mediaGroups: gameData.mediaGroups,
        animations: gameData.animations,
        animationGroups: gameData.animationGroups,
        zoneTypes: gameData.zoneTypes,
      );
    }

    await _saveProjectsIndex();
    projectStatusMessage = "Updated project \"$cleanName\"";
    notifyListeners();
    return true;
  }

  Future<bool> relocateProject({
    required String projectId,
    required String destinationRootPath,
    required bool deleteOldFolderIfCopied,
  }) async {
    await flushPendingAutosave();
    final StoredProject? project = _findProjectById(projectId);
    if (project == null) {
      return false;
    }

    final String destinationProjectPath =
        _normalizeProjectFolderPath(destinationRootPath);
    if (destinationProjectPath.isEmpty) {
      return false;
    }

    final String sourcePath = _normalizeProjectFolderPath(project.folderPath);
    if (sourcePath == destinationProjectPath) {
      return false;
    }

    try {
      final Directory destinationDirectory = Directory(destinationProjectPath);
      await destinationDirectory.create(recursive: true);
      final File existingDestinationGameFile = File(
        "$destinationProjectPath${Platform.pathSeparator}$gameFileName",
      );

      // If destination already has project data, relink directly.
      if (!await existingDestinationGameFile.exists()) {
        bool destinationHasEntries = false;
        await for (final FileSystemEntity _ in destinationDirectory.list(
          recursive: false,
          followLinks: false,
        )) {
          destinationHasEntries = true;
          break;
        }
        if (destinationHasEntries) {
          throw Exception(
            "Destination folder must be empty or already contain "
            "$gameFileName: $destinationProjectPath",
          );
        }

        await _copyDirectoryRecursively(
          source: Directory(sourcePath),
          destination: destinationDirectory,
        );

        final File copiedGameFile = File(
          "$destinationProjectPath${Platform.pathSeparator}$gameFileName",
        );
        if (!await copiedGameFile.exists()) {
          throw Exception("Copy failed: missing $gameFileName in destination");
        }
      }

      if (deleteOldFolderIfCopied) {
        try {
          await Directory(sourcePath).delete(recursive: true);
        } catch (_) {}
      }

      if (sourcePath != destinationProjectPath &&
          _knownProjectPaths.contains(destinationProjectPath)) {
        _knownProjectPaths.removeWhere((String item) => item == sourcePath);
      } else {
        final int knownIndex = _knownProjectPaths.indexOf(sourcePath);
        if (knownIndex >= 0) {
          _knownProjectPaths[knownIndex] = destinationProjectPath;
        } else {
          _knownProjectPaths.add(destinationProjectPath);
        }
      }
      _knownProjectPaths.removeWhere((String item) => item == sourcePath);
      if (!_knownProjectPaths.contains(destinationProjectPath)) {
        _knownProjectPaths.add(destinationProjectPath);
      }
      final File destinationGameFile = File(
        "$destinationProjectPath${Platform.pathSeparator}$gameFileName",
      );
      final String destinationProjectName =
          await _readProjectNameFromDisk(destinationGameFile) ?? project.name;
      _knownProjectNamesByPath.remove(sourcePath);
      _knownProjectNamesByPath[destinationProjectPath] = destinationProjectName;
      _projectBookmarksByPath.remove(sourcePath);
      final String? bookmark =
          await _createSecurityBookmarkForPath(destinationProjectPath);
      if (bookmark != null && bookmark.isNotEmpty) {
        _projectBookmarksByPath[destinationProjectPath] = bookmark;
      }
      projects.removeWhere((StoredProject item) => item.id == sourcePath);
      missingProjectPaths.remove(sourcePath);

      selectedProjectId = destinationProjectPath;
      await _syncProjectsWithDisk();
      await openProject(destinationProjectPath, notify: false);
      projectStatusMessage = deleteOldFolderIfCopied
          ? "Moved project to \"$destinationProjectPath\""
          : "Copied project to \"$destinationProjectPath\"";
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("Error relocating project: $e");
      }
      projectStatusMessage = "Change folder failed: $e";
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteProject(
    String projectId, {
    bool deleteFolder = true,
  }) async {
    await flushPendingAutosave();
    final StoredProject? project = _findProjectById(projectId);
    if (project == null) {
      return false;
    }

    try {
      if (deleteFolder) {
        final Directory projectDirectory = Directory(project.folderPath);
        if (await projectDirectory.exists()) {
          await projectDirectory.delete(recursive: true);
        }
      }
      _knownProjectPaths.removeWhere((path) => path == project.folderPath);
      _projectBookmarksByPath.remove(project.folderPath);
      _knownProjectNamesByPath.remove(project.folderPath);
      missingProjectPaths.removeWhere((path) => path == project.folderPath);
      projects.removeWhere((item) => item.id == projectId);
      if (selectedProjectId == projectId) {
        _resetWorkingProjectData();
      }
      await _saveProjectsIndex();
      projectStatusMessage = deleteFolder
          ? "Deleted project \"${project.name}\" and its folder"
          : "Unlinked project \"${project.name}\" (folder kept)";
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("Error deleting project: $e");
      }
      projectStatusMessage = "Delete failed: $e";
      notifyListeners();
      return false;
    }
  }

  Future<void> openProject(String projectId, {bool notify = true}) async {
    try {
      await flushPendingAutosave();
      final StoredProject? project = _findProjectById(projectId);
      if (project == null) {
        return;
      }

      final String projectPath = project.folderPath;
      final bool hasSecurityAccess =
          await _ensureProjectSecurityAccess(projectPath);
      if (!hasSecurityAccess && _supportsSecurityBookmarks) {
        throw Exception(
          "Security-scoped access unavailable for: $projectPath",
        );
      }
      final File file =
          File("$projectPath${Platform.pathSeparator}$gameFileName");
      if (!await file.exists()) {
        throw Exception("Project file not found in: ${file.path}");
      }

      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw Exception("Invalid game_data.json structure");
      }
      await _hydrateExternalTileMapsIntoDecodedGameData(
        decoded: decoded,
        projectDirectoryPath: projectPath,
      );
      await _hydrateExternalZonesIntoDecodedGameData(
        decoded: decoded,
        projectDirectoryPath: projectPath,
      );
      final bool needsPathsExternalization =
          await _hydrateExternalPathsIntoDecodedGameData(
        decoded: decoded,
        projectDirectoryPath: projectPath,
      );
      final bool needsAnimationsExternalization =
          await _hydrateExternalAnimationsIntoDecodedGameData(
        decoded: decoded,
        projectDirectoryPath: projectPath,
      );
      final bool needsGameplayDataMigration =
          _decodedGameplayDataMigrationNeeded(
        decoded: decoded,
      );

      gameData = GameData.fromJson(decoded);
      final bool migratedStructure = needsPathsExternalization ||
          needsAnimationsExternalization ||
          needsGameplayDataMigration ||
          _projectNeedsStructureMigration(
            decoded: decoded,
          );
      selectedProjectId = projectId;
      filePath = projectPath;
      fileName = gameFileName;
      final bool migratedMedia = await _migrateProjectMediaToMediaFolder(
        projectDirectoryPath: projectPath,
      );
      if (migratedMedia || migratedStructure) {
        await _saveGameInternal(notifyOnSuccess: false);
      }
      selectedLevel = -1;
      selectedLayer = -1;
      selectedLayerIndices = <int>{};
      selectedZone = -1;
      selectedZoneIndices = <int>{};
      selectedSprite = -1;
      selectedSpriteIndices = <int>{};
      selectedPath = -1;
      selectedAnimation = -1;
      selectedAnimationHitBox = -1;
      animationRigSelectionAnimationId = "";
      animationRigSelectedFrames = <int>[];
      animationRigSelectionStartFrame = -1;
      animationRigSelectionEndFrame = -1;
      animationRigActiveFrame = -1;
      selectedMedia = -1;
      animationSelectionStartFrame = -1;
      animationSelectionEndFrame = -1;
      selectedTileIndex = -1;
      selectedTilePattern = [];
      tilemapEraserEnabled = false;
      tilesetSelectionColStart = -1;
      tilesetSelectionRowStart = -1;
      tilesetSelectionColEnd = -1;
      tilesetSelectionRowEnd = -1;
      _undoStack.clear();
      _redoStack.clear();
      _clearUndoGroupingState();
      _clearAutosaveState();
      _disposeAndClearImageCache();
      viewportDragOffset = Offset.zero;
      viewportResizeOffset = Offset.zero;
      viewportIsDragging = false;
      viewportIsResizing = false;
      viewportPreviewX = 0;
      viewportPreviewY = 0;
      viewportPreviewWidth = 320;
      viewportPreviewHeight = 180;
      viewportPreviewLevel = -1;
      if (gameData.name.trim().isNotEmpty) {
        project.name = gameData.name.trim();
        _knownProjectNamesByPath[projectPath] = gameData.name.trim();
      }
      project.description = gameData.description.trim();
      project.updatedAt = DateTime.now().toUtc().toIso8601String();
      await _saveProjectsIndex();

      if (notify) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error opening project: $e");
      }
      final StoredProject? project = _findProjectById(projectId);
      final String failedPath = _normalizeProjectFolderPath(
        project?.folderPath ?? projectId,
      );
      if (_isMacOSPathPermissionDenied(e, failedPath)) {
        final String projectName = project?.name.trim() ?? '';
        if (projectName.isNotEmpty) {
          _knownProjectNamesByPath[failedPath] = projectName;
        }
        if (failedPath.isNotEmpty &&
            !missingProjectPaths.contains(failedPath)) {
          missingProjectPaths.add(failedPath);
        }
        projectStatusMessage =
            "Open failed: macOS denied folder access. Relink this project to grant permissions again.";
      } else {
        projectStatusMessage = "Open failed: $e";
      }
      if (notify) {
        notifyListeners();
      }
    }
  }

  bool _isMacOSPathPermissionDenied(Object error, String expectedPath) {
    if (!_supportsSecurityBookmarks) {
      return false;
    }
    final String message = error.toString().toLowerCase();
    if (!(message.contains('operation not permitted') ||
        message.contains('errno = 1') ||
        message.contains('security-scoped access unavailable'))) {
      return false;
    }
    if (expectedPath.trim().isEmpty) {
      return message.contains('pathaccessexception');
    }
    return message.contains(expectedPath.toLowerCase());
  }

  Future<bool> _ensureProjectSecurityAccess(String projectPath) async {
    if (!_supportsSecurityBookmarks) {
      return true;
    }
    String bookmark = _projectBookmarksByPath[projectPath] ?? '';
    bool changedBookmarks = false;
    if (bookmark.isEmpty) {
      final String? createdBookmark =
          await _createSecurityBookmarkForPath(projectPath);
      if (createdBookmark != null && createdBookmark.isNotEmpty) {
        bookmark = createdBookmark;
        _projectBookmarksByPath[projectPath] = createdBookmark;
        changedBookmarks = true;
      }
    }
    if (bookmark.isEmpty) {
      return false;
    }

    final Map<String, String>? resolved =
        await _resolveSecurityBookmark(bookmark);
    if (resolved == null) {
      return false;
    }
    final String refreshedBookmark = resolved['bookmark'] ?? bookmark;
    if (refreshedBookmark.isNotEmpty &&
        refreshedBookmark != _projectBookmarksByPath[projectPath]) {
      _projectBookmarksByPath[projectPath] = refreshedBookmark;
      changedBookmarks = true;
    }
    if (changedBookmarks) {
      await _saveProjectsIndex();
    }
    return true;
  }

  Future<void> reloadWorkingProject() async {
    if (selectedProjectId == "") {
      return;
    }
    await flushPendingAutosave();
    await openProject(selectedProjectId);
  }

  Future<void> reloadMediaFile(String fileName) async {
    final String raw = fileName.trim();
    if (raw.isEmpty) {
      return;
    }

    final String normalized = _normalizeProjectRelativePath(raw);
    final bool isAbsolutePath =
        raw.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw);
    final String cacheKey = normalized.isNotEmpty ? normalized : raw;

    final Set<String> cacheKeysToClear = <String>{
      raw,
      normalized,
      cacheKey,
    }..removeWhere((value) => value.isEmpty);
    _removeImagesFromCache(cacheKeysToClear);

    try {
      final String absolutePath = isAbsolutePath
          ? raw
          : _projectAbsolutePathForRelativePath(filePath, cacheKey);
      final File mediaFile = File(absolutePath);
      if (!await mediaFile.exists()) {
        throw Exception('File does not exist: $cacheKey');
      }
      final Uint8List bytes = await mediaFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('The asset does not exist or has empty data');
      }
      final ui.Image image = await decodeImage(bytes);
      imagesCache[cacheKey] = image;
      if (raw != cacheKey) {
        imagesCache[raw] = image;
      }
      projectStatusMessage = 'Reloaded "$cacheKey"';
    } catch (e) {
      projectStatusMessage = 'Reload failed for "$cacheKey": $e';
      if (kDebugMode) {
        print('Error reloading media file "$cacheKey": $e');
      }
    }
    notifyListeners();
  }

  Future<void> _copyDirectoryRecursively({
    required Directory source,
    required Directory destination,
  }) async {
    if (!await source.exists()) {
      throw Exception("Source folder does not exist: ${source.path}");
    }
    await destination.create(recursive: true);
    await for (final FileSystemEntity entity
        in source.list(recursive: false, followLinks: false)) {
      final String name = _lastPathSegment(entity.path);
      final String targetPath =
          "${destination.path}${Platform.pathSeparator}$name";
      if (entity is Directory) {
        await _copyDirectoryRecursively(
          source: entity,
          destination: Directory(targetPath),
        );
        continue;
      }
      if (entity is File) {
        final File targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  @override
  void dispose() {
    _clearAutosaveState();
    _disposeAndClearImageCache();
    super.dispose();
  }

  Future<void> _saveGameInternal({
    bool notifyOnSuccess = true,
  }) async {
    final StoredProject? project = selectedProject;
    if (project == null) {
      throw Exception("No selected project");
    }

    if (filePath == "") {
      filePath = project.folderPath;
    }
    fileName = gameFileName;

    final Directory projectDirectory = Directory(filePath);
    if (!await projectDirectory.exists()) {
      await projectDirectory.create(recursive: true);
    }

    final file = File("$filePath${Platform.pathSeparator}$fileName");
    final Map<String, dynamic> encoded = gameData.toJson();
    final Set<String> tileMapPaths =
        await _writeExternalTileMapsAndStripInlineFromGameData(
      encoded: encoded,
      projectDirectoryPath: filePath,
    );
    final Set<String> zonePaths =
        await _writeExternalZonesAndStripInlineFromGameData(
      encoded: encoded,
      projectDirectoryPath: filePath,
    );
    final Set<String> pathPaths =
        await _writeExternalPathsAndStripInlineFromGameData(
      encoded: encoded,
      projectDirectoryPath: filePath,
    );
    final String animationsPath =
        await _writeExternalAnimationsAndStripInlineFromGameData(
      encoded: encoded,
      projectDirectoryPath: filePath,
    );
    final String output = await _formatMapAsGameJson(encoded);
    await file.writeAsString(output);
    await _cleanupStaleExternalTileMapFiles(
      projectDirectoryPath: filePath,
      keepRelativePaths: tileMapPaths,
    );
    await _cleanupStaleExternalZoneFiles(
      projectDirectoryPath: filePath,
      keepRelativePaths: zonePaths,
    );
    await _cleanupStaleExternalPathFiles(
      projectDirectoryPath: filePath,
      keepRelativePaths: pathPaths,
    );
    await _cleanupStaleExternalAnimationFiles(
      projectDirectoryPath: filePath,
      keepRelativePaths: <String>{animationsPath},
    );

    if (gameData.name.trim().isNotEmpty) {
      project.name = gameData.name.trim();
    }
    project.updatedAt = DateTime.now().toUtc().toIso8601String();
    await _saveProjectsIndex();

    if (kDebugMode) {
      print("Game saved successfully to \"$filePath/$fileName\"");
    }

    if (notifyOnSuccess) {
      projectStatusMessage = "Saved project \"${project.name}\"";
      notifyListeners();
    }
  }

  Future<void> saveGame() async {
    try {
      await flushPendingAutosave();
      await _saveGameInternal();
    } catch (e) {
      if (kDebugMode) {
        print("Error saving game file: $e");
      }
      projectStatusMessage = "Save failed: $e";
      if (autosaveInlineMessage.isNotEmpty) {
        autosaveInlineMessage = '';
        autosaveHasError = false;
      }
      notifyListeners();
    }
  }

  GameMediaAsset? mediaAssetByFileName(String fileName) {
    for (final asset in gameData.mediaAssets) {
      if (asset.fileName == fileName) {
        return asset;
      }
    }
    return null;
  }

  GameAnimation? animationById(String animationId) {
    for (final animation in gameData.animations) {
      if (animation.id == animationId) {
        return animation;
      }
    }
    return null;
  }

  GameMediaAsset? mediaAssetByAnimationId(String animationId) {
    final GameAnimation? animation = animationById(animationId);
    if (animation == null) {
      return null;
    }
    return mediaAssetByFileName(animation.mediaFile);
  }

  String animationDisplayNameById(String animationId) {
    final GameAnimation? animation = animationById(animationId);
    if (animation == null) {
      return 'Unknown animation';
    }
    final String trimmed = animation.name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return GameMediaAsset.inferNameFromFileName(animation.mediaFile);
  }

  String mediaDisplayNameByFileName(String fileName) {
    final GameMediaAsset? asset = mediaAssetByFileName(fileName);
    if (asset == null) {
      return GameMediaAsset.inferNameFromFileName(fileName);
    }
    final String trimmed = asset.name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return GameMediaAsset.inferNameFromFileName(asset.fileName);
  }

  Color tilesetSelectionColorForFile(String fileName) {
    final asset = mediaAssetByFileName(fileName);
    if (asset == null) {
      return defaultTilesetSelectionColor;
    }
    return _parseHexColor(
        asset.selectionColorHex, defaultTilesetSelectionColor);
  }

  bool setTilesetSelectionColorForFile(String fileName, Color color) {
    final asset = mediaAssetByFileName(fileName);
    if (asset == null) {
      return false;
    }
    final String nextHex = _toHexColor(color);
    if (asset.selectionColorHex == nextHex) {
      return false;
    }
    asset.selectionColorHex = nextHex;
    return true;
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

  Future<String> pickImageFile() async {
    if (selectedProject == null) {
      return "";
    }

    final String initialDirectory =
        filePath != "" ? filePath : selectedProject!.folderPath;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      initialDirectory: initialDirectory,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );

    if (result == null || result.files.single.path == null) {
      return "";
    }

    String selectedPath = result.files.single.path!;
    String selectedFileName = _lastPathSegment(selectedPath);
    if (filePath == "") {
      filePath = selectedProject!.folderPath;
      fileName = gameFileName;
    }

    selectedFileName = _normalizeProjectRelativePath(selectedFileName);
    if (selectedFileName.isEmpty ||
        !_hasSupportedImageExtension(selectedFileName)) {
      return "";
    }
    final Directory mediaDirectory = Directory(
      "$filePath${Platform.pathSeparator}$mediaFolderName",
    );
    await mediaDirectory.create(recursive: true);

    final String preferredRelativePath =
        _mediaRelativePathForBaseName(selectedFileName);
    final String preferredDestinationPath =
        _projectAbsolutePathForRelativePath(filePath, preferredRelativePath);
    if (selectedPath != preferredDestinationPath &&
        await File(preferredDestinationPath).exists()) {
      final bool sameContent = await _filesHaveSameContent(
        selectedPath,
        preferredDestinationPath,
      );
      if (sameContent) {
        return preferredRelativePath;
      }
    }

    selectedFileName = await _buildUniqueFileNameInDirectory(
      mediaDirectory.path,
      selectedFileName,
    );
    selectedFileName = _mediaRelativePathForBaseName(selectedFileName);
    String destinationPath =
        _projectAbsolutePathForRelativePath(filePath, selectedFileName);

    if (selectedPath != destinationPath) {
      try {
        await File(selectedPath).copy(destinationPath);
        if (kDebugMode) {
          print("File copied to: $destinationPath");
        }
      } catch (e) {
        if (kDebugMode) {
          print("Error copying file: $e");
        }
        return "";
      }
    }

    return selectedFileName;
  }

  Future<ui.Image> getImage(String imageFileName) async {
    if (!imagesCache.containsKey(imageFileName)) {
      final File file =
          File("$filePath${Platform.pathSeparator}$imageFileName");
      if (!await file.exists()) {
        throw Exception("File does not exist: $imageFileName");
      }

      final Uint8List bytes = await file.readAsBytes();
      imagesCache[imageFileName] = await decodeImage(bytes);
    }

    return imagesCache[imageFileName]!;
  }

  Future<ui.Image> decodeImage(Uint8List bytes) {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) => completer.complete(img));
    return completer.future;
  }
}
