@echo off
rem Construit la cartouche Master System : sms\build\dkjr.sms
chcp 65001 >nul
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
where python >nul 2>nul
if errorlevel 1 goto nopython
python sms\build.py
if errorlevel 1 goto echec
echo.
echo Cartouche prete : %~dp0sms\build\dkjr.sms
pause
exit /b 0
:nopython
echo Python introuvable : installer Python 3 depuis https://www.python.org/downloads/
echo (cocher « Add python.exe to PATH » pendant l'installation).
pause
exit /b 1
:echec
echo.
echo Echec de la construction.
pause
exit /b 1
