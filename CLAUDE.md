# nfc_alarm
> ⚠️ App name subject to change

## Project Overview
An Android alarm app that requires scanning an NFC tag to dismiss the alarm.
Users place an NFC tag at a specific location (e.g., bathroom, gym) and must physically go there to turn off the alarm.
Fully offline — no server required. All data is stored on-device via SharedPreferences.

## Architecture
- **State management**: Riverpod (`NotifierProvider`) — `AlarmProvider`, `ChainProvider`, `NfcTagProvider`, `AlarmRingingProvider`
- **Background alarm**: Scheduled via `android_alarm_manager_plus`; foreground service maintained during ringing via `flutter_foreground_task`
- **Data storage**: JSON-serialized into SharedPreferences via `StorageService` singleton (no database)
- **Platform**: Android only for now; iOS expansion planned

## Tech Stack

### Core
- **Framework**: Flutter 3.41.7 (Dart 3.11.5)
- **Target Platform**: Android (iOS expansion planned)
- **Local storage**: SharedPreferences (fully offline app)

### Key Packages
| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | Global state management |
| `nfc_manager` | NFC tag scanning |
| `android_alarm_manager_plus` | Background alarm scheduling |
| `flutter_foreground_task` | Foreground service while alarm is ringing |
| `flutter_local_notifications` | Alarm notification display |
| `flutter_ringtone_player` | Alarm sound playback |
| `vibration` | Vibration |
| `android_intent_plus` | Android intents (volume control, etc.) |
| `shared_preferences` | Local storage for alarm/tag data |
| `timezone` | Timezone-based alarm time calculation |
| `path_provider` | External storage path for log file |

## Project Structure
```
nfc_alarm/
├── lib/
│   ├── main.dart                  # 진입점 — 초기화 + ProviderScope + runApp
│   ├── app.dart                   # NfcAlarmApp 루트 위젯
│   ├── constants/
│   │   ├── app_colors.dart        # 색상 상수
│   │   └── app_constants.dart     # 매직 넘버 / 패키지명 / 요일 레이블
│   ├── models/
│   │   ├── alarm_data.dart
│   │   ├── alarm_chain.dart
│   │   ├── chain_step.dart
│   │   └── nfc_tag_data.dart
│   ├── services/
│   │   ├── app_logger.dart        # 파일 기반 로거 (fire-and-forget)
│   │   ├── storage_service.dart   # SharedPreferences 읽기/쓰기 전담
│   │   ├── alarm_service.dart     # AlarmManager 스케줄링 전담
│   │   ├── nfc_service.dart       # NFC 세션 관리 / UID 추출
│   │   └── notification_service.dart # 로컬 알림 초기화 / 취소
│   ├── background/
│   │   ├── alarm_callback.dart    # alarmFiredCallback (별도 isolate — Riverpod 미사용)
│   │   └── alarm_task_handler.dart# AlarmTaskHandler (포그라운드 서비스 태스크)
│   ├── providers/
│   │   ├── nfc_tag_provider.dart  # NfcTagNotifier — 태그 CRUD + 참조 정리
│   │   ├── alarm_provider.dart    # AlarmNotifier — 알람 CRUD + 스케줄링
│   │   ├── chain_provider.dart    # ChainNotifier — 체인 CRUD + 스케줄링
│   │   └── alarm_ringing_provider.dart # AlarmRingingNotifier — 현재 울림 상태
│   ├── widgets/
│   │   ├── day_selector.dart      # 공통 요일 선택 위젯
│   │   └── sound_selector.dart    # 공통 소리 선택 위젯
│   └── screens/
│       ├── home/
│       │   ├── home_screen.dart
│       │   └── widgets/
│       │       ├── alarm_list_item.dart
│       │       └── chain_card.dart
│       ├── alarm_edit_screen.dart
│       ├── chain_edit_screen.dart
│       ├── chain_step_edit_screen.dart
│       ├── nfc_tag_list_screen.dart
│       └── alarm_ringing_screen.dart
├── android/
│   └── app/src/main/kotlin/.../
│       ├── MainActivity.kt        # Flutter main activity
│       └── AlarmVolumeReceiver.kt # 알람 볼륨 브로드캐스트 수신기
├── pubspec.yaml
└── test/
    └── widget_test.dart
```

## Coding Conventions

### Naming
- **Classes / Models**: `PascalCase` (e.g., `AlarmData`, `NfcTagData`)
- **Functions / Variables**: `camelCase` (e.g., `alarmFiredCallback`, `nfcTagIds`)
- **File names**: `snake_case` (e.g., `alarm_model.dart`, `nfc_service.dart`)

### Formatting
- Indentation: **4 spaces**
- Formatter: follow `dart format` standards

### Code Style
- All model classes must implement `toJson()` / `fromJson()` / `copyWith()`
- Use `const` constructors and widgets wherever possible
- **Code comments**: written in **Korean**
- Section divider format: `// ─── 섹션명 ───`
- Code must be **modularized into separate files by feature** (do not pile all code into a single file)

## Common Commands

### Development
```bash
flutter run                  # Run app on connected Android device
flutter run --release        # Run in release mode
flutter analyze              # Static analysis
dart format .                # Format code
```

### Build
```bash
flutter build apk            # Build Android APK
flutter build apk --release  # Build release APK
```

### Test
```bash
flutter test                 # Run unit/widget tests
```

## Domain Knowledge

### Core Concepts
- **AlarmData**: A single alarm (time, days, NFC tags, sound, volume)
- **AlarmChain**: A chain of multiple alarms in sequence (e.g., wake up → gym)
- **ChainStep**: An individual step within a chain
- **NfcTagData**: A registered NFC tag (name + UID)

### Core Logic
- Alarm dismissal condition: scan the designated NFC tag UID (empty list allows any tag)
- Alarms scheduled via `android_alarm_manager_plus`; foreground service runs via `flutter_foreground_task` while ringing
- Auto-dismiss: alarm stops automatically 300 seconds (5 minutes) after it starts ringing
- Temporary mute: sound can be silenced for 2 minutes (alarm stays active)

### SharedPreferences Key Reference
- `alarm_nfc_uids_$id` — NFC UID list per alarm
- `active_nfc_uids` — NFC UIDs of the currently ringing alarm
- `alarm_volume_$id` / `alarm_sound_$id` — volume and sound per alarm
- `active_alarm_start_ms` — alarm start timestamp (used for auto-dismiss calculation)

### Backward Compatibility Notes
- Previous versions used a single `nfcTagId`; migrated to multiple `nfcTagIds`
- Always add migration logic when changing or removing SharedPreferences keys

## Instructions for Claude

### Code Modification Principles
- Minor changes can be made immediately
- **For large-scope changes, always explain first and get approval before proceeding**
- New code must be modularized into separate files by feature (no single-file dumps)
- Study existing patterns (`toJson`/`fromJson`/`copyWith`) before implementing, and follow them consistently

### CLAUDE.md Maintenance
- If code changes affect architecture, file structure, key names, or packages, update CLAUDE.md automatically at the same time

### Request Handling
- **If a request is ambiguous, always ask first**
- Never proceed based on inference alone
- If anything is unclear, confirm before executing

### Bug Fixes
- Explain the root cause in Korean first
- Propose the fix direction, then proceed

### Responses
- All responses to the user (developer) must be written in **Korean**
- Do not use **emoji** in any response

## Important Notes
- `build/` directory is auto-generated — never modify
- Always add backward-compatible migration logic when changing or removing SharedPreferences keys
- NFC is Android-only — separate handling required when expanding to iOS
- `AlarmVolumeReceiver.kt` is native Android code — cannot be replaced by a Flutter package