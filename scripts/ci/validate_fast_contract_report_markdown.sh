#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-${FAST_CONTRACT_REPORT:-}}"

if [[ -z "$report_path" || ! -f "$report_path" ]]; then
  echo "[contracts][fail] fast contract report not found: ${report_path:-<empty>}" >&2
  exit 1
fi

python3 - "$report_path" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

if not lines:
    raise SystemExit(f"[contracts][fail] empty report: {path}")

if not re.match(r"^# Fast Contract Gate Report \([0-9]{8}-[0-9]{6}\)$", lines[0]):
    raise SystemExit("[contracts][fail] report header must match '# Fast Contract Gate Report (YYYYMMDD-HHMMSS)'")

status_matches = re.findall(r"^- Status:[ \t]*(PASS|FAIL)$", text, flags=re.MULTILINE)
if len(status_matches) != 1:
    raise SystemExit("[contracts][fail] report must contain exactly one '- Status: PASS|FAIL' line")

cmd_matches = re.findall(r"^- Command:[ \t]*(.+)$", text, flags=re.MULTILINE)
if len(cmd_matches) != 1:
    raise SystemExit("[contracts][fail] report must contain exactly one '- Command: ...' line")

if cmd_matches[0].strip() != "make test-ci-fast-contracts":
    raise SystemExit("[contracts][fail] report command must be 'make test-ci-fast-contracts'")

if "## Output" not in text:
    raise SystemExit("[contracts][fail] report missing '## Output' section")

if "```text" not in text or text.count("```") < 2:
    raise SystemExit("[contracts][fail] report output must be enclosed in a text code fence")

if text.find("## Output") > text.find("```text"):
    raise SystemExit("[contracts][fail] report output fence must appear after '## Output'")

print(f"[contracts][ok] validated fast contract report markdown: {path}")
PY
