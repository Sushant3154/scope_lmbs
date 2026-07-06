@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo  360 DEGREE CALIBRATION APP AUTO-LAUNCHER
echo ===================================================

:: 1. Find python executable
set "PYTHON_EXE="
set "USER_PYTHON_PATH=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
set "SYSTEM_PYTHON_PATH=%ProgramFiles%\Python312\python.exe"

if exist "!USER_PYTHON_PATH!" (
    set "PYTHON_EXE=!USER_PYTHON_PATH!"
    echo Found Python in User AppData: !PYTHON_EXE!
) else if exist "!SYSTEM_PYTHON_PATH!" (
    set "PYTHON_EXE=!SYSTEM_PYTHON_PATH!"
    echo Found Python in Program Files: !PYTHON_EXE!
) else (
    :: Search other python versions
    for /d %%d in ("%LOCALAPPDATA%\Programs\Python\Python*") do (
        if exist "%%d\python.exe" (
            set "PYTHON_EXE=%%d\python.exe"
            echo Found alternative Python: !PYTHON_EXE!
            goto :found_python
        )
    )
    for /d %%d in ("%ProgramFiles%\Python\Python*") do (
        if exist "%%d\python.exe" (
            set "PYTHON_EXE=%%d\python.exe"
            echo Found alternative Python: !PYTHON_EXE!
            goto :found_python
        )
    )
    
    :: Fallback to PATH
    where python >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        set "PYTHON_EXE=python"
        echo Using python from system PATH.
    ) else (
        echo.
        echo ERROR: Python executable could not be located.
        echo Please ensure Python 3.11 or 3.12 is installed.
        pause
        exit /b 1
    )
)

:found_python
echo Using Python path: %PYTHON_EXE%

:: 2. Create Virtual Environment
if not exist "venv" (
    echo.
    echo Creating virtual environment 'venv'...
    "%PYTHON_EXE%" -m venv venv
    if %ERRORLEVEL% neq 0 (
        echo Failed to create virtual environment.
        pause
        exit /b 1
    )
)

:: 3. Install Requirements
echo.
echo Upgrading pip and installing requirements...
venv\Scripts\python.exe -m pip install --upgrade pip
venv\Scripts\python.exe -m pip install -r requirements.txt
if %ERRORLEVEL% neq 0 (
    echo Failed to install package requirements.
    pause
    exit /b 1
)

:: 4. Start Main Application
echo.
echo Launching 360 Calibration Application...
venv\Scripts\python.exe main.py
if %ERRORLEVEL% neq 0 (
    echo Application exited with code %ERRORLEVEL%.
    pause
)

endlocal
