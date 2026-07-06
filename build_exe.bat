@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo  360 DEGREE CALIBRATION APP - EXE BUILDER
echo ===================================================

:: 1. Check if virtual environment exists
if not exist "venv" (
    echo.
    echo ERROR: Virtual environment 'venv' not found.
    echo Please run run.bat first to initialize Python and packages.
    pause
    exit /b 1
)

:: 2. Activate virtual environment
echo.
echo Activating virtual environment...
call venv\Scripts\activate.bat
if %ERRORLEVEL% neq 0 (
    echo Failed to activate virtual environment.
    pause
    exit /b 1
)

:: 3. Install/upgrade requirements (including PyInstaller)
echo.
echo Ensuring all dependencies (including PyInstaller) are installed...
pip install -r requirements.txt
if %ERRORLEVEL% neq 0 (
    echo Failed to install dependencies.
    pause
    exit /b 1
)

:: 4. Build standalone executable
echo.
echo Starting compilation with PyInstaller...
pyinstaller --clean --noconsole --onefile --name "AIT_Lmbs" main.py
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: PyInstaller compilation failed.
    pause
    exit /b 1
)

echo.
echo ===================================================
echo  BUILD SUCCESSFUL!
echo ===================================================
echo  Your standalone executable is located at:
echo  dist\AIT_Lmbs.exe
echo ===================================================
echo.

pause
endlocal
