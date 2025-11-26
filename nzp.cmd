@echo off
setlocal

set TOOLBOX_ROOT=%cd%
set IMAGE_NAME=nzp-toolbox:latest

rem Auto-build Docker image if absent.
docker image inspect %IMAGE_NAME% >nul 2>&1
if errorlevel 1 (
    echo [INFO] Docker image not found. Building...
    docker build --platform=linux/amd64 -t %IMAGE_NAME% %TOOLBOX_ROOT%
    echo -----------------------------------------
)

rem Detect first-time setup and pull repos if needed
set FIRSTTIME=0
if not exist "%TOOLBOX_ROOT%\repos" set FIRSTTIME=1

for /f %%G in ('dir /b "%TOOLBOX_ROOT%\repos"') do (
    if exist "%TOOLBOX_ROOT%\repos\%%G\.git" (
        set FIRSTTIME=0
        goto skip_pull
    )
)
set FIRSTTIME=1

:skip_pull

if %FIRSTTIME%==1 (
    echo [INFO] Pulling repositories for first time use...
    docker run --platform=linux/amd64 --rm -it ^
        -v "%TOOLBOX_ROOT%/config:/workspace/config" ^
        -v "%TOOLBOX_ROOT%/repos:/workspace/repos" ^
        -v "%TOOLBOX_ROOT%/python_envs:/workspace/python_envs" ^
        %IMAGE_NAME% fetch
    echo -----------------------------------------
)

rem Run container with mounts and pass our arguments
docker run --platform=linux/amd64 --rm -it ^
    -v "%TOOLBOX_ROOT%/config:/workspace/config" ^
    -v "%TOOLBOX_ROOT%/repos:/workspace/repos" ^
    -v "%TOOLBOX_ROOT%/python_envs:/workspace/python_envs" ^
    %IMAGE_NAME% %*

endlocal