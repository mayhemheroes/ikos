#!/usr/bin/env bash
#
# mayhem/test.sh — RUN ikos's full upstream test suite (built by mayhem/build.sh in build-tests/):
# core unit tests (Boost.Test), frontend/llvm regression tests (import + pass), and the analyzer
# regression tests (boa/dbz/mem/null/prover/uva/upa/sio/uio/shc/poa/pcmp/fca/dfa/sound), all via ctest.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

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

[ -d "$SRC/build-tests" ] || { echo "build-tests/ missing — mayhem/build.sh must run first" >&2; emit_ctrf cmake-ctest 0 1; exit 1; }

log=/tmp/ctest.log
( cd "$SRC/build-tests" && ctest -j"$MAYHEM_JOBS" --output-on-failure ) | tee "$log"
rc=${PIPESTATUS[0]}

# ctest summary: "100% tests passed, 0 tests failed out of 149"
total=$(sed -n 's/.*tests failed out of \([0-9]\+\).*/\1/p' "$log" | tail -1)
failed=$(sed -n 's/.*, \([0-9]\+\) tests failed out of.*/\1/p' "$log" | tail -1)
if [ -z "$total" ] || [ -z "$failed" ]; then
  echo "could not parse ctest summary" >&2
  emit_ctrf cmake-ctest 0 1
  exit 1
fi
passed=$(( total - failed ))
emit_ctrf cmake-ctest "$passed" "$failed"
exit $(( failed > 0 ? 1 : rc ))
