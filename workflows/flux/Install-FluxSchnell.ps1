<#
.SYNOPSIS
  Verifies (and optionally places) the FLUX.1 Schnell files ComfyUI needs, then
  tells you which workflow JSON in this folder to import into LU.

.DESCRIPTION
  Read-only by default: it reports what is present, missing, or in the wrong
  folder. Add -Apply to actually move files out of Downloads into ComfyUI's
  model folders. It never stops ComfyUI and never touches the GPU, so it is
  safe to run while a training job is in progress.

.EXAMPLE
  .\Install-FluxSchnell.ps1
  .\Install-FluxSchnell.ps1 -Apply
  .\Install-FluxSchnell.ps1 -ComfyRoot 'D:\ComfyUI' -Apply -Hash
#>

[CmdletBinding()]
param(
  [string] $ComfyRoot = (Join-Path $env:USERPROFILE 'ComfyUI'),
  [string] $Downloads = (Join-Path $env:USERPROFILE 'Downloads'),
  [string] $ComfyUrl  = 'http://127.0.0.1:8188',
  [switch] $Apply,
  [switch] $Hash
)

$ErrorActionPreference = 'Stop'

# filename -> model subfolder it belongs in
$Placement = [ordered]@{
  'flux1-schnell-fp8.safetensors'  = 'checkpoints'      # 17.2 GB all-in-one
  'flux1-schnell.safetensors'      = 'diffusion_models' # bare UNet
  't5xxl_fp8_e4m3fn.safetensors'   = 'text_encoders'
  'clip_l.safetensors'             = 'text_encoders'
  'ae.safetensors'                 = 'vae'
  'flux_topless_v1.safetensors'    = 'loras'
}

$ModelRoot = Join-Path $ComfyRoot 'models'
if (-not (Test-Path $ModelRoot)) {
  throw "No models folder under '$ComfyRoot'. Pass -ComfyRoot with the right path."
}

function Format-Size([long] $Bytes) { '{0:N2} GB' -f ($Bytes / 1GB) }

$found = @{}

foreach ($name in $Placement.Keys) {
  $folder = $Placement[$name]
  $dest   = Join-Path (Join-Path $ModelRoot $folder) $name

  if (Test-Path $dest) {
    $f = Get-Item $dest
    $found[$name] = $folder
    Write-Host ("  OK       {0,-32} {1,-17} {2}" -f $name, $folder, (Format-Size $f.Length)) -ForegroundColor Green
    if ($Hash) {
      Write-Host ("           sha256 {0}" -f (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()) -ForegroundColor DarkGray
    }
    continue
  }

  # not in place - is it sitting in Downloads, or in a sibling model folder?
  $stray = @(Get-ChildItem -Path $ModelRoot -Recurse -Filter $name -File -ErrorAction SilentlyContinue)
  $inDownloads = Join-Path $Downloads $name

  if ($stray.Count -gt 0) {
    $src = $stray[0].FullName
    Write-Host ("  MISPLACED {0,-31} is in '{1}', belongs in '{2}'" -f $name, (Split-Path $src -Parent), $folder) -ForegroundColor Yellow
  }
  elseif (Test-Path $inDownloads) {
    $src = $inDownloads
    Write-Host ("  IN DOWNLOADS {0,-28} {1}" -f $name, (Format-Size (Get-Item $src).Length)) -ForegroundColor Yellow
  }
  else {
    Write-Host ("  MISSING  {0,-32} expected in models\{1}" -f $name, $folder) -ForegroundColor DarkGray
    continue
  }

  if ($Apply) {
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Move-Item -LiteralPath $src -Destination $dest
    Write-Host ("           moved -> models\{0}" -f $folder) -ForegroundColor Green
    $found[$name] = $folder
  }
  else {
    Write-Host  "           re-run with -Apply to move it" -ForegroundColor DarkGray
  }
}

# --- decide which workflow to import -------------------------------------
Write-Host ''
$hasCkpt = $found.ContainsKey('flux1-schnell-fp8.safetensors')
$hasUnet = $found.ContainsKey('flux1-schnell.safetensors')
$hasLora = $found.ContainsKey('flux_topless_v1.safetensors')
$hasEnc  = $found.ContainsKey('t5xxl_fp8_e4m3fn.safetensors') -and $found.ContainsKey('clip_l.safetensors')
$hasVae  = $found.ContainsKey('ae.safetensors')

if ($hasCkpt) {
  $wf = 'flux1-schnell-checkpoint-lora-api.json'
  Write-Host "Import this workflow into LU: $wf" -ForegroundColor Cyan
  Write-Host "  (all-in-one checkpoint - it carries its own T5, CLIP-L and VAE)"
}
elseif ($hasUnet -and $hasEnc -and $hasVae) {
  $wf = if ($hasLora) { 'flux1-schnell-fp8-lora-api.json' } else { 'flux1-schnell-fp8-api.json' }
  Write-Host "Import this workflow into LU: $wf" -ForegroundColor Cyan
}
else {
  Write-Host "No complete FLUX set yet - install the base model, then re-run." -ForegroundColor Yellow
}
if (-not $hasLora) { Write-Host "  LoRA add-on not installed; the -lora workflows will fail until it is." -ForegroundColor DarkGray }

# --- ask a running ComfyUI what it can actually see -----------------------
Write-Host ''
try {
  $info = Invoke-RestMethod -Uri "$ComfyUrl/object_info" -TimeoutSec 20
  $ckpts = @($info.CheckpointLoaderSimple.input.required.ckpt_name[0])
  $unets = @($info.UNETLoader.input.required.unet_name[0])
  $loras = @($info.LoraLoader.input.required.lora_name[0])
  Write-Host "ComfyUI at $ComfyUrl reports:" -ForegroundColor Cyan
  Write-Host ("  checkpoints      : {0}" -f (($ckpts | Where-Object { $_ -match 'flux' }) -join ', '))
  Write-Host ("  diffusion_models : {0}" -f (($unets | Where-Object { $_ -match 'flux' }) -join ', '))
  Write-Host ("  loras            : {0}" -f (($loras | Where-Object { $_ -match 'flux' }) -join ', '))
  Write-Host "If a file you just moved is absent here, refresh the ComfyUI tab (it rescans on refresh; no restart needed)."
}
catch {
  Write-Host "Could not reach ComfyUI at $ComfyUrl - start it, or pass -ComfyUrl. Placement above is still valid." -ForegroundColor DarkGray
}
