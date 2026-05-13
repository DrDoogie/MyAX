#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  회의록 앱 빌드 스크립트
#  사용법: ./build.sh
#  결과:  ./MeetingRecorder.app  (더블클릭으로 실행)
# ─────────────────────────────────────────────────────────────────
set -e

APP_NAME="MeetingRecorder"
BUNDLE_ID="com.myax.meetingrecorder"
SOURCES="Sources"
OUT_DIR="build"
APP_BUNDLE="${APP_NAME}.app"

# ── macOS 확인 ─────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 이 스크립트는 macOS에서만 실행할 수 있습니다."
    exit 1
fi

# ── Xcode Command Line Tools 확인 ──────────────
if ! xcrun --find swiftc &>/dev/null; then
    echo "❌ Xcode Command Line Tools가 필요합니다."
    echo "   터미널에서 실행: xcode-select --install"
    exit 1
fi

SDK=$(xcrun --show-sdk-path)
ARCH=$(uname -m)   # arm64 (Apple Silicon) 또는 x86_64 (Intel)
TARGET="${ARCH}-apple-macos14.0"

echo "🔨 빌드 시작 (${ARCH} / macOS 14+)"
echo "   SDK: ${SDK}"

# ── 이전 빌드 정리 ─────────────────────────────
rm -rf "${OUT_DIR}" "${APP_BUNDLE}"
mkdir -p "${OUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# ── Swift 컴파일 ───────────────────────────────
echo "⚙️  Swift 컴파일 중..."

swiftc \
    -sdk "${SDK}" \
    -target "${TARGET}" \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework Speech \
    -framework AppKit \
    -framework Foundation \
    -framework Security \
    -O \
    "${SOURCES}"/*.swift \
    -o "${OUT_DIR}/${APP_NAME}"

# ── 번들 조립 ──────────────────────────────────
echo "📦 앱 번들 생성 중..."

cp "${OUT_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Info.plist"              "${APP_BUNDLE}/Contents/Info.plist"

# 앱 아이콘이 있으면 복사
if [[ -f "AppIcon.icns" ]]; then
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# ── 서명 (임시 자체 서명) ──────────────────────
echo "✍️  앱 서명 중 (자체 서명)..."
codesign --force --deep --sign "-" "${APP_BUNDLE}" 2>/dev/null || true

# ── 격리 속성 제거 (Gatekeeper 우회) ──────────
xattr -rd com.apple.quarantine "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "✅ 빌드 완료!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  앱 위치: $(pwd)/${APP_BUNDLE}"
echo ""
echo "  실행 방법:"
echo "    open ${APP_BUNDLE}"
echo "  또는 Finder에서 ${APP_BUNDLE} 더블클릭"
echo ""
echo "  API 키 설정 (선택사항):"
echo "    ./set-api-key.sh sk-ant-xxxxxxx"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
