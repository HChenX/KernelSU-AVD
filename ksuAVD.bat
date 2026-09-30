@echo off
setlocal EnableDelayedExpansion

REM ==============================================================================
REM KernelSU-AVD: Root Android Virtual Devices (AVD) using KernelSU
REM Repository: https://github.com/HChenX/KernelSU-AVD
REM Inspired by rootAVD (newbit) and powered by KernelSU (tiann / weishu)
REM ==============================================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "APPS_DIR=%SCRIPT_DIR%\Apps"
set "ADB_REMOTE_TMP=/data/local/tmp/ksuAVD"

REM Locate Android SDK & ADB
call :FindSDK
call :FindADB

REM Parse arguments
set "ARG1=%~1"
set "ARG2=%~2"
set "ARG3=%~3"
set "DEBUG_MODE=0"
set "DO_RESTORE=0"

if /i "%ARG1%"=="InstallApps" (
    call :RunInstallApps
    exit /b %ERRORLEVEL%
)

if /i "%ARG1%"=="restore" (
    set "DO_RESTORE=1"
    set "TARGET_RAMDISK=%~2"
) else (
    set "TARGET_RAMDISK=%~1"
)

if /i "%ARG2%"=="restore" set "DO_RESTORE=1"
if /i "%ARG2%"=="DEBUG" set "DEBUG_MODE=1"
if /i "%ARG3%"=="DEBUG" set "DEBUG_MODE=1"

REM If no target specified or help requested
if "%TARGET_RAMDISK%"=="" goto :HelpExit

if /i "%ARG1%"=="-h" goto :HelpExit
if /i "%ARG1%"=="--help" goto :HelpExit
if /i "%ARG1%"=="/?" goto :HelpExit
if /i "%ARG1%"=="help" goto :HelpExit
goto :StartOperation

:HelpExit
call :ShowBanner
call :ShowDeviceStatus
call :ShowHelpAndFoundImages
exit /b 0

:StartOperation
call :ShowBanner

REM Check if target ramdisk exists
if not exist "%TARGET_RAMDISK%" (
    if defined SDK_DIR if exist "%SDK_DIR%\%TARGET_RAMDISK%" (
        set "TARGET_RAMDISK=%SDK_DIR%\%TARGET_RAMDISK%"
    ) else (
        echo [x] Error: Target ramdisk file not found:
        echo     "%ARG1%"
        echo.
        call :ShowHelpAndFoundImages
        exit /b 1
    )
)

REM Handle restore operation
if "%DO_RESTORE%"=="1" (
    call :RestoreBackup "%TARGET_RAMDISK%"
    exit /b %ERRORLEVEL%
)

REM Verify ADB connection
call :CheckDeviceConnection
if %ERRORLEVEL% neq 0 exit /b 1

REM Ensure KernelSU APK exists
call :EnsureKernelSUApk
if %ERRORLEVEL% neq 0 exit /b 1

echo [*] Target ramdisk:
echo     "%TARGET_RAMDISK%"
echo.

REM Create remote working directory
echo [*] Initializing workspace on AVD: %ADB_REMOTE_TMP%
"%ADB_BIN%" shell "rm -rf %ADB_REMOTE_TMP% && mkdir -p %ADB_REMOTE_TMP%" >nul 2>&1

REM Push required files
echo [*] Pushing KernelSU APK to AVD...
"%ADB_BIN%" push "%KSU_APK_PATH%" "%ADB_REMOTE_TMP%/KernelSU.apk"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to push KernelSU APK to device.
    exit /b 1
)

echo [*] Pushing ksuAVD.sh script to AVD...
"%ADB_BIN%" push "%SCRIPT_DIR%\ksuAVD.sh" "%ADB_REMOTE_TMP%/ksuAVD.sh" >nul 2>&1
"%ADB_BIN%" shell "chmod 755 %ADB_REMOTE_TMP%/ksuAVD.sh"

echo [*] Pushing ramdisk.img to AVD (this may take a few seconds)...
"%ADB_BIN%" push "%TARGET_RAMDISK%" "%ADB_REMOTE_TMP%/ramdisk.img"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to push ramdisk.img to device.
    exit /b 1
)

REM Execute patching script on device
echo.
echo ==============================================================================
echo [*] Running KernelSU patch process inside AVD...
echo ==============================================================================
"%ADB_BIN%" shell "sh %ADB_REMOTE_TMP%/ksuAVD.sh --device"
set "PATCH_EXIT=%ERRORLEVEL%"
echo ==============================================================================
echo.

if %PATCH_EXIT% neq 0 (
    echo [x] Patching failed inside AVD with exit code %PATCH_EXIT%!
    if "%DEBUG_MODE%"=="0" (
        "%ADB_BIN%" shell "rm -rf %ADB_REMOTE_TMP%" >nul 2>&1
    )
    exit /b %PATCH_EXIT%
)

REM Backup original ramdisk if not already backed up
set "BACKUP_FILE=%TARGET_RAMDISK%.backup"
if not exist "%BACKUP_FILE%" (
    echo [*] Creating backup of original ramdisk:
    echo     "%BACKUP_FILE%"
    copy /y "%TARGET_RAMDISK%" "%BACKUP_FILE%" >nul
) else (
    echo [*] Existing backup preserved:
    echo     "%BACKUP_FILE%"
)

