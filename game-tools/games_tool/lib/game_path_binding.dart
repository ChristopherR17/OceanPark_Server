class GamePathBinding {
  static const String targetTypeLayer = 'layer';
  static const String targetTypeZone = 'zone';
  static const String targetTypeSprite = 'sprite';
  static const int defaultDurationMs = 2000;

  static const String behaviorRestart = 'restart';
  static const String behaviorPingPong = 'ping_pong';
  static const String behaviorOnce = 'once';

  static const List<String> supportedTargetTypes = <String>[
    targetTypeLayer,
    targetTypeZone,
    targetTypeSprite,
  ];
  static const List<String> supportedBehaviors = <String>[
    behaviorRestart,
    behaviorPingPong,
    behaviorOnce,
  ];

  String id;
  String pathId;
  String targetType;
  int targetIndex;
  String behavior;
  bool enabled;
  bool relativeToInitialPosition;
  int durationMs;

  GamePathBinding({
    required this.id,
    required this.pathId,
    String targetType = targetTypeSprite,
    this.targetIndex = 0,
    String behavior = behaviorPingPong,
    this.enabled = true,
    this.relativeToInitialPosition = true,
    int durationMs = defaultDurationMs,
  })  : targetType = _normalizeTargetType(targetType),
        behavior = _normalizeBehavior(behavior),
        durationMs = _normalizeDurationMs(durationMs);

  factory GamePathBinding.fromJson(Map<String, dynamic> json) {
    return GamePathBinding(
      id: (json['id'] as String? ?? '').trim(),
      pathId: (json['pathId'] as String? ?? '').trim(),
      targetType: json['targetType'] as String? ?? targetTypeSprite,
      targetIndex: (json['targetIndex'] as num?)?.round() ?? 0,
      behavior: json['behavior'] as String? ?? behaviorPingPong,
      enabled: json['enabled'] as bool? ?? true,
      relativeToInitialPosition:
          json['relativeToInitialPosition'] as bool? ?? true,
      durationMs: (json['durationMs'] as num?)?.round() ?? defaultDurationMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.trim(),
      'pathId': pathId.trim(),
      'targetType': _normalizeTargetType(targetType),
      'targetIndex': targetIndex,
      'behavior': _normalizeBehavior(behavior),
      'enabled': enabled,
      'relativeToInitialPosition': relativeToInitialPosition,
      'durationMs': _normalizeDurationMs(durationMs),
    };
  }

  static String _normalizeTargetType(String raw) {
    if (supportedTargetTypes.contains(raw)) {
      return raw;
    }
    return targetTypeSprite;
  }

  static String _normalizeBehavior(String raw) {
    if (supportedBehaviors.contains(raw)) {
      return raw;
    }
    return behaviorRestart;
  }

  static int _normalizeDurationMs(int raw) {
    if (raw <= 0) {
      return defaultDurationMs;
    }
    return raw;
  }
}
