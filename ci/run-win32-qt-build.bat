call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars32.bat" x86_amd64

set QTDIR=C:\Qt\Qt5.13.0\5.13.0\msvc2017_64
set PATH=%PATH%;%QTDIR%\bin;

qmake
nmake clean
nmake

pause
