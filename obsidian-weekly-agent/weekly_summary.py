#!/usr/bin/env python3
"""
Obsidian Weekly Summary Generator
Reads this week's Obsidian notes, summarizes them by date and meeting,
saves the summary as Markdown in WeeklySummaries/, and reads it aloud via `say`.
"""

import os
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

import anthropic

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VAULT_PATH = Path(os.environ.get("OBSIDIAN_VAULT", str(Path.home() / "Documents" / "Obsidian")))
SUMMARIES_DIR_NAME = "WeeklySummaries"

MEETING_KEYWORDS = {"회의", "meeting", "미팅", "mtg", "standup", "스탠드업", "1on1", "원온원"}


# ---------------------------------------------------------------------------
# Note discovery
# ---------------------------------------------------------------------------

def get_week_range() -> tuple[date, date]:
    today = date.today()
    start = today - timedelta(days=today.weekday())  # Monday
    end = start + timedelta(days=6)                  # Sunday
    return start, end


def collect_notes(vault: Path, start: date, end: date) -> list[dict]:
    """Return list of {path, date, content} for notes modified this week."""
    notes = []
    for md_file in vault.rglob("*.md"):
        # Skip WeeklySummaries output folder to avoid recursion
        if SUMMARIES_DIR_NAME in md_file.parts:
            continue
        mtime = date.fromtimestamp(md_file.stat().st_mtime)
        if start <= mtime <= end:
            try:
                content = md_file.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            notes.append({"path": md_file, "date": mtime, "content": content})
    notes.sort(key=lambda n: (n["date"], n["path"].name))
    return notes


def is_meeting_note(note: dict) -> bool:
    name_lower = note["path"].name.lower()
    content_lower = note["content"][:500].lower()
    return any(kw in name_lower or kw in content_lower for kw in MEETING_KEYWORDS)


# ---------------------------------------------------------------------------
# Claude API summarization
# ---------------------------------------------------------------------------

WEEKDAY_KR = {0: "월요일", 1: "화요일", 2: "수요일", 3: "목요일", 4: "금요일", 5: "토요일", 6: "일요일"}


def build_prompt(notes: list[dict], start: date, end: date) -> str:
    week_label = f"{start.strftime('%Y년 %-m월 %-d일')} ~ {end.strftime('%-m월 %-d일')}"

    # Group notes by date
    from collections import defaultdict
    by_date: dict[date, list[dict]] = defaultdict(list)
    for note in notes:
        by_date[note["date"]].append(note)

    sections = []
    for day, day_notes in sorted(by_date.items()):
        day_label = f"{day.strftime('%-m월 %-d일')}({WEEKDAY_KR[day.weekday()]})"
        note_texts = "\n".join(
            f"[{n['path'].stem}]\n{n['content']}" for n in day_notes
        )
        sections.append(f"--- {day_label} ---\n{note_texts}")

    combined = "\n\n".join(sections)
    num_days = len(by_date)
    # Target ~1,500 chars total for ~5 min speech; allocate evenly per day
    chars_per_day = max(150, 1500 // max(num_days, 1))

    return f"""당신은 팀 브리핑 스피치 작성 전문가입니다.
아래는 {week_label} 한 주간의 업무 노트입니다.

다음 조건을 엄수하여 브리핑 스크립트를 작성하세요:

1. **출력 형식**: 말로 읽히는 자연스러운 한국어 산문(prose). 마크다운 헤더(#), 불릿(-,*), 번호 목록 금지.
2. **구조**: 날짜 순서대로 하루씩 이어지는 하나의 연속된 단락. 날짜 전환 시 "다음으로 X월 Y일에는," 처럼 자연스럽게 연결.
3. **분량**: 전체 약 1,500자 이내 (날짜당 약 {chars_per_day}자). 절대 이를 초과하지 마세요.
4. **마무리**: 마지막 날짜 요약 후 단 한 번 짧게 마무리. "덧붙이자면", "또한", "이 외에도" 등으로 이미 끝난 뒤 다시 시작하지 마세요.
5. **내용**: 각 날짜의 핵심 이슈 1~2개만 간결하게. 회의 내용은 날짜 안에 녹여서 별도 섹션 없이 서술.
6. **톤**: 팀 전체에게 브리핑하는 차분하고 명확한 어조.

---
{combined}
---

위 노트를 바탕으로 브리핑 스크립트를 작성하세요. 조건을 어기면 안 됩니다."""


def summarize_with_claude(notes: list[dict], start: date, end: date) -> str:
    client = anthropic.Anthropic()
    prompt = build_prompt(notes, start, end)

    print("Claude API로 요약 생성 중...", flush=True)

    with client.messages.stream(
        model="claude-opus-4-8",
        max_tokens=8192,
        thinking={"type": "adaptive"},
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        for text in stream.text_stream:
            print(text, end="", flush=True)
        message = stream.get_final_message()

    print()  # newline after streaming output

    # Extract text blocks only (skip thinking blocks)
    parts = []
    for block in message.content:
        if block.type == "text":
            parts.append(block.text)
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# File output
# ---------------------------------------------------------------------------

def save_summary(summary: str, vault: Path, start: date) -> Path:
    from datetime import datetime
    year, week_num, _ = start.isocalendar()
    summaries_dir = vault / SUMMARIES_DIR_NAME
    summaries_dir.mkdir(parents=True, exist_ok=True)

    base = f"{year}-W{week_num:02d}_weekly_summary"
    out_file = summaries_dir / f"{base}.md"
    if out_file.exists():
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_file = summaries_dir / f"{base}_{timestamp}.md"

    header = (
        f"# 주간 요약 {year}-W{week_num:02d}\n"
        f"생성일: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n"
    )
    out_file.write_text(header + summary, encoding="utf-8")
    return out_file


# ---------------------------------------------------------------------------
# Text-to-speech
# ---------------------------------------------------------------------------

def speak_summary(summary: str) -> None:
    import re
    plain = re.sub(r"[#*`_\[\]()\-]", "", summary)
    plain = re.sub(r"\n{2,}", " ", plain).strip()
    try:
        subprocess.run(["say", "-v", "Yuna", plain], check=False)
    except FileNotFoundError:
        print("(say 명령어를 찾을 수 없습니다. macOS에서 실행해 주세요.)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    start, end = get_week_range()
    print(f"이번 주 범위: {start} ~ {end}")

    if not VAULT_PATH.exists():
        print(f"Obsidian 볼트를 찾을 수 없습니다: {VAULT_PATH}")
        print("OBSIDIAN_VAULT 환경 변수로 경로를 설정해 주세요.")
        sys.exit(1)

    print(f"볼트 경로: {VAULT_PATH}")
    notes = collect_notes(VAULT_PATH, start, end)

    if not notes:
        print("이번 주에 작성된 노트가 없습니다.")
        sys.exit(0)

    meeting_notes = [n for n in notes if is_meeting_note(n)]
    print(f"노트 {len(notes)}개 발견 (회의 노트 {len(meeting_notes)}개)")

    summary = summarize_with_claude(notes, start, end)

    out_file = save_summary(summary, VAULT_PATH, start)
    print(f"\n요약 저장 완료: {out_file}")

    print("\n요약을 읽어드립니다...")
    speak_summary(summary)


if __name__ == "__main__":
    main()
