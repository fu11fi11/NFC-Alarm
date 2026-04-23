import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_data.dart';
import '../models/alarm_chain.dart';
import '../models/nfc_tag_data.dart';
import '../background/alarm_callback.dart';

// ─── 알람 스케줄링 서비스 ──────────────────────────────────────────────────────
class AlarmService {
    static final AlarmService instance = AlarmService._();
    AlarmService._();

    // 체인 AlarmManager ID: 10000 + chainId*100 + stepIdx*10 + weekday
    int chainAmId(int chainId, int stepIdx, int weekday) =>
        10000 + chainId * 100 + stepIdx * 10 + weekday;

    DateTime nextOccurrence(int weekday, int hour, int minute) {
        final now = DateTime.now();
        final daysUntil = (weekday - now.weekday + 7) % 7;
        var candidate = DateTime(now.year, now.month, now.day, hour, minute)
            .add(Duration(days: daysUntil));
        if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 7));
        return candidate;
    }

    List<String> resolveUids(List<int> tagIds, List<NfcTagData> allTags) {
        final uids = <String>[];
        for (final id in tagIds) {
            for (final t in allTags) {
                if (t.id == id) { uids.add(t.uid); break; }
            }
        }
        return uids;
    }

    // ─── 독립 알람 스케줄링 ───────────────────────────────────────────────────

    Future<void> scheduleAlarm(AlarmData alarm, List<NfcTagData> allTags) async {
        final prefs = await SharedPreferences.getInstance();

        // 기존 알람 모두 취소
        for (int d = 1; d <= 7; d++) {
            final amId = alarm.id * 10 + d;
            await AndroidAlarmManager.cancel(amId);
            await prefs.remove('alarm_nfc_uids_$amId');
            await prefs.remove('alarm_nfc_uid_$amId');
            await prefs.remove('alarm_volume_$amId');
            await prefs.remove('alarm_sound_$amId');
        }
        if (!alarm.enabled || alarm.days.isEmpty) return;

        final uids = resolveUids(alarm.nfcTagIds, allTags);
        for (final day in alarm.days) {
            final amId = alarm.id * 10 + day;
            if (uids.isNotEmpty) await prefs.setStringList('alarm_nfc_uids_$amId', uids);
            await prefs.setDouble('alarm_volume_$amId', alarm.volume);
            await prefs.setString('alarm_sound_$amId', alarm.soundType);
            await AndroidAlarmManager.oneShotAt(
                nextOccurrence(day, alarm.hour, alarm.minute),
                amId, alarmFiredCallback,
                alarmClock: true, exact: true, wakeup: true, rescheduleOnReboot: true,
            );
        }
    }

    // ─── 체인 스케줄링 ────────────────────────────────────────────────────────

    Future<void> scheduleChain(AlarmChain chain, List<NfcTagData> allTags) async {
        final prefs = await SharedPreferences.getInstance();

        // 기존 체인 알람 모두 취소 (최대 20단계)
        for (int si = 0; si < 20; si++) {
            for (int d = 1; d <= 7; d++) {
                final amId = chainAmId(chain.id, si, d);
                await AndroidAlarmManager.cancel(amId);
                await prefs.remove('alarm_nfc_uids_$amId');
                await prefs.remove('alarm_volume_$amId');
                await prefs.remove('alarm_sound_$amId');
            }
        }
        if (!chain.enabled || chain.days.isEmpty || chain.steps.isEmpty) return;

        for (int si = 0; si < chain.steps.length; si++) {
            final step = chain.steps[si];
            final uids = resolveUids(step.nfcTagIds, allTags);
            for (final day in chain.days) {
                final amId = chainAmId(chain.id, si, day);
                if (uids.isNotEmpty) await prefs.setStringList('alarm_nfc_uids_$amId', uids);
                await prefs.setDouble('alarm_volume_$amId', step.volume);
                await prefs.setString('alarm_sound_$amId', step.soundType);
                await AndroidAlarmManager.oneShotAt(
                    nextOccurrence(day, step.hour, step.minute),
                    amId, alarmFiredCallback,
                    alarmClock: true, exact: true, wakeup: true, rescheduleOnReboot: true,
                );
            }
        }
    }

    // ─── 오늘 특정 체인 단계 건너뜀 ──────────────────────────────────────────

    Future<void> skipChainStepToday(
        AlarmChain chain, int stepIdx, List<NfcTagData> allTags) async {
        final now = DateTime.now();
        final today = now.weekday;
        if (!chain.days.contains(today)) return;

        final step = chain.steps[stepIdx];
        final todayTime = DateTime(now.year, now.month, now.day, step.hour, step.minute);
        if (!todayTime.isAfter(now)) return;

        final prefs = await SharedPreferences.getInstance();
        final amId = chainAmId(chain.id, stepIdx, today);
        await AndroidAlarmManager.cancel(amId);

        final uids = resolveUids(step.nfcTagIds, allTags);
        final nextTime = todayTime.add(const Duration(days: 7));
        if (uids.isNotEmpty) await prefs.setStringList('alarm_nfc_uids_$amId', uids);
        await prefs.setDouble('alarm_volume_$amId', step.volume);
        await prefs.setString('alarm_sound_$amId', step.soundType);
        await AndroidAlarmManager.oneShotAt(
            nextTime, amId, alarmFiredCallback,
            alarmClock: true, exact: true, wakeup: true, rescheduleOnReboot: true,
        );
    }
}
