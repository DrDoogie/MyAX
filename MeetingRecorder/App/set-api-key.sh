#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  Anthropic API 키를 macOS Keychain에 안전하게 저장합니다.
#  사용법: ./set-api-key.sh sk-ant-xxxxxx
# ─────────────────────────────────────────────────────────────────

if [[ -z "$1" ]]; then
    echo "사용법: ./set-api-key.sh <API_KEY>"
    echo "예시:   ./set-api-key.sh sk-ant-api03-xxx..."
    echo ""
    echo "API 키는 https://console.anthropic.com 에서 발급받으세요."
    exit 1
fi

API_KEY="$1"
KEYCHAIN_SERVICE="com.myax.meetingrecorder"
KEYCHAIN_ACCOUNT="anthropic_api_key"

# 기존 키 삭제 후 새로 저장
security delete-generic-password \
    -s "${KEYCHAIN_SERVICE}" \
    -a "${KEYCHAIN_ACCOUNT}" \
    2>/dev/null || true

security add-generic-password \
    -s "${KEYCHAIN_SERVICE}" \
    -a "${KEYCHAIN_ACCOUNT}" \
    -w "${API_KEY}" \
    -U

echo "✅ API 키가 Keychain에 안전하게 저장되었습니다."
echo "   앱을 재시작하면 자동으로 적용됩니다."
