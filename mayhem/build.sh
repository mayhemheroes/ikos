#!/usr/bin/env bash
#
# mayhem/build.sh — build ikos (NASA static analyzer for C/C++).
#
# Two builds:
#   1) build/       — ikos-analyzer + ikos-pp with $SANITIZER_FLAGS + $DEBUG_FLAGS (the fuzz target)
#   2) build-tests/ — normal-flags build of the full upstream test suite (ctest via the
#                     build-core-tests / build-frontend-llvm-tests / build-analyzer-tests targets),
#                     run later by mayhem/test.sh
#
# ikos requires LLVM 14 exactly; the Dockerfile installs llvm-14/clang-14 from Debian bookworm.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
# ikos supports LLVM/clang 14 only; clang-19 (the base default) rejects wpo.hpp's
# `this->_successor_lifted` typo during eager template checking, so build with clang-14.
CC=/usr/bin/clang-14 ; CXX=/usr/bin/clang++-14
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

LLVM_CONFIG=/usr/lib/llvm-14/bin/llvm-config

# 1) Sanitized fuzz build: ikos-analyzer (the Mayhem target) instrumented with ASan+UBSan + DWARF-3,
# plus SanitizerCoverage (-fsanitize=fuzzer-no-link) so Mayhem gets compile-time edge feedback
# (binary-only qemu tracing yields no edges on an ASan-instrumented binary).
# __asan_default_options (detect_leaks=0) is linked into the sanitized binaries: allocate-and-exit
# batch tool, exit-time leak reports would drown real defects (Mayhem owns ASAN_OPTIONS at run time).
"$CC" -c "$SRC/mayhem/asan_default_options.c" -o /tmp/asan_default_options.o

# detect_leaks=0 during CONFIGURE only: cmake's FindGMP try_run probe leaks by design and
# LeakSanitizer would fail the probe (GMP's default allocator never frees in the test program).
ASAN_OPTIONS=detect_leaks=0 \
cmake -B "$SRC/build" -S "$SRC" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
      -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
      -DCMAKE_EXE_LINKER_FLAGS="/tmp/asan_default_options.o" \
      -DLLVM_CONFIG_EXECUTABLE="$LLVM_CONFIG"
cmake --build "$SRC/build" -j"$MAYHEM_JOBS" --target ikos-analyzer ikos-pp

# 2) Test-suite build with the project's NORMAL flags (independent tree); builds every upstream
#    unit test + regression-test dependency so test.sh only has to RUN ctest.
cmake -B "$SRC/build-tests" -S "$SRC" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
      -DCMAKE_CXX_FLAGS="-include array $COVERAGE_FLAGS" \
      -DCLANG_EXECUTABLE="$SRC/mayhem/clang-wrapper.sh" \
      -DLLVM_CONFIG_EXECUTABLE="$LLVM_CONFIG"
# (-include array: some core/test unit files miss <array> with trixie's libstdc++ headers)
cmake --build "$SRC/build-tests" -j"$MAYHEM_JOBS" \
      --target build-core-tests build-frontend-llvm-tests build-analyzer-tests
