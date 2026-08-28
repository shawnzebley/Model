<#
  LU AI - Photorealism Pack installer for Juggernaut XL v9 (ComfyUI / Windows)

  Downloads the SDXL VAE and the two upscale models into the ComfyUI model
  folders. ComfyUI uses lowercase folder names (models\vae, models\loras,
  models\upscale_models) that differ from other WebUIs, which is the usual
  reason a downloaded file never shows up in a node dropdown.

  Usage - right-click the LU AI desktop shortcut, Properties, and copy the
  folder from "Start in". Then:

      powershell -ExecutionPolicy Bypass -File .\install-quality-pack.ps1 -ComfyUIRoot "C:\path\to\ComfyUI"

  Run with no arguments from inside the ComfyUI folder and it will find itself.

  The two detail LoRAs are Civitai-hosted and need a logged-in download, and
  Impact Pack installs through ComfyUI Manager; instructions print at the end.
#>

param(
    [string]$ComfyUIRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Resolve-ComfyUIRoot {
    param([string]$Start)

    # A ComfyUI root holds models\checkpoints. Portable builds nest the real
    # root one level down (ComfyUI_windows_portable\ComfyUI), so check there
    # and in a parent before giving up.
    $candidates = @(
        $Start,
        (Join-Path $Start 'ComfyUI'),
        (Split-Path -Parent $Start)
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'models\checkpoints'))) { return $c }
    }
    return $null
}

$root = Resolve-ComfyUIRoot $ComfyUIRoot
if (-not $root) {
    Write-Host "Could not find a ComfyUI install at '$ComfyUIRoot'." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected a 'models\checkpoints' folder. To find the right path:"
    Write-Host "  1. Right-click the LU AI shortcut on your desktop -> Properties"
    Write-Host "  2. Copy the 'Start in' path"
    Write-Host "  3. Re-run:  .\install-quality-pack.ps1 -ComfyUIRoot `"<that path>`""
    exit 1
}

Write-Host "ComfyUI root: $root" -ForegroundColor Cyan

# If extra_model_paths.yaml is active it can redirect model loading elsewhere,
# in which case files placed here may never appear in the dropdowns.
$extraPaths = Join-Path $root 'extra_model_paths.yaml'
if (Test-Path $extraPaths) {
    $active = Get-Content $extraPaths | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
    if ($active) {
        Write-Host ""
        Write-Host "NOTE: extra_model_paths.yaml is present and has uncommented entries." -ForegroundColor Yellow
        Write-Host "      If models don't appear after restarting, ComfyUI is loading them" -ForegroundColor Yellow
        Write-Host "      from the paths in that file - put these downloads there instead." -ForegroundColor Yellow
    }
}
Write-Host ""

# Destination subfolder, filename, minimum plausible size, and source URLs
# tried in order.
$Downloads = @(
    @{
        Dir = 'models\vae'; Name = 'sdxl_vae.safetensors'; MinBytes = 100MB
        Urls = @(
            'https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors?download=true',
            'https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl.vae.safetensors?download=true'
        )
    },
    @{
        Dir = 'models\upscale_models'; Name = '4x-UltraSharp.pth'; MinBytes = 30MB
        Urls = @(
            'https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth?download=true',
            'https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth?download=true'
        )
    },
    @{
        Dir = 'models\upscale_models'; Name = '4x_NMKD-Siax_200k.pth'; MinBytes = 30MB
        Urls = @(
            'https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth?download=true',
            'https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth?download=true'
        )
    }
)

$Failed = @()

foreach ($item in $Downloads) {
    $destDir = Join-Path $root $item.Dir
    $dest    = Join-Path $destDir $item.Name

    if (Test-Path $dest) {
        Write-Host ("SKIP  {0} - already present ({1} MB)" -f $item.Name,
                    [math]::Round((Get-Item $dest).Length / 1MB, 1)) -ForegroundColor DarkGray
        continue
    }

    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $ok = $false
    foreach ($url in $item.Urls) {
        $tmp = "$dest.part"
        Write-Host "GET   $($item.Name)" -ForegroundColor Yellow
        Write-Host "      $url" -ForegroundColor DarkGray
        try {
            $ProgressPreference = 'SilentlyContinue'   # much faster on large files
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -MaximumRedirection 10

            $len = (Get-Item $tmp).Length
            if ($len -lt $item.MinBytes) {
                # Short file means an HTML error page or an auth redirect, not a model.
                throw ("got {0} MB, expected at least {1} MB" -f
                       [math]::Round($len/1MB,2), [math]::Round($item.MinBytes/1MB,0))
            }

            Move-Item -Force $tmp $dest
            Write-Host ("OK    {0} ({1} MB) -> {2}`n" -f $item.Name,
                        [math]::Round($len/1MB,1), $item.Dir) -ForegroundColor Green
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

# Make sure models\loras exists so the manual LoRA step has somewhere to go.
New-Item -ItemType Directory -Force -Path (Join-Path $root 'models\loras') | Out-Null

Write-Host "--------------------------------------------------------------"
if ($Failed.Count -gt 0) {
    Write-Host "These did not download:" -ForegroundColor Red
    $Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Download them by hand into the folders listed in QUALITY-SETUP.md."
} else {
    Write-Host "All downloads complete." -ForegroundColor Green
}

Write-Host @"

REMAINING STEPS - these can't be scripted
------------------------------------------
1. Detail LoRAs (Civitai needs a logged-in download)
   Search Civitai, grab the SDXL version of each, save to:
       $root\models\loras\
     - "Detail Tweaker XL"   (add-detail-xl)
     - "XL More Art - Full"  (xl_more_art-full)

2. FaceDetailer - ComfyUI's equivalent of ADetailer
   ComfyUI Manager -> Custom Nodes Manager -> search "Impact Pack"
   -> install ComfyUI-Impact-Pack

3. Fully restart ComfyUI (close it, relaunch LU AI). A browser refresh
   is not enough - new model files are only picked up on startup.

4. Build the node chain in QUALITY-SETUP.md section 7, then
   Workflow -> Export so you never have to rebuild it.
"@ -ForegroundColor Cyan
