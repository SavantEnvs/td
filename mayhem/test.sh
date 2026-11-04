#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# RUN TDLib's own unit tests for the code the harnesses fuzz (MessageEntities, Link, StringCleaning). Each
# test asserts concrete values (CHECK/ASSERT_EQ) and aborts the process on mismatch. The runner is
# mayhem_td_tests, linked by build.sh from test/{message_entities,link,string_cleaning}.cpp. A suite counts as
# passed only if the runner exits 0 AND reports every test the source file declares, so a neutered
# (exit(0)) or truncated runner fails.
RUNNER="$SRC/build-tests/mayhem_td_tests"
[ -x "$RUNNER" ] || { echo "missing $RUNNER (mayhem/build.sh builds it)" >&2; emit_ctrf "td-unit-tests" 0 1 0; exit 1; }

passed=0; failed=0
for suite in "MessageEntities:test/message_entities.cpp" "Link:test/link.cpp" "StringCleaning:test/string_cleaning.cpp"; do
  name="${suite%%:*}"; src="${suite#*:}"
  expected=$(grep -c "^TEST($name," "$src")
  out=$("$RUNNER" -v 1 -f "Test_${name}_" 2>&1); rc=$?
  ran=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -c 'Run test \[name:Test_'"$name"'_')
  if [ "$rc" -eq 0 ] && [ "$expected" -gt 0 ] && [ "$ran" -eq "$expected" ]; then
    passed=$((passed + ran))
  else
    echo "suite $name: rc=$rc ran=$ran expected=$expected" >&2
    printf '%s\n' "$out" | tail -20 >&2
    failed=$((failed + 1))
    passed=$((passed + ran))
  fi
done

emit_ctrf "td-unit-tests" "$passed" "$failed" 0
