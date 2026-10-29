#!/usr/bin/env bash
#
# mayhem/test.sh — RUN CRoaring's OWN ctest suite (cmocka unit tests + examples; built by mayhem/build.sh in build/tests).
# exit 0 = pass. PATCH-grade oracle: after an agent patches the source, the grader
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

# Each ctest entry is run on its own and judged by what the program printed, not only by its exit status:
#  - cmocka suites print "[  PASSED  ] N test(s)." -> N passed;
#  - examples / amalgamation demos print their results -> 1 passed if they exit 0 with output;
#  - a non-zero exit, a cmocka FAILED line, or a program that prints nothing (neutered / missing) -> 1 failed.
BUILD="$SRC/build/tests"
if [ ! -f "$BUILD/CTestTestfile.cmake" ]; then echo "missing $BUILD (build.sh bug)" >&2; emit_ctrf "cmocka-ctest" 0 1 0; exit $?; fi
passed=0
failed=0
for name in $(ctest --test-dir "$BUILD" -N | sed -n 's/^ *Test *#[0-9]*: //p'); do
  out="$(ctest --test-dir "$BUILD" -R "^${name}\$" -V 2>&1)"; rc=$?
  body="$(printf '%s\n' "$out" | grep -E '^[0-9]+: ' | grep -vE '^[0-9]+: (Test command|Working Directory|Test timeout|Environment variables)' || true)"
  n=$(printf '%s\n' "$body" | sed -n 's/^[0-9]*: \[  PASSED  \] \([0-9][0-9]*\) test(s)\..*/\1/p' | awk '{s+=$1} END {print s+0}')
  if [ "$rc" -ne 0 ] || printf '%s\n' "$body" | grep -q '\[  FAILED  \]'; then
    echo "FAIL: $name (ctest rc=$rc)" >&2; printf '%s\n' "$body" | tail -20 >&2; failed=$((failed + 1))
  elif [ -n "$n" ] && [ "$n" -gt 0 ]; then
    echo "ok: $name ($n cmocka tests)"; passed=$((passed + n))
  elif [ -n "$body" ]; then
    echo "ok: $name"; passed=$((passed + 1))
  else
    echo "FAIL: $name printed nothing (neutered or missing program)" >&2; failed=$((failed + 1))
  fi
done
emit_ctrf "cmocka-ctest" "$passed" "$failed" 0
