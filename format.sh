#!/bin/bash

cd src/
find -name "*.h" | xargs clang-format -i
find -name "*.cpp" | xargs clang-format -i

cd perfect
find -name "*.h" | xargs clang-format -i
find -name "*.cpp" | xargs clang-format -i

cd ..

cd ../include
find -name "*.h" | xargs clang-format -i
find -name "*.template" | xargs clang-format -i

cd ../src/ui/flutter_app/lib
find -name "*.dart" |  xargs dart format --fix

cd ../test
find -name "*.dart" |  xargs dart format --fix

cd ../../../../

git add .
git commit -m "Format"