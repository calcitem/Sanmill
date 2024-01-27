#!/bin/bash

clang-format -i src/*.h
clang-format -i src/*.cpp

clang-format -i src/perfect/*.h
clang-format -i src/perfect/*.cpp

clang-format -i include/*.h

clang-format -i src/ui/qt/*.h
clang-format -i src/ui/qt/*.cpp

cd src/ui/flutter_app/lib
find . -name "*.dart" |  xargs dart format --fix

cd ../test
find . -name "*.dart" |  xargs dart format --fix

cd ../../../../

git add .
git commit -m "Format"

