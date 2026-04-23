import 'chain_step.dart';

// ─── 알람 체인 모델 ───────────────────────────────────────────────────────────
class AlarmChain {
    final int id;
    final String name;
    final List<int> days;       // 체인 전체 공유 요일
    final bool enabled;
    final List<ChainStep> steps;

    const AlarmChain({
        required this.id,
        required this.name,
        this.days = const [],
        this.enabled = true,
        this.steps = const [],
    });

    AlarmChain copyWith({
        String? name, List<int>? days, bool? enabled, List<ChainStep>? steps,
    }) => AlarmChain(
        id: id,
        name: name ?? this.name,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
        steps: steps ?? this.steps,
    );

    Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'days': days, 'enabled': enabled,
        'steps': steps.map((s) => s.toJson()).toList(),
    };

    factory AlarmChain.fromJson(Map<String, dynamic> j) => AlarmChain(
        id: j['id'] as int,
        name: j['name'] as String,
        days: List<int>.from((j['days'] as List?) ?? []),
        enabled: (j['enabled'] as bool?) ?? true,
        steps: ((j['steps'] as List?) ?? [])
            .map((e) => ChainStep.fromJson(e as Map<String, dynamic>))
            .toList(),
    );
}
