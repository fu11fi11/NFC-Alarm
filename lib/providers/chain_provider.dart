import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_chain.dart';
import '../models/chain_step.dart';
import '../models/nfc_tag_data.dart';
import '../services/alarm_service.dart';
import '../services/storage_service.dart';

// ─── 체인 상태 ────────────────────────────────────────────────────────────────
class ChainState {
    final List<AlarmChain> chains;
    final int nextId;

    const ChainState({required this.chains, this.nextId = 0});

    ChainState copyWith({List<AlarmChain>? chains, int? nextId}) =>
        ChainState(chains: chains ?? this.chains, nextId: nextId ?? this.nextId);
}

class ChainNotifier extends Notifier<ChainState> {
    @override
    ChainState build() => const ChainState(chains: []);

    void initialize(List<AlarmChain> chains, int nextId) {
        state = ChainState(chains: chains, nextId: nextId);
    }

    Future<void> add({
        required String name, required List<int> days,
        required List<ChainStep> steps, required List<NfcTagData> allTags,
    }) async {
        final chain = AlarmChain(id: state.nextId, name: name, days: days, steps: steps);
        final newChains = [...state.chains, chain];
        state = state.copyWith(chains: newChains, nextId: state.nextId + 1);
        await StorageService.instance.saveChains(newChains, state.nextId);
        await AlarmService.instance.scheduleChain(chain, allTags);
    }

    Future<void> update(
        AlarmChain chain, {
        required String name, required List<int> days,
        required List<ChainStep> steps, required List<NfcTagData> allTags,
    }) async {
        final updated = chain.copyWith(name: name, days: days, steps: steps);
        final idx = state.chains.indexWhere((c) => c.id == chain.id);
        if (idx == -1) return;
        final newChains = [...state.chains];
        newChains[idx] = updated;
        state = state.copyWith(chains: newChains);
        await StorageService.instance.saveChains(newChains, state.nextId);
        await AlarmService.instance.scheduleChain(updated, allTags);
    }

    Future<void> delete(AlarmChain chain, List<NfcTagData> allTags) async {
        // enabled: false, steps: [] 로 scheduleChain 호출하면 AlarmManager 항목 전부 취소됨
        await AlarmService.instance.scheduleChain(
            chain.copyWith(enabled: false, steps: []), allTags);
        final newChains = state.chains.where((c) => c.id != chain.id).toList();
        state = state.copyWith(chains: newChains);
        await StorageService.instance.saveChains(newChains, state.nextId);
    }

    Future<void> skipStep(
        AlarmChain chain, int stepIdx, List<NfcTagData> allTags) async {
        await AlarmService.instance.skipChainStepToday(chain, stepIdx, allTags);
    }

    // NFC 태그 삭제 시 참조 정리
    Future<void> removeTagReference(int tagId, List<NfcTagData> remainingTags) async {
        bool changed = false;
        final newChains = state.chains.map((c) {
            final newSteps = c.steps.map((s) {
                final filtered = s.nfcTagIds.where((id) => id != tagId).toList();
                if (filtered.length != s.nfcTagIds.length) {
                    changed = true;
                    return s.copyWith(nfcTagIds: filtered);
                }
                return s;
            }).toList();
            return c.copyWith(steps: newSteps);
        }).toList();
        if (!changed) return;
        state = state.copyWith(chains: newChains);
        await StorageService.instance.saveChains(newChains, state.nextId);
        for (final chain in newChains) {
            await AlarmService.instance.scheduleChain(chain, remainingTags);
        }
    }

    // 알람 해제 후 전체 재스케줄
    Future<void> rescheduleAll(List<NfcTagData> allTags) async {
        for (final chain in state.chains) {
            await AlarmService.instance.scheduleChain(chain, allTags);
        }
    }
}

final chainProvider = NotifierProvider<ChainNotifier, ChainState>(ChainNotifier.new);
