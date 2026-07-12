#!/usr/bin/env bash
#
# mayhem/build.sh — build the hanz2piny fuzz target, the functional oracle, and the
# upstream (vendored utfcpp) test drivers.
#
# hanz2piny is a small C++11 CLI (src/main.cpp + CmdlineOption.cpp + Hanz2Piny.cpp) that
# converts a UTF-8 file of Chinese hanzi to pinyin: `hanz2piny --path <file>`. That CLI is
# the Mayhem target (the archived original fuzzed `/hanz2piny --path @@`), so we build it
# two ways:
#   /mayhem/hanz2piny               sanitized + DWARF-3  -> the Mayhem target
#   build-oracle/hanz2piny          normal flags         -> the mayhem/test.sh oracle
# Upstream also vendors utfcpp WITH its own test drivers (src/lib/3rd/utfcpp/test_drivers)
# — hanz2piny's UTF-8 handling is built on it — so we build those too, per their Makefiles,
# and test.sh runs them.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

SRCS="src/main.cpp src/lib/helper/CmdlineOption.cpp src/lib/self/libhanz2piny/Hanz2Piny.cpp"
UTFCPP=src/lib/3rd/utfcpp

# 1) Sanitized fuzz target — the PROJECT ITSELF is instrumented (not just a harness), so
#    ASan/UBSan see bugs inside Hanz2Piny.cpp. -O1 keeps frames readable; $DEBUG_FLAGS after
#    the sanitizer flags so -gdwarf-3 wins (DWARF must be < 4 for Mayhem triage).
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++11 $SRCS -o hanz2piny

# 2) Clean oracle build (NO sanitizers, upstream's -std=c++11 release flags) so mayhem/test.sh
#    is an honest functional oracle. $COVERAGE_FLAGS is empty by default.
mkdir -p build-oracle
# shellcheck disable=SC2086
$CXX -O2 $COVERAGE_FLAGS -std=c++11 $SRCS -o build-oracle/hanz2piny

# 3) Upstream test suite: the vendored utfcpp test drivers (assert-based smoke test + the
#    negative/invalid-UTF-8 detector), built with their Makefiles' compiler and flags
#    (CC = g++ — the smoke test's replace_invalid check trips a compiler-dependent
#    pattern under clang++, so we match upstream's toolchain exactly).
# shellcheck disable=SC2086
g++ -g -Wall $COVERAGE_FLAGS "$UTFCPP/test_drivers/smoke_test/test.cpp" -o build-oracle/utfcpp_smoketest
# shellcheck disable=SC2086
g++ -g -Wall -pedantic $COVERAGE_FLAGS "$UTFCPP/test_drivers/negative/negative.cpp" -o build-oracle/utfcpp_negativetest

echo "build.sh: built /mayhem/hanz2piny (sanitized), build-oracle/{hanz2piny,utfcpp_smoketest,utfcpp_negativetest}"
