@echo off
set LIBDIR=%~dp0..\lib\win-i386
set BINDIR=%~dp0..\lib\bin
set LIBS=ws2_32.lib %LIBDIR%\event2.lib %LIBDIR%\eay.lib %LIBDIR%\ssl.lib
set DFLAGS=-debug -g -w -property
set EXEDIR=%TEMP%\.rdmd\source
if NOT EXIST %EXEDIR% (
	mkdir %EXEDIR%
)
copy %~dp0*.dll %EXEDIR% > nul 2>&1

rem Update the application using VPM.
rdmd %DFLAGS% -of%EXEDIR%\vpm.exe -I%~dp0..\source %LIBS% %~dp0.\vpm.d

rem Run the application.
if EXIST deps.txt. (
	rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d %1 %2 %3 %4 %5 %6
) else (
	rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource %LIBS% source\app.d %1 %2 %3 %4 %5 %6
)