import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── 알람 울림 상태 ────────────────────────────────────────────────────────────
class AlarmRingingState {
    final bool isActive;
    final List<String> activeNfcUids;

    const AlarmRingingState({this.isActive = false, this.activeNfcUids = const []});
}

class AlarmRingingNotifier extends Notifier<AlarmRingingState> {
    @override
    AlarmRingingState build() => const AlarmRingingState();

    void setActive(List<String> nfcUids) {
        state = AlarmRingingState(isActive: true, activeNfcUids: nfcUids);
    }

    void dismiss() {
        state = const AlarmRingingState();
    }
}

final alarmRingingProvider =
    NotifierProvider<AlarmRingingNotifier, AlarmRingingState>(AlarmRingingNotifier.new);
