@echo on

@echo ImageMagick fix libpng warning: iCCP: Not recognizing known sRGB profile ...
@echo Search PNG in subdirs and convert ...

set fn=ImageMagick\convert.exe

for /f "tokens=*" %%i in ('dir/s/b *.png') do "%fn%" "%%i" -strip "%%i"

@echo Done.

pause
