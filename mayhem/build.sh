#!/usr/bin/env bash
#
# mayhem/build.sh — build TDLib's fuzz harnesses (sanitized) and its functional test runner (normal flags).
# Runs inside the commit image as `mayhem` in /mayhem; re-runnable and offline (everything it needs is in
# the image: clang, cmake, ninja, gperf, OpenSSL and zlib headers).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) keeps an explicit EMPTY SANITIZER_FLAGS (the no-sanitizer build) intact.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
# TDLib's sanitized translation units need ~1.5 GB each; stay inside the container's memory limit.
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
cg=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
case "$cg" in max|"") ;; *) [ $((cg / 1024)) -lt "$mem_kb" ] && mem_kb=$((cg / 1024)) ;; esac
by_mem=$((mem_kb / 1500000)); [ "$by_mem" -ge 1 ] || by_mem=1
[ "$MAYHEM_JOBS" -le "$by_mem" ] || MAYHEM_JOBS=$by_mem
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) TDLib generates its TL API sources (td/generate/auto, tdutils/generate/auto) with host tools that
#    must not be sanitized (the MIME-table generator trips ASan itself). Generate them once with the
#    NORMAL native build; the same tree is the one the test runner is linked from (step 4).
cmake -S . -B build-tests -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" -DCMAKE_C_FLAGS_DEBUG=-g1 -DCMAKE_CXX_FLAGS_DEBUG=-g1
cmake --build build-tests --target prepare_cross_compiling -j"$MAYHEM_JOBS"

# 2) The project itself, sanitized + SanCov (fuzzer-no-link) + DWARF 3. Declaring the system name makes CMake
#    "cross-compile" (to the same machine), so TDLib uses the sources generated in step 1 instead of
#    building its generators with these sanitizer flags. -O1 keeps the DCHECKs live (Debug, not Release).
# -g1 (line tables, still DWARF 3) for the huge TDLib objects: full -g makes every harness binary ~800 MB.
FUZZ_PROJECT_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1 -g1"
cmake -S . -B build -G Ninja -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" \
  -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FUZZ_PROJECT_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_PROJECT_FLAGS" \
  -DCMAKE_C_FLAGS_DEBUG= -DCMAKE_CXX_FLAGS_DEBUG= -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS"
cmake --build build --target tdcore -j"$MAYHEM_JOBS"

# Include dirs / libraries of a TDLib build tree ($1), as the library targets themselves use them.
td_inc() { echo "-I$SRC -I$SRC/td/generate/auto -I$SRC/tdnet -I$SRC/tdutils -I$1/tdutils -I$SRC/tdactor -I$SRC/tddb -I$SRC/tde2e"; }
td_libs() { echo "-Wl,--start-group $(find "$1" -name '*.a' | sort | tr '\n' ' ') -Wl,--end-group -lssl -lcrypto -ldl -lz -lpthread"; }
CXXSTD="-std=c++17 -fno-exceptions -fno-rtti -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE"

# 3) Harnesses: each linked twice — libFuzzer binary + a standalone run-once reproducer — with LeakSanitizer
#    turned off at build time (lsan_off.cc). fuzz_url is TDLib's own in-tree harness (test/fuzz_url.cpp);
#    mayhem/fuzz_init.cpp only silences its LOG(ERROR) chatter.
OUT="$SRC"
OBJ="$SRC/build/mayhem_obj"; mkdir -p "$OBJ"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o $OBJ/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o $OBJ/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $CXXSTD $(td_inc build) -c mayhem/fuzz_init.cpp -o $OBJ/fuzz_init.o
STANDALONE_EXTRA=""
if [ -z "$SANITIZER_FLAGS" ]; then
  # no sanitizer runtime to provide the SanCov callbacks the instrumented project objects reference
  $CC $DEBUG_FLAGS -c mayhem/sancov_stub.c -o $OBJ/sancov_stub.o
  STANDALONE_EXTRA=$OBJ/sancov_stub.o
fi
LIBS="$(td_libs build)"
for h in "fuzz_url:test/fuzz_url.cpp" "fuzz_entities:mayhem/fuzz_entities.cpp" \
         "fuzz_format:mayhem/fuzz_format.cpp" "fuzz_link:mayhem/fuzz_link.cpp"; do
  name="${h%%:*}"; src="${h#*:}"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $CXXSTD $(td_inc build) -c "$src" -o "$OBJ/$name.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/$name.o" $OBJ/fuzz_init.o $OBJ/lsan_off.o $LIBS -o "$OUT/$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/$name.o" $OBJ/fuzz_init.o $OBJ/lsan_off.o $OBJ/standalone_main.o $STANDALONE_EXTRA $LIBS -o "$OUT/$name-standalone"
done

# 4) Functional oracle: TDLib's own unit tests for the same code (entities, links, string cleaning), built
#    with the project's NORMAL flags (no sanitizers) against the plain native tree from step 1.
cmake --build build-tests --target tdcore -j"$MAYHEM_JOBS"
TEST_OBJS=""
for t in main message_entities link string_cleaning; do
  $CXX $COVERAGE_FLAGS $CXXSTD -O1 $(td_inc build-tests) -I"$SRC/test" -c "test/$t.cpp" -o "build-tests/test_$t.o"
  TEST_OBJS="$TEST_OBJS build-tests/test_$t.o"
done
$CXX $COVERAGE_FLAGS $TEST_OBJS $(td_libs build-tests) -o build-tests/mayhem_td_tests
