<#
  LU AI - Photorealism Pack installer for Juggernaut XL v9 (ComfyUI / Windows)

  Downloads the SDXL VAE and the two upscale models into the ComfyUI model
  folders. ComfyUI uses lowercase folder names (models\vae, models\loras,
  models\upscale_models) that differ from other WebUIs, which is the usual
  reason a downloaded file never shows up in a node dropdown.

  LU AI installs to C:\Program Files\Locally Uncensored, which Windows
  protects - so this MUST be run from an elevated (Administrator) PowerShell
  or every download will fail with an access-denied error. The script checks
  and tells you if you are not elevated.

  RUN IT:
    1. Start menu -> type "powershell"
    2. Right-click "Windows PowerShell" -> Run as administrator
    3. Paste:

       powershell -ExecutionPolicy Bypass -File "<path to this file>\install-quality-pack.ps1"

  The two detail LoRAs are Civitai-hosted and need a logged-in download, and
  Impact Pack installs through ComfyUI Manager; instructions print at the end.
#>

param(
    # Defaults to the standard LU AI install location.
    [string]$ComfyUIRoot = 'C:\Program Files\Locally Uncensored'
)

$ErrorActionPreference = 'Stop'

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-ComfyUIRoot {
    param([string]$Start)

    if (-not (Test-Path $Start)) { return $null }

    # A ComfyUI root holds models\checkpoints. Packaged apps bury it at various
    # depths (resources\ComfyUI, app\ComfyUI, ComfyUI_windows_portable\ComfyUI),
    # so try the common spots first, then fall back to a bounded search.
    $known = @(
        $Start,
        (Join-Path $Start 'ComfyUI'),
        (Join-Path $Start 'resources\ComfyUI'),
        (Join-Path $Start 'app\ComfyUI'),
        (Join-Path $Start 'ComfyUI_windows_portable\ComfyUI')
    )
    foreach ($c in $known) {
        if (Test-Path (Join-Path $c 'models\checkpoints')) { return $c }
    }

    Write-Host "Searching for the models folder under $Start ..." -ForegroundColor DarkGray
    $hit = Get-ChildItem -Path $Start -Directory -Recurse -Depth 4 -Filter 'checkpoints' `
             -ErrorAction SilentlyContinue |
           Where-Object { $_.Parent.Name -eq 'models' } |
           Select-Object -First 1
    if ($hit) { return $hit.Parent.Parent.FullName }

    return $null
}

if (-not (Test-Elevated)) {
    Write-Host ""
    Write-Host "NOT RUNNING AS ADMINISTRATOR" -ForegroundColor Red
    Write-Host ""
    Write-Host "LU AI lives under C:\Program Files, which Windows protects. Without"
    Write-Host "elevation every download here will fail with access denied."
    Write-Host ""
    Write-Host "  1. Start menu -> type: powershell"
    Write-Host "  2. Right-click 'Windows PowerShell' -> Run as administrator"
    Write-Host "  3. Re-run this script from that window"
    Write-Host ""
    exit 1
}

$root = Resolve-ComfyUIRoot $ComfyUIRoot
if (-not $root) {
    Write-Host "Could not find a ComfyUI install at '$ComfyUIRoot'." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected to find a 'models\checkpoints' folder somewhere beneath it."
    Write-Host ""
    Write-Host "Show me what's actually in there and I can point you at the right path:"
    Write-Host ""
    Write-Host "  Get-ChildItem -Path '$ComfyUIRoot' -Directory -Recurse -Depth 3 |" -ForegroundColor White
    Write-Host "    Select-Object -ExpandProperty FullName" -ForegroundColor White
    Write-Host ""
    Write-Host "Or pass the correct folder directly:"
    Write-Host "  .\install-quality-pack.ps1 -ComfyUIRoot `"<path containing models\checkpoints>`""
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
