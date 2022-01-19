#!/bin/bash

cd src/
find -name "*.h" | xargs clang-format -i
find -name "*.cpp" | xargs clang-format -i

cd ../include
find -name "*.h" | xargs clang-format -i
find -name "*.template" | xargs clang-format -i

