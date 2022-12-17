git clean -fdx

cmake .

cmake --build . --target MillGame
windeployqt "Debug\MillGame.exe

cmake --build . --target MillGame --config Release
windeployqt "Release\MillGame.exe
