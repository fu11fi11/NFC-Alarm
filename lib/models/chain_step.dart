// ─── 체인 단계 모델 ───────────────────────────────────────────────────────────
class ChainStep {
    final int hour;
    final int minute;
    final String label;         // 단계 이름 (예: "기상", "헬스장")
    final List<int> nfcTagIds;
    final String soundType;
    final double volume;

    const ChainStep({
        required this.hour,
        required this.minute,
        this.label = '',
        this.nfcTagIds = const [],
        this.soundType = 'alarm',
        this.volume = 1.0,
    });

    ChainStep copyWith({
        int? hour, int? minute, String? label,
        List<int>? nfcTagIds, String? soundType, double? volume,
    }) => ChainStep(
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        nfcTagIds: nfcTagIds ?? this.nfcTagIds,
        soundType: soundType ?? this.soundType,
        volume: volume ?? this.volume,
    );

    Map<String, dynamic> toJson() => {
        'hour': hour, 'minute': minute, 'label': label,
        'nfcTagIds': nfcTagIds, 'soundType': soundType, 'volume': volume,
    };

    factory ChainStep.fromJson(Map<String, dynamic> j) => ChainStep(
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        label: (j['label'] as String?) ?? '',
        nfcTagIds: List<int>.from((j['nfcTagIds'] as List?) ?? []),
        soundType: (j['soundType'] as String?) ?? 'alarm',
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
    );
}
