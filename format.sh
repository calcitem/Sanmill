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

cd src/ui/flutter_app/lib
find . -name "*.dart" |  xargs dart format

cd ../test
find . -name "*.dart" |  xargs dart format

cd ../integration_test
find . -name "*.dart" |  xargs dart format

cd ../../../../

if [ "$1" != "s" ]; then
    git add .
    git commit -m "Format"
fi

