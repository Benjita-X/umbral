# Ejecuta las pruebas automáticas de UMBRAL en Roblox Studio y muestra los resultados.
# Uso (desde la carpeta umbral):  powershell -ExecutionPolicy Bypass -File tools/ejecutar-pruebas.ps1
# 1. Reconstruye los lugares e instala el plugin de pruebas.
# 2. Abre build/UMBRAL-Pruebas.rbxlx en una ventana nueva de Studio (el plugin inicia Play solo).
# 3. Lee lo que el plugin guardó con plugin:SetSetting (Studio no escribe los print en sus registros).
# 4. Cierra SOLO la ventana de pruebas que abrió este script; las demás ventanas de Studio no se tocan.

# Opciones: -Retraso 0.1 simula 100 ms de latencia por sentido; -Suites "Eco,Ecos" corre solo esas suites.
param([int]$TimeoutSeconds = 960, [double]$Retraso = 0, [string]$Suites = '')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Identificador de esta ejecución: el plugin lo copia en sus registros y solo se aceptan los que coinciden
$runId = [guid]::NewGuid().ToString('N').Substring(0, 8)
$extra = @()
if ($Retraso -gt 0) { $extra += "--retraso=$($Retraso.ToString([System.Globalization.CultureInfo]::InvariantCulture))" }
if ($Suites) { $extra += "--suites=$Suites" }
node tools/construir.mjs --pruebas --instalar-plugin "--run-id=$runId" @extra | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'La construcción falló (ver el error de arriba): no se abre Studio.' }

$studio = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Recurse -Filter RobloxStudioBeta.exe |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $studio) { throw 'No se encontró Roblox Studio.' }

# Ajustes de plugins locales de la cuenta de Studio (carpeta con el id de usuario, no la "0")
$settingsFile = Get-ChildItem "$env:LOCALAPPDATA\Roblox" -Directory |
    Where-Object { $_.Name -match '^\d+$' -and $_.Name -ne '0' } |
    ForEach-Object { Join-Path $_.FullName 'InstalledPlugins\0\settings.json' } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $settingsFile) { throw 'No se encontró settings.json de los plugins locales.' }

function Read-Results {
    try {
        $json = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { return $null }
    $out = [ordered]@{}
    foreach ($ctx in 'edicion', 'servidor', 'cliente') {
        $value = $json."UmbralPruebas_$ctx"
        # Datos de otra ejecución (o de una versión vieja del plugin): se ignoran
        $out[$ctx] = @(if ($value -and $value.run -eq $runId -and $value.lines) { $value.lines } else { @() })
    }
    return $out
}

$placePath = Join-Path $root 'build\UMBRAL-Pruebas.rbxlx'
# Con otra ventana de Studio abierta, la nueva instancia puede entregarle el archivo y no abrir el lugar de
# pruebas (pasó el 2026-11-06: Studio quedó en la pantalla de inicio y no hubo resultados).
if (Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue) {
    Write-Host 'AVISO: ya hay una ventana de Roblox Studio abierta. Si no aparecen resultados, ciérrala y vuelve a ejecutar.'
}
$before = @(Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
Start-Process -FilePath $studio.FullName -ArgumentList "`"$placePath`""
Write-Host "Studio abierto con el lugar de pruebas. Esperando resultados (máx. $TimeoutSeconds s)..."

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$finished = $false
$sawPlugin = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $r = Read-Results
    if ($null -eq $r) { continue }
    $editLines = $r['edicion'] -join "`n"
    if ($editLines -match 'plugin activo') { $sawPlugin = $true }
    if ($editLines -match 'sesión terminada|no se pudo|no está disponible') { $finished = $true; break }
}

# Cerrar solo la ventana de pruebas abierta por este script (cerrarla también vuelca los ajustes a disco)
$opened = Get-Process -Name RobloxStudioBeta -ErrorAction SilentlyContinue |
    Where-Object { $before -notcontains $_.Id }
foreach ($p in $opened) {
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(10000)) { Stop-Process -Id $p.Id -Force }
    Write-Host "Ventana de pruebas cerrada (proceso $($p.Id))."
}
Start-Sleep -Seconds 1

$r = Read-Results
Write-Host ''
Write-Host '================ RESULTADOS ================'
foreach ($ctx in 'edicion', 'servidor', 'cliente') {
    Write-Host "--- $ctx"
    foreach ($line in $r[$ctx]) { Write-Host $line }
}
if (-not $sawPlugin -and -not $finished) { Write-Host 'AVISO: el plugin no dejó registros mientras Studio estaba abierto.' }
if (-not $finished) { Write-Host "AVISO: la sesión no terminó en $TimeoutSeconds s." }
