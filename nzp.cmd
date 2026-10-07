@echo off
setlocal

set "TOOLBOX_ROOT=%~dp0"
for %%I in ("%TOOLBOX_ROOT%.") do set "TOOLBOX_ROOT=%%~fI"
set IMAGE_NAME=nzp-toolbox:latest

if /I "%~1"=="update" goto update

docker build --platform=linux/amd64 -t %IMAGE_NAME% "%TOOLBOX_ROOT%"
if errorlevel 1 exit /b 1

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
    docker run --platform=linux/amd64 --rm --shm-size=512m -i ^
        -v "%TOOLBOX_ROOT%/config:/workspace/config" ^
        -v "%TOOLBOX_ROOT%/repos:/workspace/repos" ^
        -v "%TOOLBOX_ROOT%/python_envs:/workspace/python_envs" ^
        -v "%TOOLBOX_ROOT%/game:/workspace/game" ^
        -e TOOLBOX_HOST_OS="Windows" ^
        -e TOOLBOX_HOST_ARCH="x86_64" ^
        -e TOOLBOX_ROOT=%TOOLBOX_ROOT% ^
        %IMAGE_NAME% fetch
    echo -----------------------------------------
)

rem If no args, enable TTY (-it) so Textual frontend works properly.
set DOCKER_TTY_FLAGS=-i
if "%~1"=="" set DOCKER_TTY_FLAGS=-it

rem Run container with mounts and pass our arguments
docker run --platform=linux/amd64 --rm --shm-size=512m %DOCKER_TTY_FLAGS% ^
    -v "%TOOLBOX_ROOT%/config:/workspace/config" ^
    -v "%TOOLBOX_ROOT%/repos:/workspace/repos" ^
    -v "%TOOLBOX_ROOT%/python_envs:/workspace/python_envs" ^
    -v "%TOOLBOX_ROOT%/game:/workspace/game" ^
    -e TOOLBOX_HOST_OS="Windows" ^
    -e TOOLBOX_HOST_ARCH="x86_64" ^
    -e TOOLBOX_ROOT=%TOOLBOX_ROOT% ^
    %IMAGE_NAME% %*

endlocal
exit /b %ERRORLEVEL%

:update
if not "%~2"=="" (
    echo Usage: nzp.cmd update 1>&2
    exit /b 2
)
git -C "%TOOLBOX_ROOT%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Toolbox must be installed with git to update it. See README.md. 1>&2
    exit /b 1
)
set "GIT_PREFIX="
for /f "delims=" %%G in ('git -C "%TOOLBOX_ROOT%" rev-parse --show-prefix') do set "GIT_PREFIX=%%G"
if not "%GIT_PREFIX%"=="" (
    echo [ERROR] Toolbox must be installed with git to update it. See README.md. 1>&2
    exit /b 1
)
for /f %%G in ('git -C "%TOOLBOX_ROOT%" status --porcelain --untracked-files=no') do (
    echo [ERROR] Toolbox has local changes. Commit or stash them before updating. 1>&2
    exit /b 1
)
git -C "%TOOLBOX_ROOT%" rev-parse --abbrev-ref --symbolic-full-name @{upstream} >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Current branch has no upstream. Check out a tracking branch before updating. 1>&2
    exit /b 1
)
git -C "%TOOLBOX_ROOT%" pull --ff-only
if errorlevel 1 exit /b 1
echo [INFO] Toolbox updated. The image will be rebuilt on the next command.
exit /b 0
