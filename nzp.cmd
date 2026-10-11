@echo off
setlocal EnableDelayedExpansion

set "TOOLBOX_ROOT=%~dp0"
for %%I in ("%TOOLBOX_ROOT%.") do set "TOOLBOX_ROOT=%%~fI"
if /I "%~1"=="update" goto update
if /I "%~1"=="build-image" goto build_image

if defined TOOLBOX_IMAGE (
    set "IMAGE_NAME=%TOOLBOX_IMAGE%"
) else (
    for /f %%G in ('git -C "%TOOLBOX_ROOT%" rev-parse HEAD') do set "COMMIT=%%G"
    if not defined COMMIT (
        echo [ERROR] Could not read the Toolbox Git commit. 1>&2
        exit /b 1
    )
    for /f %%G in ('powershell -NoProfile -Command "$r=git -C $env:TOOLBOX_ROOT remote get-url origin; if($r -match '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+)/toolbox(?:\.git)?$'){ $matches[1].ToLowerInvariant() }"') do set "IMAGE_OWNER=%%G"
    if not defined IMAGE_OWNER (
        echo [ERROR] Could not resolve a GitHub Toolbox image from origin. 1>&2
        echo Set TOOLBOX_IMAGE to an image reference. 1>&2
        exit /b 1
    )
    set "IMAGE_NAME=ghcr.io/!IMAGE_OWNER!/toolbox:sha-!COMMIT!"
)

set "IMAGE_ARCH="
for /f %%G in ('docker image inspect --format "{{.Architecture}}" "%IMAGE_NAME%" 2^>nul') do set "IMAGE_ARCH=%%G"
if not "%IMAGE_ARCH%"=="amd64" (
    echo [INFO] Downloading %IMAGE_NAME%...
    docker pull --platform=linux/amd64 "%IMAGE_NAME%"
    if errorlevel 1 (
        echo [ERROR] Could not download %IMAGE_NAME%. 1>&2
        echo If this commit is not published yet, wait for image CI or run nzp.cmd build-image and set TOOLBOX_IMAGE=nzp-toolbox:local. 1>&2
        exit /b 1
    )
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
    docker run --platform=linux/amd64 --rm --shm-size=512m -i ^
        -v "%TOOLBOX_ROOT%/config:/workspace/config" ^
        -v "%TOOLBOX_ROOT%/repos:/workspace/repos" ^
        -v "%TOOLBOX_ROOT%/python_envs:/workspace/python_envs" ^
        -v "%TOOLBOX_ROOT%/game:/workspace/game" ^
        -e TOOLBOX_HOST_OS="Windows" ^
        -e TOOLBOX_HOST_ARCH="x86_64" ^
        -e TOOLBOX_ROOT=%TOOLBOX_ROOT% ^
        "%IMAGE_NAME%" fetch
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
    "%IMAGE_NAME%" %*

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
echo [INFO] Toolbox updated. The matching image will be downloaded on the next command.
exit /b 0

:build_image
if not "%~2"=="" (
    echo Usage: nzp.cmd build-image 1>&2
    exit /b 2
)
docker build --platform=linux/amd64 -t nzp-toolbox:local "%TOOLBOX_ROOT%"
if errorlevel 1 exit /b 1
echo [INFO] Local image built. Run with TOOLBOX_IMAGE=nzp-toolbox:local to use it.
exit /b 0
