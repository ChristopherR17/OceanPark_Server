part of 'layout.dart';

/// Zone selection helpers: marquee, validation, drag-move.
extension _LayoutZoneSelection on _LayoutState {
  int _firstZoneIndexInSelection(Set<int> selection) {
    if (selection.isEmpty) {
      return -1;
    }
    final List<int> sorted = selection.toList()..sort();
    return sorted.first;
  }

  Rect? get _zonesMarqueeRect {
    if (!_isMarqueeSelectingZones ||
        _zonesMarqueeStartLocal == null ||
        _zonesMarqueeCurrentLocal == null) {
      return null;
    }
    return Rect.fromPoints(
        _zonesMarqueeStartLocal!, _zonesMarqueeCurrentLocal!);
  }

  void _publishZoneSelectionToAppData(AppData appData) {
    final Set<int> next = Set<int>.from(_selectedZoneIndices);
    if (appData.selectedZoneIndices.length == next.length &&
        appData.selectedZoneIndices.containsAll(next)) {
      return;
    }
    appData.selectedZoneIndices = next;
  }

  Set<int> _validatedZoneSelection(AppData appData, Iterable<int> input) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return <int>{};
    }
    final int zoneCount =
        appData.gameData.levels[appData.selectedLevel].zones.length;
    final Set<int> output = <int>{};
    for (final int index in input) {
      if (index >= 0 && index < zoneCount) {
        output.add(index);
      }
    }
    return output;
  }

  Rect? _zoneScreenRect(AppData appData, GameZone zone) {
    if (zone.width <= 0 || zone.height <= 0) {
      return null;
    }
    final double scale = appData.scaleFactor;
    final double left = appData.imageOffset.dx + zone.x * scale;
    final double top = appData.imageOffset.dy + zone.y * scale;
    final double width = zone.width * scale;
    final double height = zone.height * scale;
    if (width <= 0 || height <= 0) {
      return null;
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  Set<int> _zoneIndicesInMarqueeRect(AppData appData, Rect marqueeRect) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return <int>{};
    }
    final List<GameZone> zones =
        appData.gameData.levels[appData.selectedLevel].zones;
    final Set<int> hits = <int>{};
    for (int i = 0; i < zones.length; i++) {
      final Rect? zoneRect = _zoneScreenRect(appData, zones[i]);
      if (zoneRect == null) {
        continue;
      }
      if (marqueeRect.overlaps(zoneRect)) {
        hits.add(i);
      }
    }
    return hits;
  }

  bool _applyZoneMarqueeSelection(AppData appData) {
    final Rect? marqueeRect = _zonesMarqueeRect;
    if (marqueeRect == null) {
      return false;
    }
    final Set<int> hitSelection =
        _zoneIndicesInMarqueeRect(appData, marqueeRect);
    final Set<int> nextSelection = _zoneMarqueeSelectionAdditive
        ? <int>{..._marqueeBaseZoneSelection, ...hitSelection}
        : hitSelection;
    final int preferredPrimary = hitSelection.isEmpty
        ? appData.selectedZone
        : _firstZoneIndexInSelection(hitSelection);
    return _setZoneSelection(
      appData,
      nextSelection,
      preferredPrimary: preferredPrimary,
    );
  }

  bool _setZoneSelection(
    AppData appData,
    Set<int> nextSelection, {
    int? preferredPrimary,
  }) {
    final Set<int> validated = _validatedZoneSelection(appData, nextSelection);
    final int nextPrimary = validated.isEmpty
        ? -1
        : (preferredPrimary != null && validated.contains(preferredPrimary)
            ? preferredPrimary
            : _firstZoneIndexInSelection(validated));
    final bool sameSelection =
        validated.length == _selectedZoneIndices.length &&
            _selectedZoneIndices.containsAll(validated);
    final bool samePrimary = appData.selectedZone == nextPrimary;
    if (sameSelection && samePrimary) {
      return false;
    }
    _selectedZoneIndices
      ..clear()
      ..addAll(validated);
    appData.selectedZone = nextPrimary;
    _publishZoneSelectionToAppData(appData);
    return true;
  }

  void _syncZoneSelectionState(AppData appData) {
    if (appData.selectedSection != 'zones' ||
        appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      _selectedZoneIndices.clear();
      _zoneDragOffsetsByIndex.clear();
      _isMarqueeSelectingZones = false;
      _zonesMarqueeStartLocal = null;
      _zonesMarqueeCurrentLocal = null;
      _marqueeBaseZoneSelection = <int>{};
      _zoneSelectionLevelIndex = -1;
      _publishZoneSelectionToAppData(appData);
      return;
    }

    if (_zoneSelectionLevelIndex != appData.selectedLevel) {
      _selectedZoneIndices.clear();
      _zoneDragOffsetsByIndex.clear();
      _zoneSelectionLevelIndex = appData.selectedLevel;
    }

    final Set<int> validated =
        _validatedZoneSelection(appData, appData.selectedZoneIndices);
    if (validated.length != _selectedZoneIndices.length ||
        !_selectedZoneIndices.containsAll(validated)) {
      _selectedZoneIndices
        ..clear()
        ..addAll(validated);
    }

    final bool selectedZoneValid = validated.contains(appData.selectedZone);
    final bool appDataSelectionValid = appData.selectedZone >= 0 &&
        appData.selectedZone <
            appData.gameData.levels[appData.selectedLevel].zones.length;
    if (selectedZoneValid || !appDataSelectionValid) {
      _publishZoneSelectionToAppData(appData);
      return;
    }

    _selectedZoneIndices
      ..clear()
      ..add(appData.selectedZone);
    _publishZoneSelectionToAppData(appData);
  }

  bool _startDraggingSelectedZones(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length) {
      return false;
    }
    final List<GameZone> zones =
        appData.gameData.levels[appData.selectedLevel].zones;
    final Set<int> selection = _validatedZoneSelection(
      appData,
      _selectedZoneIndices,
    );
    if (selection.isEmpty) {
      return false;
    }

    final Offset worldPos = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final Map<int, Offset> offsets = <int, Offset>{};
    for (final int zoneIndex in selection) {
      if (zoneIndex < 0 || zoneIndex >= zones.length) {
        continue;
      }
      final GameZone zone = zones[zoneIndex];
      offsets[zoneIndex] =
          worldPos - Offset(zone.x.toDouble(), zone.y.toDouble());
    }
    if (offsets.isEmpty) {
      return false;
    }

    appData.pushUndo();
    _zoneDragOffsetsByIndex
      ..clear()
      ..addAll(offsets);
    return true;
  }

  bool _dragSelectedZones(AppData appData, Offset localPosition) {
    if (appData.selectedLevel < 0 ||
        appData.selectedLevel >= appData.gameData.levels.length ||
        _zoneDragOffsetsByIndex.isEmpty) {
      return false;
    }
    final Offset worldPos = LayoutUtils.translateCoords(
      localPosition,
      appData.imageOffset,
      appData.scaleFactor,
    );
    final List<GameZone> zones =
        appData.gameData.levels[appData.selectedLevel].zones;
    bool changed = false;
    for (final MapEntry<int, Offset> entry in _zoneDragOffsetsByIndex.entries) {
      final int zoneIndex = entry.key;
      if (zoneIndex < 0 || zoneIndex >= zones.length) {
        continue;
      }
      final GameZone zone = zones[zoneIndex];
      final int newX = (worldPos.dx - entry.value.dx).round();
      final int newY = (worldPos.dy - entry.value.dy).round();
      if (newX == zone.x && newY == zone.y) {
        continue;
      }
      zone.x = newX;
      zone.y = newY;
      changed = true;
    }
    return changed;
  }
}
