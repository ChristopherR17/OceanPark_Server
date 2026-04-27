part of 'layout.dart';

/// Navigation, tabs, breadcrumb, and section routing.
extension _LayoutNavigation on _LayoutState {
  Future<void> _onTabSelected(AppData appData, String value) async {
    await appData.setSelectedSection(value);
  }

  int _selectedSectionIndex(String selectedSection) {
    final selectedIndex = sections.indexOf(selectedSection);
    return selectedIndex == -1 ? 0 : selectedIndex;
  }

  List<MapEntry<String, String>> _selectedBreadcrumbParts(AppData appData) {
    final List<MapEntry<String, String>> parts = [];
    final String? projectName = appData.selectedProject?.name.trim();
    if (projectName != null && projectName.isNotEmpty) {
      parts.add(MapEntry('Project', projectName));
    }

    final bool hasLevel = appData.selectedLevel >= 0 &&
        appData.selectedLevel < appData.gameData.levels.length;
    final level =
        hasLevel ? appData.gameData.levels[appData.selectedLevel] : null;

    void addLevel() {
      if (level == null) return;
      parts.add(
        MapEntry(
          'Level',
          level.name.trim().isEmpty
              ? 'Level ${appData.selectedLevel + 1}'
              : level.name.trim(),
        ),
      );
    }

    void addLayer() {
      if (level == null) return;
      if (appData.selectedLayer < 0 ||
          appData.selectedLayer >= level.layers.length) {
        return;
      }
      final layer = level.layers[appData.selectedLayer];
      parts.add(
        MapEntry(
          'Layer',
          layer.name.trim().isEmpty
              ? 'Layer ${appData.selectedLayer + 1}'
              : layer.name.trim(),
        ),
      );
    }

    void addZone() {
      if (level == null) return;
      if (appData.selectedZone < 0 ||
          appData.selectedZone >= level.zones.length) {
        return;
      }
      final zone = level.zones[appData.selectedZone];
      final String zoneName = zone.name.trim();
      final String zoneType = zone.type.trim();
      final String displayName = zoneName.isNotEmpty
          ? zoneName
          : (zoneType.isNotEmpty
              ? zoneType
              : 'Zone ${appData.selectedZone + 1}');
      parts.add(
        MapEntry(
          'Zone',
          displayName,
        ),
      );
    }

    void addSprite() {
      if (level == null) return;
      if (appData.selectedSprite < 0 ||
          appData.selectedSprite >= level.sprites.length) {
        return;
      }
      final sprite = level.sprites[appData.selectedSprite];
      final String spriteName = sprite.name.trim();
      parts.add(
        MapEntry(
          'Sprite',
          spriteName.isEmpty
              ? 'Sprite ${appData.selectedSprite + 1}'
              : spriteName,
        ),
      );
    }

    void addAnimation() {
      if (appData.selectedAnimation < 0 ||
          appData.selectedAnimation >= appData.gameData.animations.length) {
        return;
      }
      final animation = appData.gameData.animations[appData.selectedAnimation];
      final String name = animation.name.trim().isNotEmpty
          ? animation.name.trim()
          : appData.animationDisplayNameById(animation.id);
      parts.add(MapEntry('Animation', name));
    }

    void addMedia() {
      if (appData.selectedMedia < 0 ||
          appData.selectedMedia >= appData.gameData.mediaAssets.length) {
        return;
      }
      final media = appData.gameData.mediaAssets[appData.selectedMedia];
      parts.add(MapEntry(
          'Media', appData.mediaDisplayNameByFileName(media.fileName)));
    }

    switch (appData.selectedSection) {
      case 'levels':
      case 'paths':
      case 'viewport':
        addLevel();
        break;
      case 'layers':
      case 'tilemap':
        addLevel();
        addLayer();
        break;
      case 'zones':
        addLevel();
        addZone();
        break;
      case 'sprites':
        addLevel();
        addSprite();
        break;
      case 'animations':
      case 'animation_rigs':
        addAnimation();
        break;
      case 'media':
        addMedia();
        break;
      case 'projects':
      default:
        break;
    }

    if (parts.isEmpty) {
      return const [MapEntry('Selection', 'None')];
    }
    return parts;
  }

  Widget _buildBreadcrumb(AppData appData, BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
    const Color breadcrumbLabelColor = Color(0xFF66B2FF);
    final TextStyle textStyle = typography.caption;
    final List<MapEntry<String, String>> parts =
        _selectedBreadcrumbParts(appData);
    final List<InlineSpan> spans = [];

    for (int i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans.add(
          TextSpan(
            text: ' > ',
            style: textStyle.copyWith(
              color: breadcrumbLabelColor,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: '${parts[i].key}: ',
          style: textStyle.copyWith(
            color: breadcrumbLabelColor,
          ),
        ),
      );
      spans.add(
        TextSpan(
          text: parts[i].value,
          style: textStyle.copyWith(color: cdkColors.colorText),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _buildBottomStatusBar(AppData appData, BuildContext context) {
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    return Container(
      color: cdkColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double clipboardWidth =
                ((constraints.maxWidth * 0.42).clamp(280.0, 460.0) - 100.0)
                    .clamp(180.0, 360.0);
            return Row(
              children: [
                Expanded(
                  child: _buildBreadcrumb(appData, context),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: clipboardWidth,
                  child: _buildClipboardStatusRow(appData, context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _sectionLabel(String section) {
    final String normalized = section.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) {
      return section;
    }
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  List<Widget> _buildSegmentedOptions(BuildContext context) {
    return sections
        .map(
          (segment) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: CDKText(
              _sectionLabel(segment),
              role: CDKTextRole.caption,
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _getSelectedLayout(AppData appData) {
    switch (appData.selectedSection) {
      case 'projects':
        return const LayoutProjects();
      case 'levels':
        return LayoutLevels(key: layoutLevelsKey);
      case 'layers':
        return LayoutLayers(key: layoutLayersKey);
      case 'tilemap':
        return const LayoutTilemaps();
      case 'zones':
        return LayoutZones(key: layoutZonesKey);
      case 'animations':
        return LayoutAnimations(key: _layoutAnimationsKey);
      case 'animation_rigs':
        return LayoutAnimationRigs(key: layoutAnimationRigsKey);
      case 'sprites':
        return LayoutSprites(key: layoutSpritesKey);
      case 'paths':
        return LayoutPaths(key: layoutPathsKey);
      case 'viewport':
        return LayoutViewport(key: layoutViewportKey);
      case 'media':
        return LayoutMedia(key: _layoutMediaKey);
      default:
        return const Center(
          child: CDKText(
            'Unknown Layout',
            role: CDKTextRole.body,
            secondary: true,
          ),
        );
    }
  }
}
