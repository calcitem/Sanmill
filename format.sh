#!/bin/bash

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

# Format only project source trees. Avoid build/ and rust_builder/ artifacts,
# which inherit analysis_options.yaml but lack flutter_lints resolution.
dart format \
    src/ui/flutter_app/lib \
    src/ui/flutter_app/test \
    src/ui/flutter_app/integration_test \
    src/ui/flutter_app/test_driver \
    scripts/find_keys

if [ "$1" != "s" ]; then
    git add .
    git commit -m "Format"
fi

