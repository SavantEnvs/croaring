#!/usr/bin/env bash
# Builds, inside the commit image as `mayhem` in /mayhem:
#   1. libroaring.a with $SANITIZER_FLAGS + $DEBUG_FLAGS + -fsanitize=fuzzer-no-link (build/fuzz)
#   2. the rank_many differential harness (mayhem/harnesses/rank_many_fuzzer.c) as libFuzzer + -standalone binaries
#   3. the project's cmocka test suite with NORMAL flags (build/tests), run by mayhem/test.sh
# Build dirs live under `build/`, which upstream's .gitignore covers (git clean -ffdX removes them).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

# SanCov for the fuzzed code: $SANITIZER_FLAGS carries none and $LIB_FUZZING_ENGINE only covers the link.
FUZZ_COV_FLAGS="-fsanitize=fuzzer-no-link"

# CPM + cmocka are pre-seeded here by mayhem/Dockerfile so this build never needs the network.
export CPM_SOURCE_CACHE=/opt/toolchains/cpm
CMOCKA_SRC=/opt/toolchains/cpm/cmocka-src

# cmake picks the compilers up from $CC/$CXX by name (-DCMAKE_C_COMPILER=clang would make every re-run
# on an existing cache wipe it as "changed variables" and drop the -D options below).
cd "$SRC"

# 1) sanitized library (tests/benchmarks off; CPM off — nothing to fetch)
cmake -S . -B build/fuzz -G Ninja \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS" \
  -DENABLE_ROARING_TESTS=OFF -DENABLE_ROARING_BENCHMARKS=OFF -DROARING_USE_CPM=OFF
cmake --build build/fuzz -j"$MAYHEM_JOBS" --target roaring
LIB="$SRC/build/fuzz/src/libroaring.a"

# 2) harnesses: libFuzzer binary + run-once standalone reproducer; leak detection off at build time
OBJ="$SRC/build/fuzz/harness"
mkdir -p "$OBJ"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OBJ/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -I"$SRC/include" $FUZZ_COV_FLAGS -c mayhem/harnesses/rank_many_fuzzer.c -o "$OBJ/rank_many_fuzzer.o"

for t in rank_many_fuzzer; do
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/$t.o" "$OBJ/lsan_off.o" "$LIB" -o "$SRC/$t"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/standalone_main.o" "$OBJ/$t.o" "$OBJ/lsan_off.o" "$LIB" -o "$SRC/$t-standalone"
done

# 3) functional suite, normal flags (independent of the sanitized build above)
cmake -S . -B build/tests -G Ninja \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DENABLE_ROARING_BENCHMARKS=OFF -DROARING_USE_CPM=ON -DCPM_cmocka_SOURCE="$CMOCKA_SRC"
cmake --build build/tests -j"$MAYHEM_JOBS"
