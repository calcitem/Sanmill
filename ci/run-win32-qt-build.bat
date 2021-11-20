call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars32.bat" x86_amd64

set QTDIR=Qt\5.15.2\msvc2019_64
set PATH=%PATH%;%QTDIR%\bin;

qmake
nmake clean
nmake
