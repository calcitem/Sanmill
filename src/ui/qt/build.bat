git clean -fdx

cmake .

cmake --build . --target mill-pro
windeployqt "Debug\mill-pro.exe

cmake --build . --target mill-pro --config Release
windeployqt "Release\mill-pro.exe
