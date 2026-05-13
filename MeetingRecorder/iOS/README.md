# 회의록 iOS 앱 — 설치 가이드

## 설치 방법

### 필요 사항
- Mac (Xcode 설치된 것)  
- iPhone 또는 iPad  
- Apple 계정 (무료 개발자 계정으로 충분 — App Store 배포 불필요)

### 1단계: Xcode에서 프로젝트 열기

```
MeetingRecorder/iOS/MeetingRecorder.xcodeproj
```
더블클릭하면 Xcode가 자동으로 열립니다.

### 2단계: 서명 설정 (한 번만)

1. Xcode 왼쪽 파일 목록에서 `MeetingRecorder` (파란 아이콘) 클릭
2. `Signing & Capabilities` 탭 클릭
3. **Team** → 본인 Apple ID 선택
4. Bundle Identifier를 고유하게 변경 (예: `com.홍길동.meetingrecorder`)

### 3단계: 기기 연결 후 실행

1. iPhone/iPad를 Mac에 USB 연결
2. Xcode 상단 기기 선택 → 내 iPhone/iPad 선택
3. `▶ Run` 버튼 (또는 `Cmd+R`) 클릭
4. 처음 실행 시 기기에서: **설정 → 일반 → VPN 및 기기 관리 → 신뢰** 탭으로 이동해 허용

### 4단계: API 키 설정 (선택사항)

앱 실행 후 우상단 **⚙️ 설정** → API 키 입력

---

## 앱 기능

| 화면 | 기능 |
|---|---|
| **메인** | 녹음 시작/중지 버튼, 파형, 타이머 |
| **회의록 목록** | 저장된 회의록 검색 및 조회 |
| **회의록 상세** | 마크다운 렌더링, 메모 앱으로 공유 |
| **설정** | API 키 관리, 개인정보 정책 확인 |

## 사용 흐름

```
🎙️ 버튼 → 녹음 시작
    ↓
⏹️ 버튼 → 녹음 중지
    ↓
📝 음성 → 텍스트 (기기 내 처리)
    ↓
🤖 Claude AI → 구조화된 회의록
    ↓
📋 앱 내 저장 + 공유 시트로 메모 앱에 저장
```

## 백그라운드 녹음

앱이 백그라운드로 가도 녹음이 계속됩니다  
(`UIBackgroundModes: audio` 설정됨)
