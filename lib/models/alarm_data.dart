// ─── 알람 모델 ────────────────────────────────────────────────────────────────
class AlarmData {
    final int id;
    final int hour;
    final int minute;
    final List<int> days;
    final bool enabled;
    final List<int> nfcTagIds;  // 빈 목록 = 아무 태그나 허용
    final String soundType;
    final double volume;

    const AlarmData({
        required this.id,
        required this.hour,
        required this.minute,
        required this.days,
        this.enabled = true,
        this.nfcTagIds = const [],
        this.soundType = 'alarm',
        this.volume = 1.0,
    });

    AlarmData copyWith({
        int? hour, int? minute, List<int>? days, bool? enabled,
        List<int>? nfcTagIds, String? soundType, double? volume,
    }) => AlarmData(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
        nfcTagIds: nfcTagIds ?? this.nfcTagIds,
        soundType: soundType ?? this.soundType,
        volume: volume ?? this.volume,
    );

    Map<String, dynamic> toJson() => {
        'id': id, 'hour': hour, 'minute': minute, 'days': days,
        'enabled': enabled, 'nfcTagIds': nfcTagIds,
        'soundType': soundType, 'volume': volume,
    };

    factory AlarmData.fromJson(Map<String, dynamic> j) => AlarmData(
        id: j['id'] as int,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        days: List<int>.from(j['days'] as List),
        enabled: j['enabled'] as bool,
        // 구버전 단일 nfcTagId 마이그레이션
        nfcTagIds: j['nfcTagIds'] != null
            ? List<int>.from(j['nfcTagIds'] as List)
            : (j['nfcTagId'] != null ? [j['nfcTagId'] as int] : []),
        soundType: (j['soundType'] as String?) ?? 'alarm',
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
    );
}
