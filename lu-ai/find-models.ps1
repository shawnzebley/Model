<#
  LU AI - locate the ComfyUI models folder

  LU AI is packaged as an Electron-style app: C:\Program Files\Locally Uncensored
  holds only the UI shell, so the ComfyUI backend and its models live somewhere
  else - usually under the user profile, which is why no admin rights are needed
  to add models once the folder is found.

  Run in a NORMAL PowerShell window (elevation not required):

      powershell -ExecutionPolicy Bypass -File .\find-models.ps1

  Paste the output back and the install paths can be confirmed exactly.
#>

$ErrorActionPreference = 'SilentlyContinue'
$app = 'C:\Program Files\Locally Uncensored'

Write-Host "`n=== 1. What's inside the app folder ===" -ForegroundColor Cyan
# resources\ showing no subfolders means an .asar bundle - listing files proves it.
Get-ChildItem $app -Recurse -Depth 2 -File |
    Select-Object -First 40 @{n='Size(MB)';e={[math]::Round($_.Length/1MB,1)}}, FullName |
    Format-Table -AutoSize

Write-Host "`n=== 2. Config files that may point at the real data folder ===" -ForegroundColor Cyan
$configNames = 'extra_model_paths.yaml','config.json','settings.json','comfy.settings.json','*.ini'
foreach ($n in $configNames) {
    Get-ChildItem $app -Recurse -Depth 3 -Filter $n -File |
        Select-Object -ExpandProperty FullName
}

Write-Host "`n=== 3. Searching for a ComfyUI models folder ===" -ForegroundColor Cyan
# Anything named 'checkpoints' sitting inside a 'models' folder is the ComfyUI
# layout. Search the places a packaged app is allowed to write, plus drive roots.
$roots = @(
    $env:APPDATA,
    $env:LOCALAPPDATA,
    $env:USERPROFILE,
    $env:ProgramData,
    $app
) + ((Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }).Root)

$found = @()
foreach ($r in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
    # Depth 6 covers e.g. %APPDATA%\LocallyUncensored\ComfyUI\models\checkpoints
    # without walking the entire disk.
    Get-ChildItem -Path $r -Directory -Recurse -Depth 6 -Filter 'checkpoints' |
        Where-Object { $_.Parent.Name -eq 'models' } |
        ForEach-Object { $found += $_.Parent.Parent.FullName }
}

$found = $found | Select-Object -Unique
if ($found) {
    Write-Host "FOUND - ComfyUI root(s):" -ForegroundColor Green
    foreach ($f in $found) {
        Write-Host "  $f" -ForegroundColor Green
        Get-ChildItem (Join-Path $f 'models') -Directory |
            Select-Object -ExpandProperty Name |
            ForEach-Object { Write-Host "      models\$_" -ForegroundColor DarkGray }
    }
} else {
    Write-Host "No models\checkpoints folder found in the usual locations." -ForegroundColor Yellow
}

Write-Host "`n=== 4. Large model files anywhere obvious ===" -ForegroundColor Cyan
# Fallback: find the checkpoint itself. Juggernaut XL is roughly 6-7 GB.
foreach ($r in @($env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE, $app)) {
    Get-ChildItem -Path $r -Recurse -Depth 6 -Include *.safetensors,*.ckpt -File |
        Where-Object { $_.Length -gt 500MB } |
        Select-Object @{n='Size(GB)';e={[math]::Round($_.Length/1GB,2)}}, FullName
} | Format-Table -AutoSize

Write-Host "`nDone. Paste the output above back into the chat.`n" -ForegroundColor Cyan
