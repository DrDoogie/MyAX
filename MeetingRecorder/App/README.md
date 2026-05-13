# 회의록 앱 — 빠른 시작 가이드

## 설치 방법 (Xcode 없이)

> Xcode Command Line Tools만 필요합니다 (Xcode 앱 불필요).

### 1단계: Command Line Tools 설치

```bash
xcode-select --install
```

### 2단계: 앱 빌드

```bash
cd MeetingRecorder/App
chmod +x build.sh set-api-key.sh
./build.sh
```

### 3단계: API 키 설정 (선택사항)

```bash
./set-api-key.sh sk-ant-xxxxx
```
> API 키 없이도 앱이 동작하지만 AI 요약 없이 녹취 내용만 저장됩니다.

### 4단계: 실행

```bash
open MeetingRecorder.app
```
또는 Finder에서 `MeetingRecorder.app` 더블클릭.

---

## 사용 방법

1. **마이크 버튼** → 녹음 시작
2. **중지 버튼** → 녹음 종료 + 자동 처리
   - 음성 → 텍스트 변환 (기기 내 처리)
   - Claude AI로 회의록 자동 작성
   - Apple 메모 앱 "회의록" 폴더에 자동 저장
   - `~/Library/Application Support/MeetingRecorder/Notes/` 에 Markdown 백업

## 저장 위치

| 항목 | 위치 |
|---|---|
| 녹음 파일 | `~/Library/Application Support/MeetingRecorder/Recordings/` |
| 회의록 (Markdown) | `~/Library/Application Support/MeetingRecorder/Notes/` |
| Apple 메모 | 메모 앱 → "회의록" 폴더 |

## 개인정보 보호

- 음성 인식: 기기 내에서만 처리 (`requiresOnDeviceRecognition = true`)
- 녹음 파일: 기기 로컬 저장 (iCloud 동기화 없음)
- API 키: Keychain에만 저장, 코드에 하드코딩되지 않음
- Claude API 호출 시 녹취 텍스트만 전송, 음성 파일은 전송되지 않음
