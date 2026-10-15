@echo off
chcp 65001 > nul
cls
echo ========================================
echo   inlaut (Windows Prototype)
echo ========================================
echo.
if not exist "Inlaut.Cli.exe" (
    echo Fehler: Inlaut.Cli.exe wurde nicht im aktuellen Ordner gefunden.
    pause
    exit /b 1
)

if not exist "models" (
    echo Hinweis: Kein Ordner 'models' gefunden.
    echo Bitte platziere dein Modell (model.onnx oder model.int8.onnx + tokens.txt)
    echo in einen Unterordner namens 'models'.
    echo.
)

echo Starte Inlaut.Cli...
echo.
Inlaut.Cli.exe %*
echo.
pause
