import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nfc_tag_data.dart';
import '../services/storage_service.dart';
import 'alarm_provider.dart';
import 'chain_provider.dart';

// ─── NFC 태그 상태 ────────────────────────────────────────────────────────────
class NfcTagState {
    final List<NfcTagData> tags;
    final int nextId;

    const NfcTagState({required this.tags, this.nextId = 0});

    NfcTagState copyWith({List<NfcTagData>? tags, int? nextId}) =>
        NfcTagState(tags: tags ?? this.tags, nextId: nextId ?? this.nextId);
}

class NfcTagNotifier extends Notifier<NfcTagState> {
    @override
    NfcTagState build() => const NfcTagState(tags: []);

    void initialize(List<NfcTagData> tags, int nextId) {
        state = NfcTagState(tags: tags, nextId: nextId);
    }

    Future<void> add(String name, String uid) async {
        final tag = NfcTagData(id: state.nextId, name: name, uid: uid);
        final newTags = [...state.tags, tag];
        state = state.copyWith(tags: newTags, nextId: state.nextId + 1);
        await StorageService.instance.saveNfcTags(newTags, state.nextId);
    }

    Future<void> update(int id, String name, String uid) async {
        final idx = state.tags.indexWhere((t) => t.id == id);
        if (idx == -1) return;
        final newTags = [...state.tags];
        newTags[idx] = state.tags[idx].copyWith(name: name, uid: uid);
        state = state.copyWith(tags: newTags);
        await StorageService.instance.saveNfcTags(newTags, state.nextId);
    }

    Future<void> delete(int tagId) async {
        final newTags = state.tags.where((t) => t.id != tagId).toList();
        state = state.copyWith(tags: newTags);
        await StorageService.instance.saveNfcTags(newTags, state.nextId);
        // 삭제된 태그 참조를 알람·체인에서 정리
        await ref.read(alarmProvider.notifier).removeTagReference(tagId, newTags);
        await ref.read(chainProvider.notifier).removeTagReference(tagId, newTags);
    }
}

final nfcTagProvider = NotifierProvider<NfcTagNotifier, NfcTagState>(NfcTagNotifier.new);
