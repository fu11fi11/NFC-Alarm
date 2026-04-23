# nfc_alarm
> ⚠️ 앱 이름은 추후 변경 예정

## Project Overview
NFC 태그를 스캔해야만 알람을 끌 수 있는 Android 알람 앱.
사용자가 특정 장소(예: 화장실, 헬스장)에 NFC 태그를 붙여두고,
실제로 그 장소로 이동해야 알람이 꺼지도록 강제한다.
서버 없이 완전 오프라인으로 동작하며, 모든 데이터는 기기 내 SharedPreferences에 저장된다.

## Architecture
- **현재**: 모든 로직이 `lib/main.dart` 단일 파일에 집중됨 → 점진적으로 기능별 파일 분리 예정
- **백그라운드 알람**: `android_alarm_manager_plus`로 알람 예약, `flutter_foreground_task`로 울림 중 포그라운드 서비스 유지
- **데이터 저장**: SharedPreferences에 JSON 직렬화하여 저장 (DB 없음)
- **플랫폼**: 현재 Android 전용, iOS 확장 예정

## Tech Stack

### Core
- **Framework**: Flutter 3.41.7 (Dart 3.11.5)
- **Target Platform**: Android (iOS 확장 예정)
- **로컬 저장소**: SharedPreferences (완전 오프라인 앱)

### 주요 패키지
| 패키지 | 용도 |
|--------|------|
| `nfc_manager` | NFC 태그 스캔 |
| `android_alarm_manager_plus` | 백그라운드 알람 예약 |
| `flutter_foreground_task` | 알람 울림 중 포그라운드 서비스 유지 |
| `flutter_local_notifications` | 알람 알림 표시 |
| `flutter_ringtone_player` | 알람 소리 재생 |
| `vibration` | 진동 |
| `android_intent_plus` | Android 인텐트 (볼륨 조절 등) |
| `shared_preferences` | 알람/태그 데이터 로컬 저장 |
| `timezone` | 타임존 기반 알람 시간 계산 |

## Project Structure
```
nfc_alarm/
├── lib/
│   └── main.dart                  # 현재 전체 앱 로직 (리팩토링 예정)
├── android/
│   └── app/src/main/kotlin/.../
│       ├── MainActivity.kt        # Flutter 메인 액티비티
│       └── AlarmVolumeReceiver.kt # 알람 볼륨 브로드캐스트 수신
├── ios/                           # iOS 빌드 파일 (미래 확장용, 현재 미사용)
├── pubspec.yaml                   # 패키지 의존성
└── test/
    └── widget_test.dart           # 기본 테스트
```

### 리팩토링 목표 구조 (기능별 파일 분리)
```
lib/
├── main.dart
├── models/
│   ├── alarm_data.dart
│   ├── alarm_chain.dart
│   ├── chain_step.dart
│   └── nfc_tag_data.dart
├── screens/
│   ├── home_screen.dart
│   ├── alarm_ringing_screen.dart
│   └── nfc_tag_screen.dart
└── services/
    ├── alarm_service.dart
    └── nfc_service.dart
```

## Coding Conventions

### 네이밍
- **클래스 / 모델**: `PascalCase` (예: `AlarmData`, `NfcTagData`)
- **함수 / 변수**: `camelCase` (예: `alarmFiredCallback`, `nfcTagIds`)
- **파일명**: `snake_case` (예: `alarm_model.dart`, `nfc_service.dart`)

### 포매팅
- 들여쓰기: **4칸 스페이스**
- 포매터: `dart format` 기준 준수

### 코드 스타일
- 모든 모델 클래스에 `toJson()` / `fromJson()` / `copyWith()` 구현
- `const` 생성자 및 위젯 적극 활용
- 주석은 **한국어**로 작성
- 구분선 주석 형식: `// ─── 섹션명 ───`
- 코드는 반드시 **기능별로 파일을 나눠 모듈화** (단일 파일에 모든 코드 몰아넣기 금지)

## Common Commands

### 개발
```bash
flutter run                  # 연결된 Android 기기에서 앱 실행
flutter run --release        # 릴리즈 모드로 실행
flutter analyze              # 정적 분석
dart format .                # 코드 포매팅
```

### 빌드
```bash
flutter build apk            # Android APK 빌드
flutter build apk --release  # 릴리즈 APK 빌드
```

### 테스트
```bash
flutter test                 # 유닛/위젯 테스트 실행
```

## Domain Knowledge

### 핵심 개념
- **AlarmData**: 단일 알람 (시간, 요일, NFC 태그, 소리, 볼륨)
- **AlarmChain**: 여러 알람을 순서대로 묶은 체인 (예: 기상 → 헬스장)
- **ChainStep**: 체인 안의 개별 단계
- **NfcTagData**: 등록된 NFC 태그 (이름 + UID)

### 핵심 로직
- 알람 해제 조건: 지정된 NFC 태그 UID 스캔 (빈 목록이면 아무 태그나 허용)
- 알람은 `android_alarm_manager_plus`로 예약, 울릴 때 `flutter_foreground_task`로 포그라운드 서비스 실행
- 자동 꺼짐: 알람 울린 후 300초(5분) 경과 시 자동 종료
- 임시 음소거: 2분간 소리 끄기 가능 (알람은 유지)

### SharedPreferences 주요 키
- `alarm_nfc_uids_$id` — 알람별 NFC UID 목록
- `active_nfc_uids` — 현재 울리는 알람의 NFC UID
- `alarm_volume_$id` / `alarm_sound_$id` — 알람별 볼륨·소리
- `active_alarm_start_ms` — 알람 시작 시각 (자동 꺼짐 계산용)

### 하위 호환 주의
- 구버전에서 단일 `nfcTagId` → 다중 `nfcTagIds`로 마이그레이션된 이력 있음
- SharedPreferences 키 변경 시 반드시 마이그레이션 로직 추가할 것

## Instructions for Claude

### 코드 수정 원칙
- 소규모 수정은 바로 진행해도 됨
- **수정 범위가 클 경우 반드시 먼저 설명하고 승인받은 후 진행**
- 새 코드 작성 시 반드시 기능별로 파일을 나눠 모듈화할 것 (단일 파일에 모든 코드 금지)
- 기존 패턴(`toJson`/`fromJson`/`copyWith`)을 파악한 후 일관되게 구현

### CLAUDE.md 유지보수
- 코드 수정으로 인해 아키텍처, 파일 구조, 주요 키, 패키지 등이 변경된 경우 CLAUDE.md도 함께 자동 업데이트할 것

### 요청 처리 원칙
- **요청이 불명확하면 반드시 먼저 질문할 것**
- 절대 추론으로 먼저 실행하지 말 것
- 애매한 부분이 하나라도 있으면 실행 전에 확인

### 버그 수정 시
- 원인을 먼저 한국어로 설명
- 수정 방향 제시 후 진행

### 응답
- 모든 응답은 **한국어**로 작성

## Important Notes
- `build/` 폴더는 자동 생성 파일 — 절대 수정 금지
- SharedPreferences 키를 변경하거나 삭제할 경우 반드시 하위 호환 마이그레이션 로직 추가
- NFC는 Android 전용 기능 — iOS 확장 시 별도 처리 필요
- `AlarmVolumeReceiver.kt`는 Android 네이티브 코드 — Flutter 패키지로 대체 불가
