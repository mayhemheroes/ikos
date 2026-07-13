#!/usr/bin/env bash
# clang-14 wrapper for the ikos test suite (CLANG_EXECUTABLE): compile C++ test files against
# libc++ — Debian trixie's libstdc++ headers emit DIDerivedType debug info that ikos's LLVM-14
# frontend rejects ("matches several llvm DIDerivedType"); libc++ (what ikos's macOS CI uses) is fine.
for a in "$@"; do
  case "$a" in
    *.cpp|-std=c++*) exec /usr/lib/llvm-14/bin/clang -stdlib=libc++ "$@" ;;
  esac
done
exec /usr/lib/llvm-14/bin/clang "$@"