REM Pull patched ramdisk back
echo [*] Pulling patched ramdisk from AVD...
"%ADB_BIN%" pull "%ADB_REMOTE_TMP%/ramdiskpatched4AVD.img" "%TARGET_RAMDISK%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to pull patched ramdisk!
    exit /b 1
)

REM Install KernelSU Manager APK
echo [*] Installing KernelSU Manager app on AVD...
"%ADB_BIN%" install -r "%KSU_APK_PATH%"

REM Cleanup remote workspace
if "%DEBUG_MODE%"=="0" (
    echo [*] Cleaning up temporary files on AVD...
    "%ADB_BIN%" shell "rm -rf %ADB_REMOTE_TMP%" >nul 2>&1
) else (
    echo [!] DEBUG mode: Temporary files kept at %ADB_REMOTE_TMP%
)

echo.
echo ==============================================================================
echo [V] SUCCESS! KernelSU has been successfully integrated into your AVD ramdisk!
echo ==============================================================================
echo.
echo Next Steps:
echo   1. Fully STOP the running emulator.
echo   2. Start it again using "Cold Boot Now" in Android Studio Device Manager
echo      (or launch via CLI with: emulator -avd ^<avd_name^> -no-snapshot-load).
echo   3. Open the KernelSU app inside the emulator. You should see "Working"!
echo   4. Go to the "Superuser" tab to grant root permissions to Apps or Shell.
echo.
exit /b 0

REM ==============================================================================
REM Subroutines
REM ==============================================================================

:ShowBanner
echo ==============================================================================
echo                     KernelSU-AVD: Root AVD with KernelSU
echo              GitHub: https://github.com/HChenX/KernelSU-AVD
echo ==============================================================================
echo.
exit /b 0

:FindSDK
set "SDK_DIR="
if defined ANDROID_HOME if exist "%ANDROID_HOME%" set "SDK_DIR=%ANDROID_HOME%"
if not defined SDK_DIR if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%" set "SDK_DIR=%ANDROID_SDK_ROOT%"
if not defined SDK_DIR if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_DIR=%LOCALAPPDATA%\Android\Sdk"
if defined SDK_DIR (
    for %%a in ("!SDK_DIR!") do set "SDK_DIR=%%~fa"
)
exit /b 0

:FindADB
set "ADB_BIN=adb"
where adb >nul 2>&1
if %ERRORLEVEL% equ 0 exit /b 0

if defined SDK_DIR (
    if exist "%SDK_DIR%\platform-tools\adb.exe" (
        set "ADB_BIN=%SDK_DIR%\platform-tools\adb.exe"
        exit /b 0
    )
)
echo [!] Warning: adb command not found in PATH or Android SDK platform-tools.
exit /b 1

:CheckDeviceConnection
"%ADB_BIN%" get-state >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [x] Error: No running Android emulator / device detected by ADB!
    echo     Please make sure your AVD is launched and fully booted before running this script.
    echo.
    "%ADB_BIN%" devices
    exit /b 1
)
exit /b 0

:ShowDeviceStatus
echo --- ADB Connected Device Status ---
%ADB_BIN% get-state >nul 2>&1
set "ADB_STATE_EXIT=%ERRORLEVEL%"
if not "%ADB_STATE_EXIT%"=="0" (
    echo   Device: None connected - Start your AVD first
    echo.
    exit /b 0
)

set "DEV_MODEL=Unknown"
set "DEV_ANDROID=Unknown"
set "DEV_SDK=Unknown"
set "DEV_ABI=Unknown"
set "DEV_KERNEL=Unknown"

for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.product.model') do set "DEV_MODEL=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.build.version.release') do set "DEV_ANDROID=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.build.version.sdk') do set "DEV_SDK=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.product.cpu.abi') do set "DEV_ABI=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell uname -r') do set "DEV_KERNEL=%%i"

echo   Model:           !DEV_MODEL!
echo   Android Version: !DEV_ANDROID! (API !DEV_SDK!)
echo   Architecture:    !DEV_ABI!
echo   Kernel:          !DEV_KERNEL!
echo.
exit /b 0

:EnsureKernelSUApk
set "KSU_APK_PATH="
if exist "%APPS_DIR%\KernelSU.apk" (
    set "KSU_APK_PATH=%APPS_DIR%\KernelSU.apk"
    exit /b 0
)
if exist "%SCRIPT_DIR%\KernelSU.apk" (
    set "KSU_APK_PATH=%SCRIPT_DIR%\KernelSU.apk"
    exit /b 0
)

echo [!] KernelSU.apk was not found in Apps\ or script root directory.
echo [*] Attempting to download the latest KernelSU release APK from GitHub...
if not exist "%APPS_DIR%" mkdir "%APPS_DIR%"

powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "$repo = 'tiann/KernelSU'; " ^
    "try { " ^
    "  $release = Invoke-RestMethod -Uri \"https://api.github.com/repos/$repo/releases/latest\"; " ^
    "  $asset = $release.assets | Where-Object { $_.name -like '*.apk' -and $_.name -notlike '*debug*' } | Select-Object -First 1; " ^
    "  if (-not $asset) { $asset = $release.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1; } " ^
    "  Write-Host \"Downloading $($asset.name)...\"; " ^
    "  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile '%APPS_DIR%\KernelSU.apk'; " ^
    "  exit 0; " ^
    "} catch { " ^
    "  Write-Host \"Download failed: $_\" -ForegroundColor Red; " ^
    "  exit 1; " ^
    "}"

if exist "%APPS_DIR%\KernelSU.apk" (
    set "KSU_APK_PATH=%APPS_DIR%\KernelSU.apk"
    echo [V] Downloaded successfully to "%KSU_APK_PATH%".
    exit /b 0
)

echo [x] Error: Could not download KernelSU.apk automatically.
echo     Please manually download KernelSU APK from https://github.com/tiann/KernelSU/releases
echo     and place it at: "%APPS_DIR%\KernelSU.apk"
exit /b 1

:RestoreBackup
set "RESTORE_TARGET=%~1"
set "BACKUP_SRC=%RESTORE_TARGET%.backup"
if not exist "%BACKUP_SRC%" (
    echo [x] Error: Backup file not found:
    echo     "%BACKUP_SRC%"
    exit /b 1
)
echo [*] Restoring backup:
echo     From: "%BACKUP_SRC%"
echo     To:   "%RESTORE_TARGET%"
copy /y "%BACKUP_SRC%" "%RESTORE_TARGET%" >nul
if %ERRORLEVEL% equ 0 (
    echo [V] Restore completed successfully!
) else (
    echo [x] Restore failed!
)
exit /b %ERRORLEVEL%

:RunInstallApps
call :ShowBanner
call :CheckDeviceConnection
if %ERRORLEVEL% neq 0 exit /b 1

echo [*] Installing all APK files from: %APPS_DIR%
set "FOUND_ANY=0"
for %%f in ("%APPS_DIR%\*.apk") do (
    set "FOUND_ANY=1"
    echo [*] Installing "%%~nxf"...
    "%ADB_BIN%" install -r "%%f"
)
if "%FOUND_ANY%"=="0" (
    echo [!] No .apk files found in %APPS_DIR%
) else (
    echo [V] Finished installing apps.
)
exit /b 0

:ShowHelpAndFoundImages
echo Usage:
echo   ksuAVD.bat ^<path_to_ramdisk.img^> [OPTIONS]
echo   ksuAVD.bat restore ^<path_to_ramdisk.img^>
echo   ksuAVD.bat InstallApps
echo.
echo Options:
echo   restore      Restore original ramdisk from ramdisk.img.backup
echo   DEBUG        Keep temporary working files on AVD (/data/local/tmp/ksuAVD)
echo.
echo --- Available System Images / AVDs Detected on This Machine ---
set "FOUND_COUNT=0"

REM Search system-images
if defined SDK_DIR (
    if exist "%SDK_DIR%\system-images" (
        for /f "delims=" %%f in ('dir "%SDK_DIR%\system-images\ramdisk*.img" /s /b /a-d 2^>nul') do (
            set /a FOUND_COUNT+=1
            call :PrintDetectedPath "%%f"
        )
    )
)

REM Search AVD instances in .android/avd or ANDROID_AVD_HOME or ANDROID_SDK_HOME
set "AVD_SEARCH_DIR=%USERPROFILE%\.android\avd"
if defined ANDROID_AVD_HOME if exist "%ANDROID_AVD_HOME%" set "AVD_SEARCH_DIR=%ANDROID_AVD_HOME%"
if defined ANDROID_SDK_HOME (
    for %%a in ("%ANDROID_SDK_HOME%") do (
        if exist "%%~fa\.android\avd" set "AVD_SEARCH_DIR=%%~fa\.android\avd"
    )
)

if exist "%AVD_SEARCH_DIR%" (
    for /f "delims=" %%f in ('dir "%AVD_SEARCH_DIR%\ramdisk*.img" /s /b /a-d 2^>nul') do (
        set /a FOUND_COUNT+=1
        call :PrintDetectedPath "%%f"
    )
)

if "%FOUND_COUNT%"=="0" (
    echo   No ramdisk.img was automatically found under standard SDK/AVD paths.
    echo   You can pass the path directly, for example:
    echo     ksuAVD.bat "D:\RuanJian\AVD\Pixel_10_Pro.avd\ramdisk.img"
    echo.
)
exit /b 0

:PrintDetectedPath
set "ITEM_PATH=%~1"
set "REL_ITEM_PATH=!ITEM_PATH!"
if defined SDK_DIR (
    set "TMP_SDK=!SDK_DIR!\"
    for /f "delims=" %%k in ("!TMP_SDK!") do set "REL_ITEM_PATH=!REL_ITEM_PATH:%%k=!"
)
echo   [%FOUND_COUNT%] ksuAVD.bat "!REL_ITEM_PATH!"
echo.
exit /b 0
