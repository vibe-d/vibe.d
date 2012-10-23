@echo off
if "%1"=="" (
	echo Usage: run_example ^(example name^)
	echo.
	echo Possible examples:
	pushd examples
	for /F "usebackq" %%i in (`dir /b`) do echo %%i
	popd
) else (
	echo Running %1...
	pushd examples\%1
	vibe
	popd
)