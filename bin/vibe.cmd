@echo off
set LIBDIR=%~dp0..\lib\win-i386
set BINDIR=%~dp0..\lib\bin
set LIBS=%LIBDIR%\event2.lib %LIBDIR%\eay.lib %LIBDIR%\ssl.lib ws2_32.lib
set EXEDIR=%TEMP%\.rdmd\source
set START_SCRIPT=%EXEDIR%\vibe.cmd

if NOT EXIST %EXEDIR% (
	mkdir %EXEDIR%
)
copy %~dp0*.dll %EXEDIR% > nul 2>&1
copy %~dp0*.dll . > nul 2>&1
copy %~dp0.\vpm.d %EXEDIR% > nul 2>&1

rem Run, execute, do everything.. but when you do it, do it with the vibe!
rdmd -debug -g -w -property -of%EXEDIR%\vpm.exe -I%~dp0..\source %LIBS% %EXEDIR%.\vpm.d %~dp0 %START_SCRIPT% %1 %2 %3 %4 %5 %6 %7 %8 %9

rem Finally, start the app, if vpm succeded.
if ERRORLEVEL 0 %START_SCRIPT%
