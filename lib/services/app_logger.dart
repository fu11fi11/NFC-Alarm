import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// ─── 로그 태그 상수 ───────────────────────────────────────────────────────────
class LogTag {
    static const String app       = 'APP';
    static const String alarm     = 'ALARM';
    static const String nfc       = 'NFC';
    static const String service   = 'SERVICE';
    static const String chain     = 'CHAIN';
    static const String schedule  = 'SCHEDULE';
}

// ─── 앱 로거 ─────────────────────────────────────────────────────────────────
// 모든 주요 이벤트를 외부 저장소 파일에 기록한다.
// 경로: /sdcard/Android/data/com.example.nfc_alarm/files/nfc_alarm_log.txt
// 꺼내기: adb pull /sdcard/Android/data/com.example.nfc_alarm/files/nfc_alarm_log.txt
const int _maxBytes = 1024 * 1024 * 1024; // 1 GB
const String _logFileName = 'nfc_alarm_log.txt';

String? _cachedPath;

// 파일 경로를 한 번만 resolve하고 이후에는 캐시를 사용한다.
Future<String?> _resolvePath() async {
    if (_cachedPath != null) return _cachedPath;
    try {
        final dir = await getExternalStorageDirectory();
        if (dir == null) return null;
        _cachedPath = '${dir.path}/$_logFileName';
        return _cachedPath;
    } catch (_) {
        return null;
    }
}

// 공개 로그 함수 — fire-and-forget으로 호출한다.
void appLog(String tag, String message) {
    unawaited(_write(tag, message));
}

Future<void> _write(String tag, String message) async {
    try {
        final path = await _resolvePath();
        if (path == null) return;

        final file = File(path);
        final now = DateTime.now();
        final ts = '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}:'
            '${now.second.toString().padLeft(2, '0')}.'
            '${now.millisecond.toString().padLeft(3, '0')}';
        final line = '[$ts] [$tag] $message\n';

        // 1 GB 초과 시 앞 50% 삭제 후 이어씀
        if (await file.exists()) {
            final size = await file.length();
            if (size > _maxBytes) {
                final content = await file.readAsString();
                final trimmed = content.substring(content.length ~/ 2);
                await file.writeAsString(trimmed);
            }
        }

        await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {
        // 로그 쓰기 실패는 앱 동작에 영향을 주지 않는다.
    }
}
