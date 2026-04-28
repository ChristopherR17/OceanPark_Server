import 'game_animation_hit_box.dart';

class GameAnimationFrameRig {
  GameAnimationFrameRig({
    required int frame,
    required double anchorX,
    required double anchorY,
    required String anchorColor,
    required List<GameAnimationHitBox> hitBoxes,
  })  : frame = frame < 0 ? 0 : frame,
        anchorX = GameAnimation._normalizeAnchorComponent(
          anchorX,
          GameAnimation.defaultAnchorX,
        ),
        anchorY = GameAnimation._normalizeAnchorComponent(
          anchorY,
          GameAnimation.defaultAnchorY,
        ),
        anchorColor = GameAnimation._normalizeAnchorColor(anchorColor),
        hitBoxes =
            hitBoxes.map((item) => item.copyWith()).toList(growable: true);

  final int frame;
  final double anchorX;
  final double anchorY;
  final String anchorColor;
  final List<GameAnimationHitBox> hitBoxes;

  factory GameAnimationFrameRig.fromJson(Map<String, dynamic> json) {
    return GameAnimationFrameRig(
      frame: (json['frame'] as num?)?.toInt() ?? 0,
      anchorX:
          (json['anchorX'] as num?)?.toDouble() ?? GameAnimation.defaultAnchorX,
      anchorY:
          (json['anchorY'] as num?)?.toDouble() ?? GameAnimation.defaultAnchorY,
      anchorColor:
          json['anchorColor'] as String? ?? GameAnimation.defaultAnchorColor,
      hitBoxes: ((json['hitBoxes'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(GameAnimationHitBox.fromJson)
          .toList(growable: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'frame': frame,
      'anchorX': anchorX,
      'anchorY': anchorY,
      'anchorColor': anchorColor,
      'hitBoxes': hitBoxes.map((item) => item.toJson()).toList(growable: false),
    };
  }

  GameAnimationFrameRig copyWith({
    int? frame,
    double? anchorX,
    double? anchorY,
    String? anchorColor,
    List<GameAnimationHitBox>? hitBoxes,
  }) {
    return GameAnimationFrameRig(
      frame: frame ?? this.frame,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      anchorColor: anchorColor ?? this.anchorColor,
      hitBoxes: hitBoxes ?? this.hitBoxes,
    );
  }
}

class GameAnimation {
  static const String defaultGroupId = '__main__';
  static const double defaultAnchorX = 0.5;
  static const double defaultAnchorY = 0.5;
  static const String defaultAnchorColor = 'red';
  static const List<String> anchorColorPalette = <String>[
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
    'black',
    'white',
  ];

  String id;
  String name;
  String mediaFile;
  int startFrame;
  int endFrame;
  double fps;
  bool loop;
  String groupId;
  double anchorX;
  double anchorY;
  String anchorColor;
  List<GameAnimationHitBox> hitBoxes;
  List<GameAnimationFrameRig> frameRigs;

  GameAnimation({
    required this.id,
    required this.name,
    required this.mediaFile,
    required this.startFrame,
    required this.endFrame,
    required this.fps,
    required this.loop,
    String? groupId,
    double? anchorX,
    double? anchorY,
    String? anchorColor,
    List<GameAnimationHitBox>? hitBoxes,
    List<GameAnimationFrameRig>? frameRigs,
  })  : groupId = _normalizeGroupId(groupId),
        anchorX = _normalizeAnchorComponent(anchorX, defaultAnchorX),
        anchorY = _normalizeAnchorComponent(anchorY, defaultAnchorY),
        anchorColor = _normalizeAnchorColor(anchorColor),
        hitBoxes =
            hitBoxes?.map((item) => item.copyWith()).toList(growable: true) ??
                <GameAnimationHitBox>[],
        frameRigs = frameRigs
                ?.map(
                  (item) => item.copyWith(
                    hitBoxes: item.hitBoxes
                        .map((hitBox) => hitBox.copyWith())
                        .toList(growable: true),
                  ),
                )
                .toList(growable: true) ??
            <GameAnimationFrameRig>[] {
    if (startFrame < 0) {
      startFrame = 0;
    }
    if (endFrame < startFrame) {
      endFrame = startFrame;
    }
    if (fps <= 0 || !fps.isFinite) {
      fps = 12.0;
    }
    _normalizeFrameRigs();
    ensureFrameRigsForRange();
    _syncLegacyRigFromFrame(startFrame);
  }

  factory GameAnimation.fromJson(Map<String, dynamic> json) {
    final int parsedStart = (json['startFrame'] as num?)?.toInt() ?? 0;
    final int parsedEnd = (json['endFrame'] as num?)?.toInt() ?? parsedStart;
    final double parsedFps = (json['fps'] as num?)?.toDouble() ?? 12.0;
    return GameAnimation(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      mediaFile: ((json['mediaFile'] as String?) ??
              (json['imageFile'] as String?) ??
              '')
          .trim(),
      startFrame: parsedStart < 0 ? 0 : parsedStart,
      endFrame: parsedEnd < parsedStart ? parsedStart : parsedEnd,
      fps: parsedFps <= 0 ? 12.0 : parsedFps,
      loop: json['loop'] as bool? ?? true,
      groupId: json['groupId'] as String? ?? defaultGroupId,
      anchorX:
          (json['anchorX'] as num?)?.toDouble() ?? GameAnimation.defaultAnchorX,
      anchorY:
          (json['anchorY'] as num?)?.toDouble() ?? GameAnimation.defaultAnchorY,
      anchorColor: json['anchorColor'] as String? ?? defaultAnchorColor,
      hitBoxes: ((json['hitBoxes'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(GameAnimationHitBox.fromJson)
          .toList(growable: true),
      frameRigs: ((json['frameRigs'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(GameAnimationFrameRig.fromJson)
          .toList(growable: true),
    );
  }

  Map<String, dynamic> toJson() {
    ensureFrameRigsForRange();
    _syncLegacyRigFromFrame(startFrame);
    return {
      'id': id,
      'name': name,
      'mediaFile': mediaFile,
      'startFrame': startFrame,
      'endFrame': endFrame,
      'fps': fps,
      'loop': loop,
      'groupId': _normalizeGroupId(groupId),
      'anchorX': _normalizeAnchorComponent(anchorX, defaultAnchorX),
      'anchorY': _normalizeAnchorComponent(anchorY, defaultAnchorY),
      'anchorColor': _normalizeAnchorColor(anchorColor),
      'hitBoxes': hitBoxes.map((item) => item.toJson()).toList(growable: false),
      'frameRigs': frameIndicesInAnimationRange()
          .map((frame) => rigForFrame(frame).toJson())
          .toList(growable: false),
    };
  }

  List<int> frameIndicesInAnimationRange() {
    final int start = startFrame < 0 ? 0 : startFrame;
    final int end = endFrame < start ? start : endFrame;
    return List<int>.generate(end - start + 1, (index) => start + index);
  }

  GameAnimationFrameRig rigForFrame(int frame) {
    final int normalizedFrame = frame < 0 ? 0 : frame;
    for (final GameAnimationFrameRig rig in frameRigs) {
      if (rig.frame == normalizedFrame) {
        return rig.copyWith(
          hitBoxes: rig.hitBoxes
              .map((item) => item.copyWith())
              .toList(growable: true),
        );
      }
    }
    return GameAnimationFrameRig(
      frame: normalizedFrame,
      anchorX: anchorX,
      anchorY: anchorY,
      anchorColor: anchorColor,
      hitBoxes: hitBoxes.map((item) => item.copyWith()).toList(growable: true),
    );
  }

  void setRigForFrame(int frame, GameAnimationFrameRig rig) {
    final int normalizedFrame = frame < 0 ? 0 : frame;
    final GameAnimationFrameRig normalizedRig = rig.copyWith(
      frame: normalizedFrame,
      hitBoxes:
          rig.hitBoxes.map((item) => item.copyWith()).toList(growable: true),
    );
    final int existingIndex =
        frameRigs.indexWhere((item) => item.frame == normalizedFrame);
    if (existingIndex == -1) {
      frameRigs.add(normalizedRig);
    } else {
      frameRigs[existingIndex] = normalizedRig;
    }
    _normalizeFrameRigs();
    _syncLegacyRigFromFrame(startFrame);
  }

  void setRigForFrames(Iterable<int> frames, GameAnimationFrameRig rig) {
    for (final int frame in frames) {
      setRigForFrame(frame, rig.copyWith(frame: frame));
    }
  }

  void ensureFrameRigsForRange() {
    final List<int> frames = frameIndicesInAnimationRange();
    for (final int frame in frames) {
      if (frameRigs.any((item) => item.frame == frame)) {
        continue;
      }
      frameRigs.add(
        GameAnimationFrameRig(
          frame: frame,
          anchorX: anchorX,
          anchorY: anchorY,
          anchorColor: anchorColor,
          hitBoxes:
              hitBoxes.map((item) => item.copyWith()).toList(growable: true),
        ),
      );
    }
    _normalizeFrameRigs();
  }

  void _normalizeFrameRigs() {
    final Map<int, GameAnimationFrameRig> byFrame =
        <int, GameAnimationFrameRig>{};
    for (final GameAnimationFrameRig item in frameRigs) {
      byFrame[item.frame < 0 ? 0 : item.frame] = item.copyWith(
        frame: item.frame < 0 ? 0 : item.frame,
        hitBoxes: item.hitBoxes
            .map((hitBox) => hitBox.copyWith())
            .toList(growable: true),
      );
    }
    final List<GameAnimationFrameRig> normalized = byFrame.values
        .toList(growable: true)
      ..sort((a, b) => a.frame.compareTo(b.frame));
    frameRigs = normalized;
  }

  void _syncLegacyRigFromFrame(int frame) {
    final GameAnimationFrameRig rig = rigForFrame(frame);
    anchorX = rig.anchorX;
    anchorY = rig.anchorY;
    anchorColor = rig.anchorColor;
    hitBoxes =
        rig.hitBoxes.map((item) => item.copyWith()).toList(growable: true);
  }

  static String _normalizeGroupId(String? rawGroupId) {
    final String trimmed = rawGroupId?.trim() ?? '';
    if (trimmed.isEmpty) {
      return defaultGroupId;
    }
    return trimmed;
  }

  static double _normalizeAnchorComponent(double? value, double fallback) {
    if (value == null || value.isNaN || value.isInfinite) {
      return fallback;
    }
    return value.clamp(0.0, 1.0);
  }

  static String _normalizeAnchorColor(String? rawColor) {
    final String normalized = rawColor?.trim() ?? '';
    if (anchorColorPalette.contains(normalized)) {
      return normalized;
    }
    return defaultAnchorColor;
  }
}
