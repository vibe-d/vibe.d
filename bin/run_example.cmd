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
	SET LIBDIR="..\lib\win-i386"
	SET DFLAGS=-debug -g -gs -property -w
	SET LIBS=ws2_32.lib %LIBDIR%\event2.lib %LIBDIR%\ssl.lib %LIBDIR%\eay.lib
	echo %2 %3 %DFLAGS% -Jviews -I..\source %LIBS% ..\source\examples\%1.d
	rdmd %2 %3 %DFLAGS% -Jviews -I..\source %LIBS% ..\source\examples\%1.d
)