import 'package:nfc_manager/nfc_manager.dart';

// ─── NFC 서비스 ───────────────────────────────────────────────────────────────
class NfcService {
    static final NfcService instance = NfcService._();
    NfcService._();

    // NFC 태그에서 UID를 추출한다 (nfca/nfcb/nfcf/nfcv 순서로 시도)
    String? extractUid(NfcTag tag) {
        List<int>? id;
        for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv']) {
            if (tag.data[key] != null) {
                id = List<int>.from(tag.data[key]['identifier']);
                break;
            }
        }
        if (id == null) return null;
        return id.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
    }

    Future<bool> isAvailable() => NfcManager.instance.isAvailable();

    void startSession({required Future<void> Function(NfcTag) onDiscovered}) {
        NfcManager.instance.startSession(onDiscovered: onDiscovered);
    }

    Future<void> stopSession() => NfcManager.instance.stopSession();
}
