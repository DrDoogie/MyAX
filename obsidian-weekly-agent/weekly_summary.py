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

def build_prompt(notes: list[dict], start: date, end: date) -> str:
    week_label = f"{start.strftime('%Y-%m-%d')} ~ {end.strftime('%Y-%m-%d')}"
    sections = []
    for note in notes:
        sections.append(
            f"=== [{note['date'].strftime('%Y-%m-%d')}] {note['path'].stem} ===\n{note['content']}"
        )
    combined = "\n\n".join(sections)

    return f"""You are a concise and insightful note summarizer. Below are all Obsidian notes from the week of {week_label}.

Please produce a structured weekly summary in Korean with the following sections:

## 📅 날짜별 요약 (Daily Summary)
Summarize the key topics, tasks, and ideas for each date that has notes.

## 🗣️ 회의별 요약 (Meeting Summary)
For each meeting note found, write a brief summary covering purpose, key decisions, and action items.
If no meeting notes were found, state that.

## ✅ 주요 액션 아이템 (Key Action Items)
Bullet list of the most important follow-ups and tasks from the entire week.

## 💡 주간 인사이트 (Weekly Insights)
2–3 sentences synthesizing the overall theme or learnings of the week.

---
NOTES:
{combined}
"""


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
    year, week_num, _ = start.isocalendar()
    summaries_dir = vault / SUMMARIES_DIR_NAME
    summaries_dir.mkdir(parents=True, exist_ok=True)
    out_file = summaries_dir / f"{year}-W{week_num:02d}_weekly_summary.md"

    header = (
        f"# 주간 요약 {year}-W{week_num:02d}\n"
        f"생성일: {date.today().strftime('%Y-%m-%d')}\n\n"
    )
    out_file.write_text(header + summary, encoding="utf-8")
    return out_file


# ---------------------------------------------------------------------------
# Text-to-speech
# ---------------------------------------------------------------------------

def speak_summary(summary: str) -> None:
    # Strip markdown syntax for cleaner speech
    import re
    plain = re.sub(r"[#*`_\[\]()]", "", summary)
    plain = re.sub(r"\n{2,}", "\n", plain).strip()
    # Limit to first ~2000 chars to keep TTS duration reasonable
    plain = plain[:2000]
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
