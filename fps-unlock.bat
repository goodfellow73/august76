@echo off
title Poco X3 GT - Brawl Stars FPS Unlocker
color 0A

echo ============================================
echo   Poco X3 GT - Brawl Stars 120fps Unlocker
echo ============================================
echo.

:: Check if ADB is already installed
where adb >nul 2>&1
if %errorlevel% == 0 (
    echo [OK] ADB found in PATH.
    goto :check_device
)

:: Try local platform-tools folder
if exist "%~dp0platform-tools\adb.exe" (
    echo [OK] ADB found in platform-tools folder.
    set PATH=%~dp0platform-tools;%PATH%
    goto :check_device
)

:: Download platform-tools
echo [INFO] ADB not found. Downloading Android Platform Tools...
echo        This only happens once - it's about 30MB.
echo.

where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] curl not found. Please install ADB manually:
    echo         https://developer.android.com/tools/releases/platform-tools
    echo         Extract it next to this .bat file and run again.
    pause
    exit /b 1
)

curl -L -o "%~dp0platform-tools.zip" "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
if %errorlevel% neq 0 (
    echo [ERROR] Download failed. Check your internet connection and try again.
    pause
    exit /b 1
)

echo [INFO] Extracting...
powershell -command "Expand-Archive -Path '%~dp0platform-tools.zip' -DestinationPath '%~dp0' -Force"
del "%~dp0platform-tools.zip"
set PATH=%~dp0platform-tools;%PATH%
echo [OK] ADB ready.
echo.

:check_device
echo ============================================
echo   STEP 1: Enable USB Debugging on your phone
echo ============================================
echo.
echo   On your Poco X3 GT:
echo   1. Settings ^> About Phone ^> tap "MIUI version" 7 times
echo   2. Settings ^> Additional Settings ^> Developer Options
echo   3. Turn ON "USB Debugging"
echo   4. Plug phone into PC via USB
echo   5. On phone: tap "Allow" when it asks about USB Debugging
echo.
echo   Press any key when your phone is plugged in and USB Debugging is ON...
pause >nul

echo.
echo [INFO] Looking for device...
adb start-server >nul 2>&1

adb devices | findstr /i "device" | findstr /v "List" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] No device found. Make sure:
    echo         - USB Debugging is ON
    echo         - Phone is plugged in
    echo         - You tapped "Allow" on the phone
    echo.
    echo   Try unplugging and replugging the USB cable, then press any key...
    pause >nul
    adb devices | findstr /i "device" | findstr /v "List" >nul 2>&1
    if %errorlevel% neq 0 (
        echo [ERROR] Still no device. Exiting.
        pause
        exit /b 1
    )
)

echo [OK] Device connected!
echo.

:: Show device info
for /f "tokens=*" %%i in ('adb shell getprop ro.product.model 2^>nul') do set MODEL=%%i
for /f "tokens=*" %%i in ('adb shell getprop ro.miui.ui.version.name 2^>nul') do set MIUI=%%i
echo   Device : %MODEL%
echo   MIUI   : %MIUI%
echo.

echo ============================================
echo   STEP 2: Applying 120fps settings
echo ============================================
echo.

:: Force peak refresh rate to 120Hz system-wide
echo [*] Setting peak refresh rate to 120Hz...
adb shell settings put system peak_refresh_rate 120
adb shell settings put system min_refresh_rate 60

:: MIUI specific: disable adaptive refresh rate throttling
echo [*] Disabling MIUI adaptive refresh rate limits...
adb shell settings put system user_refresh_rate_mode 2

:: Force display to stay at 120Hz
echo [*] Forcing display refresh rate...
adb shell service call SurfaceFlinger 1035 i32 0 >nul 2>&1

:: Unlock Brawl Stars from 60fps cap (per-app override)
echo [*] Applying per-app 120fps override for Brawl Stars...
adb shell settings put system game_mode_enabled_for_com.supercell.brawlstars 1 >nul 2>&1

:: Set high performance mode for Brawl Stars via Game Turbo if available
adb shell am broadcast -a com.xiaomi.gamebooster.action.FRAME_RATE_UNLOCK --es packageName com.supercell.brawlstars --ei frameRate 120 >nul 2>&1

:: Disable battery saver if it's on (it caps refresh rate)
echo [*] Checking battery saver...
for /f "tokens=*" %%i in ('adb shell settings get global low_power') do set LOWPOWER=%%i
if "%LOWPOWER%"=="1" (
    echo [!] Battery saver was ON - turning it off ^(it caps fps^)
    adb shell settings put global low_power 0
) else (
    echo [OK] Battery saver is already off.
)

:: Kill and restart Brawl Stars so changes take effect
echo.
echo [*] Restarting Brawl Stars to apply changes...
adb shell am force-stop com.supercell.brawlstars
timeout /t 2 /nobreak >nul
adb shell monkey -p com.supercell.brawlstars -c android.intent.category.LAUNCHER 1 >nul 2>&1

echo.
echo ============================================
echo   Done!
echo ============================================
echo.
echo   Brawl Stars is launching on your phone.
echo   In-game, check if it feels smoother.
echo.
echo   If still 60fps:
echo   - Your device may not be on Supercell's 120fps whitelist
echo   - The only remaining fix requires rooting your phone
echo.
pause
