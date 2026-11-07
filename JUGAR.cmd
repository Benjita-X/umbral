@echo off
rem JUGAR: construye UMBRAL con lo ultimo y lo abre en Roblox Studio. En Studio, presiona F5 para jugar.
cd /d "%~dp0"
echo Construyendo UMBRAL...
node tools\construir.mjs
if errorlevel 1 (
  echo.
  echo La construccion fallo. Revisa el mensaje de arriba.
  pause
  exit /b 1
)
echo Abriendo Roblox Studio (en Studio presiona F5 para jugar)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-ChildItem \"$env:LOCALAPPDATA\Roblox\Versions\" -Recurse -Filter RobloxStudioBeta.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if (-not $s) { Write-Host 'No se encontro Roblox Studio.'; exit 1 }; $place = (Resolve-Path 'build\UMBRAL-Desarrollo.rbxlx').Path; Start-Process -FilePath $s.FullName -ArgumentList ('\"' + $place + '\"')"
