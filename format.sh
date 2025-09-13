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

# Format fastmill project files (with existence checks)
if ls tools/fastmill/*.h >/dev/null 2>&1; then
    clang-format -i tools/fastmill/*.h
fi
if ls tools/fastmill/*.cpp >/dev/null 2>&1; then
    clang-format -i tools/fastmill/*.cpp
fi
if [ -d "tools/fastmill/src" ]; then
    find tools/fastmill/src -name "*.h" -exec clang-format -i {} \; 2>/dev/null
    find tools/fastmill/src -name "*.cpp" -exec clang-format -i {} \; 2>/dev/null
fi

dart format .

if [ "$1" != "s" ]; then
    git add .
    git commit -m "Format"
fi

