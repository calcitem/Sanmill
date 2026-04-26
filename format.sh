#!/bin/bash
set -euo pipefail

clang-format -i src/*.h
clang-format -i src/*.cpp

clang-format -i src/perfect/*.h
clang-format -i src/perfect/*.cpp

clang-format -i include/*.h

clang-format -i src/ui/qt/*.h
clang-format -i src/ui/qt/*.cpp

#clang-format -i tests/*.h
clang-format -i tests/*.cpp

#clang-format -i tests/perfect/*.h
#clang-format -i tests/perfect/*.cpp

dart format .

if [ -f Cargo.toml ]; then
    cargo fmt --all
    cargo clippy --workspace --all-targets --all-features -- -D warnings
fi

if [ "${1:-}" != "s" ]; then
    git add .
    git commit -m "Format"
fi
