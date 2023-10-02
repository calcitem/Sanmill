git clean -fdx

cmake .

cmake --build . --target mill-pro
#windeployqt "Debug/mill-pro"

cmake --build . --target mill-pro --config Release
#windeployqt "Release/mill-pro"

# cov-build  --dir cov-int cmake --build . --target mill-pro
