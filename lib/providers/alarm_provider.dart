import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_data.dart';
import '../models/nfc_tag_data.dart';
import '../services/alarm_service.dart';
import '../services/storage_service.dart';

// ─── 알람 상태 ────────────────────────────────────────────────────────────────
class AlarmState {
    final List<AlarmData> alarms;
    final int nextId;

    const AlarmState({required this.alarms, this.nextId = 0});

    AlarmState copyWith({List<AlarmData>? alarms, int? nextId}) =>
        AlarmState(alarms: alarms ?? this.alarms, nextId: nextId ?? this.nextId);
}

class AlarmNotifier extends Notifier<AlarmState> {
    @override
    AlarmState build() => const AlarmState(alarms: []);

    void initialize(List<AlarmData> alarms, int nextId) {
        state = AlarmState(alarms: alarms, nextId: nextId);
    }

    Future<void> add({
        required int hour, required int minute, required List<int> days,
        required List<int> nfcTagIds, required String soundType,
        required double volume, required List<NfcTagData> allTags,
    }) async {
        final alarm = AlarmData(
            id: state.nextId, hour: hour, minute: minute, days: days,
            nfcTagIds: nfcTagIds, soundType: soundType, volume: volume,
        );
        final newAlarms = [...state.alarms, alarm];
        state = state.copyWith(alarms: newAlarms, nextId: state.nextId + 1);
        await StorageService.instance.saveAlarms(newAlarms, state.nextId);
        await AlarmService.instance.scheduleAlarm(alarm, allTags);
    }

    Future<void> update(
        AlarmData alarm, {
        required int hour, required int minute, required List<int> days,
        required List<int> nfcTagIds, required String soundType,
        required double volume, required List<NfcTagData> allTags,
    }) async {
        final updated = alarm.copyWith(
            hour: hour, minute: minute, days: days,
            nfcTagIds: nfcTagIds, soundType: soundType, volume: volume,
        );
        final idx = state.alarms.indexWhere((a) => a.id == alarm.id);
        if (idx == -1) return;
        final newAlarms = [...state.alarms];
        newAlarms[idx] = updated;
        state = state.copyWith(alarms: newAlarms);
        await StorageService.instance.saveAlarms(newAlarms, state.nextId);
        await AlarmService.instance.scheduleAlarm(updated, allTags);
    }

    Future<void> delete(AlarmData alarm, List<NfcTagData> allTags) async {
        // enabled: false, days: [] 로 scheduleAlarm 호출하면 AlarmManager 항목 전부 취소됨
        await AlarmService.instance.scheduleAlarm(
            alarm.copyWith(enabled: false, days: []), allTags);
        final newAlarms = state.alarms.where((a) => a.id != alarm.id).toList();
        state = state.copyWith(alarms: newAlarms);
        await StorageService.instance.saveAlarms(newAlarms, state.nextId);
    }

    Future<void> toggle(AlarmData alarm, bool enabled, List<NfcTagData> allTags) async {
        final updated = alarm.copyWith(enabled: enabled);
        final idx = state.alarms.indexWhere((a) => a.id == alarm.id);
        if (idx == -1) return;
        final newAlarms = [...state.alarms];
        newAlarms[idx] = updated;
        state = state.copyWith(alarms: newAlarms);
        await StorageService.instance.saveAlarms(newAlarms, state.nextId);
        await AlarmService.instance.scheduleAlarm(updated, allTags);
    }

    // NFC 태그 삭제 시 참조 정리
    Future<void> removeTagReference(int tagId, List<NfcTagData> remainingTags) async {
        bool changed = false;
        final newAlarms = state.alarms.map((a) {
            final filtered = a.nfcTagIds.where((id) => id != tagId).toList();
            if (filtered.length != a.nfcTagIds.length) {
                changed = true;
                return a.copyWith(nfcTagIds: filtered);
            }
            return a;
        }).toList();
        if (!changed) return;
        state = state.copyWith(alarms: newAlarms);
        await StorageService.instance.saveAlarms(newAlarms, state.nextId);
    }

    // 알람 해제 후 전체 재스케줄
    Future<void> rescheduleAll(List<NfcTagData> allTags) async {
        for (final alarm in state.alarms) {
            await AlarmService.instance.scheduleAlarm(alarm, allTags);
        }
    }
}

final alarmProvider = NotifierProvider<AlarmNotifier, AlarmState>(AlarmNotifier.new);
