#!/usr/bin/env bash
# End-to-end verification for dupefind. Runs on macOS with just Command Line Tools.
# Exits non-zero on any failure. Prints a summary at the end.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/.build/debug/dupefind"

PASS=0
FAIL=0
FAIL_NAMES=()

pass() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); echo "  ❌ $1: $2"; }

section() { echo; echo "== $1 =="; }

# ---------- build ----------
section "build"
if swift build --configuration debug 2>&1 | tail -5; then
    pass "swift build"
else
    fail "swift build" "build failed"
    exit 1
fi
[[ -x "$CLI" ]] || { fail "cli exists" "$CLI not found"; exit 1; }

# ---------- fixture ----------
FIX="$(mktemp -d -t dfverify)"
trap 'rm -rf "$FIX"' EXIT

# Group A: 2 identical photos
printf 'photoA' > "$FIX/a1.jpg"
printf 'photoA' > "$FIX/a2.jpg"
# Group B: 3 identical docs in a subdir
mkdir -p "$FIX/nested"
printf 'docB' > "$FIX/nested/b1.txt"
printf 'docB' > "$FIX/nested/b2.txt"
printf 'docB' > "$FIX/nested/b3.txt"
# Uniques
printf 'unique1' > "$FIX/solo.png"
printf 'unique2' > "$FIX/solo.pdf"
# Same size, different content — should NOT group
printf 'aaaa' > "$FIX/s4a.txt"
printf 'bbbb' > "$FIX/s4b.txt"
# Excluded: put dupes inside .git and Library, should be ignored
mkdir -p "$FIX/.git" "$FIX/Library"
printf 'inside-git' > "$FIX/.git/x1.jpg"
printf 'inside-git' > "$FIX/.git/x2.jpg"
printf 'inside-lib' > "$FIX/Library/y1.jpg"
printf 'inside-lib' > "$FIX/Library/y2.jpg"

section "correctness — CLI JSON output"
JSON="$("$CLI" --json --quiet "$FIX")"

count_groups() { echo "$JSON" | /usr/bin/python3 -c 'import json,sys;print(len(json.load(sys.stdin)["groups"]))'; }
groups_meta()  { echo "$JSON" | /usr/bin/python3 -c 'import json,sys
r=json.load(sys.stdin)
for g in r["groups"]:
    print(g["hash"], len(g["files"]), g["size"])'; }

N="$(count_groups)"
if [[ "$N" == "2" ]]; then pass "found exactly 2 duplicate groups"; else fail "group count" "expected 2, got $N"; fi

if ! echo "$JSON" | grep -q '/.git/'; then pass "no results from .git"; else fail ".git excluded" "found .git paths in output"; fi
if ! echo "$JSON" | grep -q '/Library/'; then pass "no results from Library"; else fail "Library excluded" "found Library paths in output"; fi

# Confirm one group has 2 files, another has 3
COUNTS_SORTED="$(groups_meta | awk '{print $2}' | sort -n | tr '\n' ' ')"
if [[ "$COUNTS_SORTED" == "2 3 " ]]; then pass "group sizes are {2,3}"; else fail "group sizes" "got: $COUNTS_SORTED"; fi

section "correctness — hash matches shasum"
CLI_HASH="$(echo "$JSON" | /usr/bin/python3 -c 'import json,sys
r=json.load(sys.stdin)
for g in r["groups"]:
    if len(g["files"])==2: print(g["hash"]); break')"
REF_HASH="$(shasum -a 256 "$FIX/a1.jpg" | awk "{print \$1}")"
if [[ "$CLI_HASH" == "$REF_HASH" ]]; then pass "dupefind hash == shasum -a 256"; else fail "hash equivalence" "cli=$CLI_HASH shasum=$REF_HASH"; fi

section "kinds filter"
KJSON="$("$CLI" --json --quiet --kinds photo "$FIX")"
KN="$(echo "$KJSON" | /usr/bin/python3 -c 'import json,sys;print(len(json.load(sys.stdin)["groups"]))')"
if [[ "$KN" == "1" ]]; then pass "--kinds photo returns only photo group"; else fail "kinds filter" "expected 1 group, got $KN"; fi

section "trash dry-run does NOT delete"
BEFORE="$(ls "$FIX/nested" | wc -l | tr -d ' ')"
"$CLI" --quiet --trash keep-first-path "$FIX" > /dev/null
AFTER="$(ls "$FIX/nested" | wc -l | tr -d ' ')"
if [[ "$BEFORE" == "$AFTER" ]]; then pass "dry-run preserved files"; else fail "dry-run" "files changed from $BEFORE to $AFTER"; fi

section "trash --confirm actually removes copies from disk"
"$CLI" --quiet --trash keep-first-path --confirm "$FIX" > /dev/null
# Now nested/ should have exactly 1 file (2 of 3 removed for group B),
# and $FIX top-level should have lost 1 of the 2 a*.jpg files.
NESTED_LEFT="$(ls "$FIX/nested" | wc -l | tr -d ' ')"
A_LEFT="$(ls "$FIX"/a*.jpg 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$NESTED_LEFT" == "1" && "$A_LEFT" == "1" ]]; then
    pass "kept 1 copy per group, removed the rest ($A_LEFT + $NESTED_LEFT survivors)"
else
    fail "trash --confirm" "expected 1 & 1, got a=$A_LEFT nested=$NESTED_LEFT"
fi

# Re-scan: should now report 0 duplicate groups
RESCAN_N="$("$CLI" --json --quiet "$FIX" | /usr/bin/python3 -c 'import json,sys;print(len(json.load(sys.stdin)["groups"]))')"
if [[ "$RESCAN_N" == "0" ]]; then pass "post-trash rescan finds 0 duplicates"; else fail "post-trash rescan" "expected 0, got $RESCAN_N"; fi

# ---------- summary ----------
echo
echo "======================================"
echo "  passed: $PASS   failed: $FAIL"
echo "======================================"
if (( FAIL > 0 )); then
    for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
    exit 1
fi
