@echo off
set VIBE_BIN=%~dps0
set LIBDIR=%VIBE_BIN%..\lib\win-i386
set BINDIR=%VIBE_BIN%..\lib\bin
set LIBS="%LIBDIR%\event2.lib" "%LIBDIR%\eay.lib" "%LIBDIR%\ssl.lib" ws2_32.lib
set EXEDIR=%TEMP%\.rdmd\source
set START_SCRIPT=%EXEDIR%\vibe.cmd

echo Notice: This VPM build script is deprecated. It is recommended to
echo use DUB instead.
echo See https://github.com/rejectedsoftware/dub
echo.

if NOT EXIST %EXEDIR% (
	mkdir %EXEDIR%
)
copy "%LIBDIR%\*.dll" %EXEDIR% > nul 2>&1
if "%1" == "build" copy "%LIBDIR%\*.dll" . > nul 2>&1
copy "%VIBE_BIN%vpm.d" %EXEDIR% > nul 2>&1

del %START_SCRIPT% >nul 2>&1

rem Run, execute, do everything.. but when you do it, do it with the vibe!
rdmd -debug -g -w -property -version=VibeLibeventDriver -of%EXEDIR%\vpm.exe -I%VIBE_BIN%..\source -I%VIBE_BIN%..\import %LIBS% %EXEDIR%\vpm.d %VIBE_BIN% %START_SCRIPT% %*

rem Finally, start the app, if vpm succeded.
if %ERRORLEVEL% == 0 (
	if EXIST %START_SCRIPT% %START_SCRIPT%
)
