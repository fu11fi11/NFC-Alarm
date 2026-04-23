# NFC 알람

바이브코딩으로 내가 필요한 걸 만들어보자는 의도에서 시작한 프로젝트.

NFC 태그를 스캔해야만 알람을 끌 수 있는 Android 알람 앱.

사용자가 특정 장소(예: 화장실, 헬스장)에 NFC 태그를 붙여두고, 실제로 그 장소로 이동해야 알람이 꺼지도록 강제합니다. 서버 없이 완전 오프라인으로 동작하며, 모든 데이터는 기기 내 SharedPreferences에 저장됩니다.



---

## 주요 기능

- **태그해야만 종료되는 알람**: 지정된 장소(화장실, 헬스장, 학교, 회사 등)에 미리 붙여둔 NFC 태그를 스캔해야만 알람 종료
- **NFC 태그 관리**: 태그에 이름을 붙여 등록·수정·삭제
- **알람 체인**: 여러 알람을 순서대로 묶어 단계별로 실행 (예: 기상 → 헬스장)
- **임시 음소거**: 2분간 소리 끄기 (알람 자체는 유지)
- **자동 꺼짐**: 알람 울린 후 5분 경과 시 자동 종료

---

## 동작 방식

1. 앱에서 알람 시간과 요일, 해제용 NFC 태그를 설정
2. `android_alarm_manager_plus`가 지정 시각에 백그라운드에서 알람을 실행
3. `flutter_foreground_task`로 포그라운드 서비스를 띄워 알람 유지
4. 사용자가 NFC 태그가 있는 장소로 이동해 태그를 스캔하면 알람 해제

---

## 기술 스택


| 항목        | 내용                          |
| --------- | --------------------------- |
| Framework | Flutter 3.x / Dart 3.x      |
| 플랫폼       | Android (iOS 확장 예정)         |
| 로컬 저장소    | SharedPreferences (완전 오프라인) |


### 주요 패키지


| 패키지                           | 용도                     |
| ----------------------------- | ---------------------- |
| `nfc_manager`                 | NFC 태그 스캔              |
| `android_alarm_manager_plus`  | 백그라운드 알람 예약            |
| `flutter_foreground_task`     | 알람 울림 중 포그라운드 서비스 유지   |
| `flutter_local_notifications` | 풀스크린 알람 알림 표시          |
| `flutter_ringtone_player`     | 알람 소리 재생               |
| `vibration`                   | 진동                     |
| `android_intent_plus`         | 볼륨 조절 등 Android 인텐트 처리 |
| `shared_preferences`          | 알람·태그 데이터 로컬 저장        |
| `timezone`                    | 타임존 기반 알람 시간 계산        |


---

## 프로젝트 구조

```
nfc_alarm/
├── lib/
│   └── main.dart                        # 전체 앱 로직
├── android/
│   └── app/src/main/kotlin/.../
│       ├── MainActivity.kt              # Flutter 메인 액티비티
│       └── AlarmVolumeReceiver.kt       # 알람 볼륨 브로드캐스트 수신
├── pubspec.yaml
└── test/
    └── widget_test.dart
```

---

## 개발 환경 설정

### 요구사항

- Flutter SDK 3.x 이상
- Android SDK (API 21+)
- NFC를 지원하는 Android 기기

### 설치 및 실행

```bash
# 의존성 설치
flutter pub get

# 연결된 Android 기기에서 실행
flutter run

# 릴리즈 모드 실행
flutter run --release
```

---

## Android 권한

앱이 정상 동작하려면 다음 권한이 필요합니다.

- `NFC` — NFC 태그 스캔
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — 정확한 알람 예약
- `RECEIVE_BOOT_COMPLETED` — 재부팅 후 알람 재등록
- `FOREGROUND_SERVICE` — 알람 울림 중 포그라운드 서비스 유지
- `POST_NOTIFICATIONS` — 알람 알림 표시
- `SYSTEM_ALERT_WINDOW` (선택) — 잠금화면 위 오버레이 표시

---

## 데이터 모델

### AlarmData

단일 알람. 시간, 반복 요일, 연결된 NFC 태그 목록, 소리, 볼륨을 가집니다.

### AlarmChain

여러 알람을 순서대로 묶은 체인. 동일 요일에 여러 단계의 알람을 실행합니다.

### ChainStep

체인 안의 개별 단계. 시간, 라벨, NFC 태그, 소리, 볼륨을 가집니다.

### NfcTagData

등록된 NFC 태그. 이름과 UID를 가집니다.

---

## 라이선스

개인 프로젝트입니다. 별도 라이선스 없음.