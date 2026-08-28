<#
  LU AI - Photorealism Pack installer for Juggernaut XL v9 (ComfyUI / Windows)

  Downloads the SDXL VAE and two upscale models into the ComfyUI model folders.

  LU AI's launcher lives in C:\Program Files\Locally Uncensored, but the ComfyUI
  backend and its models sit in the user profile at %USERPROFILE%\ComfyUI - so
  this needs NO administrator rights.

  RUN IT - a normal PowerShell window is fine:

      powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\install-quality-pack.ps1"

  If Windows blocks the downloaded script ("not digitally signed"), unblock it:

      Unblock-File "$env:USERPROFILE\Desktop\install-quality-pack.ps1"

  ComfyUI uses lowercase folder names (models\vae, models\loras,
  models\upscale_models) that differ from other WebUIs - the usual reason a
  downloaded file never shows up in a node dropdown.

  The two detail LoRAs are Civitai-hosted and need a logged-in download, and
  Impact Pack installs through ComfyUI Manager; instructions print at the end.
#>

param(
    [string]$ComfyUIRoot = (Join-Path $env:USERPROFILE 'ComfyUI')
)

$ErrorActionPreference = 'Stop'

function Resolve-ComfyUIRoot {
    param([string]$Start)

    if (-not $Start -or -not (Test-Path $Start)) { return $null }

    # A ComfyUI root holds models\checkpoints. Packaged builds sometimes nest it,
    # so probe the common spots before falling back to a bounded search.
    $known = @(
        $Start,
        (Join-Path $Start 'ComfyUI'),
        (Join-Path $Start 'resources\ComfyUI'),
        (Join-Path $Start 'ComfyUI_windows_portable\ComfyUI')
    )
    foreach ($c in $known) {
        if (Test-Path (Join-Path $c 'models\checkpoints')) { return $c }
    }

    $hit = Get-ChildItem -Path $Start -Directory -Recurse -Depth 4 -Filter 'checkpoints' `
             -ErrorAction SilentlyContinue |
           Where-Object { $_.Parent.Name -eq 'models' } |
           Select-Object -First 1
    if ($hit) { return $hit.Parent.Parent.FullName }

    return $null
}

$root = Resolve-ComfyUIRoot $ComfyUIRoot
if (-not $root) {
    Write-Host "No ComfyUI install found at '$ComfyUIRoot'." -ForegroundColor Red
    Write-Host "Expected a 'models\checkpoints' folder. Locate it with:"
    Write-Host ""
    Write-Host "  Get-ChildItem `$env:USERPROFILE -Directory -Recurse -Depth 6 -Filter checkpoints ``" -ForegroundColor White
    Write-Host "    -ErrorAction SilentlyContinue | Where-Object {`$_.Parent.Name -eq 'models'}" -ForegroundColor White
    Write-Host ""
    Write-Host "Then re-run with:  -ComfyUIRoot `"<the folder above models\>`""
    exit 1
}

Write-Host "ComfyUI root: $root" -ForegroundColor Cyan

# Only Program Files and similar protected locations need elevation; a install
# under the user profile does not.
if ($root -like "$env:ProgramFiles*" -or $root -like "${env:ProgramFiles(x86)}*") {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $elevated) {
        Write-Host "This root is under Program Files and needs an Administrator PowerShell." -ForegroundColor Red
        Write-Host "Start menu -> right-click 'Windows PowerShell' -> Run as administrator."
        exit 1
    }
}

# An active extra_model_paths.yaml can redirect model loading somewhere else.
$extraPaths = Join-Path $root 'extra_model_paths.yaml'
if (Test-Path $extraPaths) {
    $active = Get-Content $extraPaths | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
    if ($active) {
        Write-Host "NOTE: extra_model_paths.yaml has active entries. If models don't appear" -ForegroundColor Yellow
        Write-Host "      after restarting, ComfyUI is loading them from the paths in it." -ForegroundColor Yellow
    }
}
Write-Host ""

# Destination subfolder, filename, minimum plausible size, and sources in order.
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
                # A short file is an HTML error page or an auth redirect, not a model.
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

# Ensure the LoRA folder exists for the manual step below.
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
   Grab the SDXL version of each and save to:
       $root\models\loras\
     - "Detail Tweaker XL"   (add-detail-xl)
     - "XL More Art - Full"  (xl_more_art-full)

2. FaceDetailer - ComfyUI's equivalent of ADetailer
   ComfyUI Manager -> Custom Nodes Manager -> search "Impact Pack"
   -> install ComfyUI-Impact-Pack

3. Fully quit and relaunch LU AI. A browser refresh is not enough -
   new model files are only picked up when the backend starts.

4. Build the node chain in QUALITY-SETUP.md section 7, then
   Workflow -> Export so you never have to rebuild it.
"@ -ForegroundColor Cyan
