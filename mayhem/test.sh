#!/usr/bin/env bash
#
# mayhem/test.sh — RUN hanz2piny's test suite (prebuilt by mayhem/build.sh; nothing compiles here).
#
# Upstream ships tests only for its vendored utfcpp library (src/lib/3rd/utfcpp/test_drivers):
#   * utfcpp_smoketest    — assert-based known-answer tests over the utf8 API (aborts on mismatch)
#   * utfcpp_negativetest — checks invalid-UTF-8 detection against test_data/negative/utf8_invalid.txt;
#                           prints a diagnostic line for every mismatch (empty output = pass)
# hanz2piny itself ships NO tests, so we add authored known-answer tests: run the clean oracle
# binary on the committed seed and diff against committed golden outputs (default / --tone /
# --camel --polyphone all). A PATCH that neuters the program to exit(0) produces no output and
# FAILS the golden diffs (anti-reward-hack).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "${SRC:-/mayhem}"

passed=0; failed=0
check() { # <name> <rc>
  if [ "$2" -eq 0 ]; then echo "  ok   - $1"; passed=$((passed+1))
  else echo "  FAIL - $1"; failed=$((failed+1)); fi
}

# emit_ctrf <tool> <passed> <failed> [skipped]
emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"
  local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

BIN=build-oracle/hanz2piny
SMOKE=build-oracle/utfcpp_smoketest
NEG=build-oracle/utfcpp_negativetest
SEED=mayhem/hanz2piny/testsuite/testhanzi.txt
GOLD=mayhem/hanz2piny/golden
for b in "$BIN" "$SMOKE" "$NEG"; do
  if [ ! -x "$b" ]; then
    echo "test.sh: $b missing — build.sh must build it (not rebuilding here)" >&2
    emit_ctrf hanz2piny 0 1; exit 1
  fi
done

# 1) utfcpp smoke test: assert-based known-answer suite (SIGABRT on any mismatch).
"$SMOKE" >/tmp/utfcpp_smoke.log 2>&1
check "utfcpp smoke_test (assert-based KATs)" $?

# 2) utfcpp negative test: must exit 0 AND report no unexpected (in)valid lines.
NEG_OUT="$("$NEG" src/lib/3rd/utfcpp/test_data/negative/utf8_invalid.txt 2>&1)"; neg_rc=$?
if [ "$neg_rc" -eq 0 ] && [ -z "$NEG_OUT" ]; then check "utfcpp negative (invalid-UTF-8 detection)" 0
else echo "$NEG_OUT" | head -5; check "utfcpp negative (invalid-UTF-8 detection)" 1; fi

# 3-5) hanz2piny golden known-answer tests (authored; upstream ships no tests of its own).
"$BIN" --path "$SEED" >/tmp/h2p_default.out 2>/dev/null
cmp -s /tmp/h2p_default.out "$GOLD/default.out"; check "hanz2piny golden: default" $?

"$BIN" --tone --path "$SEED" >/tmp/h2p_tone.out 2>/dev/null
cmp -s /tmp/h2p_tone.out "$GOLD/tone.out"; check "hanz2piny golden: --tone" $?

"$BIN" --camel --polyphone all --path "$SEED" >/tmp/h2p_camel_poly.out 2>/dev/null
cmp -s /tmp/h2p_camel_poly.out "$GOLD/camel_polyphone_all.out"; check "hanz2piny golden: --camel --polyphone all" $?

echo "test.sh: passed=$passed failed=$failed"
emit_ctrf hanz2piny "$passed" "$failed"
