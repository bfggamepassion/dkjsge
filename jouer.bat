@echo off
rem Lance la cartouche Master System (sms\build\dkjr.sms) dans Mesen 2
rem (%LOCALAPPDATA%\Mesen2\Mesen.exe) ; a defaut, avec le programme associe aux fichiers .sms.
cd /d "%~dp0"
set "ROM=%~dp0sms\build\dkjr.sms"
set "MESEN=%LOCALAPPDATA%\Mesen2\Mesen.exe"
if not exist "%ROM%" goto norom
if not exist "%MESEN%" goto autre
start "" "%MESEN%" "%ROM%"
exit /b 0
:autre
start "" "%ROM%"
exit /b 0
:norom
echo Cartouche absente : %ROM%
echo La construire d'abord avec compiler.bat (ou : python sms\build.py)
pause
exit /b 1
