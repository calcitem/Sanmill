git clean -fdx

cmake .

cmake --build . --target mill-pro
#windeployqt "Debug/mill-pro"

cmake --build . --target mill-pro --config Release
#windeployqt "Release/mill-pro"

# cmake .. -G "Xcode" -DCMAKE_PREFIX_PATH=~/Qt5.12.12/5.12.12/clang_64 -DCMAKE_OSX_ARCHITECTURES=x86_64

# cov-build  --dir cov-int cmake --build . --target mill-pro

