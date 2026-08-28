<#
  LU AI - Photorealism Pack installer for Juggernaut XL v9 (Windows / PowerShell)

  Downloads the VAE and upscalers into a Stable Diffusion WebUI install.
  Run from your WebUI root, or pass -WebUIRoot.

      cd C:\path\to\stable-diffusion-webui
      powershell -ExecutionPolicy Bypass -File .\install-quality-pack.ps1

  The two detail LoRAs are Civitai-hosted and need a logged-in download;
  the script prints instructions for those at the end.
#>

param(
    [string]$WebUIRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# Each entry: destination subfolder, filename, and one or more source URLs
# tried in order. If every URL fails, the file is reported as MISSING and
# nothing partial is left behind.
$Downloads = @(
    @{
        Dir  = 'models\VAE'
        Name = 'sdxl_vae.safetensors'
        Urls = @(
            'https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors?download=true',
            'https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl.vae.safetensors?download=true'
        )
        MinBytes = 100MB
    },
    @{
        Dir  = 'models\ESRGAN'
        Name = '4x-UltraSharp.pth'
        Urls = @(
            'https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth?download=true',
            'https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth?download=true'
        )
        MinBytes = 30MB
    },
    @{
        Dir  = 'models\ESRGAN'
        Name = '4x_NMKD-Siax_200k.pth'
        Urls = @(
            'https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth?download=true',
            'https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth?download=true'
        )
        MinBytes = 30MB
    }
)

function Test-IsWebUIRoot {
    param([string]$Root)
    # A real WebUI install has a models directory and a launcher.
    return (Test-Path (Join-Path $Root 'models')) -and
           ((Test-Path (Join-Path $Root 'webui-user.bat')) -or
            (Test-Path (Join-Path $Root 'webui.py')) -or
            (Test-Path (Join-Path $Root 'launch.py')))
}

if (-not (Test-IsWebUIRoot $WebUIRoot)) {
    Write-Host "'$WebUIRoot' does not look like a Stable Diffusion WebUI install." -ForegroundColor Red
    Write-Host "Expected a 'models' folder plus webui-user.bat / webui.py / launch.py."
    Write-Host "Re-run from the WebUI root, or: .\install-quality-pack.ps1 -WebUIRoot 'C:\path\to\webui'"
    exit 1
}

Write-Host "WebUI root: $WebUIRoot`n" -ForegroundColor Cyan

$Failed = @()

foreach ($item in $Downloads) {
    $destDir = Join-Path $WebUIRoot $item.Dir
    $dest    = Join-Path $destDir $item.Name

    if (Test-Path $dest) {
        $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Host "SKIP  $($item.Name) - already present ($sizeMB MB)" -ForegroundColor DarkGray
        continue
    }

    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $ok = $false
    foreach ($url in $item.Urls) {
        $tmp = "$dest.part"
        Write-Host "GET   $($item.Name)" -ForegroundColor Yellow
        Write-Host "      $url" -ForegroundColor DarkGray
        try {
            $ProgressPreference = 'SilentlyContinue'   # 10x faster on large files
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -MaximumRedirection 10

            $len = (Get-Item $tmp).Length
            if ($len -lt $item.MinBytes) {
                # Almost always an HTML error page or an auth redirect, not the model.
                throw "downloaded only $([math]::Round($len/1MB,2)) MB, expected at least $([math]::Round($item.MinBytes/1MB,0)) MB"
            }

            Move-Item -Force $tmp $dest
            Write-Host "OK    $($item.Name) ($([math]::Round($len/1MB,1)) MB)`n" -ForegroundColor Green
            $ok = $true
            break
        }
        catch {
            Write-Host "FAIL  $($_.Exception.Message)" -ForegroundColor Red
            Remove-Item -Force -ErrorAction SilentlyContinue $tmp
        }
    }

    if (-not $ok) { $Failed += $item.Name }
}

# Forge and some reForge builds look in models\RealESRGAN instead of models\ESRGAN.
# Copy the upscalers across so both layouts find them.
$esrgan = Join-Path $WebUIRoot 'models\ESRGAN'
$real   = Join-Path $WebUIRoot 'models\RealESRGAN'
if ((Test-Path $esrgan) -and (Test-Path $real)) {
    Get-ChildItem $esrgan -Filter *.pth | ForEach-Object {
        $target = Join-Path $real $_.Name
        if (-not (Test-Path $target)) {
            Copy-Item $_.FullName $target
            Write-Host "COPY  $($_.Name) -> models\RealESRGAN" -ForegroundColor DarkGray
        }
    }
}

Write-Host "`n--------------------------------------------------------------"
if ($Failed.Count -gt 0) {
    Write-Host "These files did not download:" -ForegroundColor Red
    $Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Download them by hand and drop them in the folders listed in QUALITY-SETUP.md."
} else {
    Write-Host "All downloads complete." -ForegroundColor Green
}

Write-Host @"

MANUAL STEP - the two detail LoRAs
----------------------------------
Civitai requires a logged-in session, so these can't be scripted reliably.
Search Civitai for each, download the SDXL version, and save to:

    $WebUIRoot\models\Lora\

  1. "Detail Tweaker XL"   (add-detail-xl)
  2. "XL More Art - Full"  (xl_more_art-full)

MANUAL STEP - ADetailer (biggest win for photoreal faces)
---------------------------------------------------------
Extensions -> Install from URL -> https://github.com/Bing-su/adetailer
Restart the WebUI afterwards; it downloads its detection models on first run.

Then apply the settings in QUALITY-SETUP.md.
"@ -ForegroundColor Cyan
