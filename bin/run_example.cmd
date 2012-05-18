@echo off
if "%1"=="" (
	echo Usage: run_example ^(example name^)
	echo.
	echo Possible examples:
	pushd ..\source\examples
	for /F "usebackq delims=." %%i in (`dir /b`) do echo %%i
	popd
) else (
	echo Running %1...
	SET DFLAGS=-debug -g -property -w
	SET LIBS=ws2_32.lib ..\lib\win-i386\event2.lib ..\lib\win-i386\ssl.lib ..\lib\win-i386\eay.lib
	echo %2 %3 %DFLAGS% -Jviews -I..\source %LIBS% ..\source\examples\%1.d
	rdmd %2 %3 %DFLAGS% -Jviews -I..\source %LIBS% ..\source\examples\%1.d
)