#!/usr/bin/env bash
# LU AI - Photorealism Pack installer for Juggernaut XL v9 (Linux / macOS)
#
# Downloads the VAE and upscalers into a Stable Diffusion WebUI install.
# Run from your WebUI root, or pass the root as the first argument:
#
#     ./install-quality-pack.sh [/path/to/stable-diffusion-webui]
#
# The two detail LoRAs are Civitai-hosted and need a logged-in download;
# instructions for those are printed at the end.

set -uo pipefail

ROOT="${1:-$PWD}"

if [[ ! -d "$ROOT/models" ]] || \
   [[ ! -f "$ROOT/webui.py" && ! -f "$ROOT/launch.py" && ! -f "$ROOT/webui-user.sh" ]]; then
    echo "'$ROOT' does not look like a Stable Diffusion WebUI install." >&2
    echo "Expected a 'models' directory plus webui.py / launch.py / webui-user.sh." >&2
    exit 1
fi

echo "WebUI root: $ROOT"
echo

failed=()

# fetch <subdir> <filename> <min_megabytes> <url> [fallback_url ...]
fetch() {
    local subdir="$1" name="$2" min_mb="$3"; shift 3
    local dir="$ROOT/$subdir" dest="$dir/$name" tmp

    if [[ -f "$dest" ]]; then
        echo "SKIP  $name - already present ($(du -h "$dest" | cut -f1))"
        return 0
    fi

    mkdir -p "$dir"
    tmp="$dest.part"

    for url in "$@"; do
        echo "GET   $name"
        echo "      $url"
        if curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$tmp" "$url"; then
            local bytes
            bytes=$(wc -c < "$tmp")
            # A short file is an HTML error page or an auth redirect, not the model.
            if (( bytes < min_mb * 1024 * 1024 )); then
                echo "FAIL  got $(( bytes / 1024 / 1024 )) MB, expected at least ${min_mb} MB" >&2
                rm -f "$tmp"
                continue
            fi
            mv -f "$tmp" "$dest"
            echo "OK    $name ($(du -h "$dest" | cut -f1))"
            echo
            return 0
        fi
        rm -f "$tmp"
        echo "FAIL  download error" >&2
    done

    failed+=("$name")
    return 1
}

fetch models/VAE sdxl_vae.safetensors 100 \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors?download=true" \
    "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl.vae.safetensors?download=true"

fetch models/ESRGAN 4x-UltraSharp.pth 30 \
    "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth?download=true" \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth?download=true"

fetch models/ESRGAN 4x_NMKD-Siax_200k.pth 30 \
    "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth?download=true" \
    "https://huggingface.co/gemasai/4x_NMKD-Siax_200k/resolve/main/4x_NMKD-Siax_200k.pth?download=true"

# Forge and some reForge builds read models/RealESRGAN instead of models/ESRGAN.
if [[ -d "$ROOT/models/RealESRGAN" ]]; then
    for f in "$ROOT"/models/ESRGAN/*.pth; do
        [[ -e "$f" ]] || continue
        target="$ROOT/models/RealESRGAN/$(basename "$f")"
        [[ -e "$target" ]] || { cp "$f" "$target"; echo "COPY  $(basename "$f") -> models/RealESRGAN"; }
    done
fi

echo
echo "--------------------------------------------------------------"
if (( ${#failed[@]} > 0 )); then
    echo "These files did not download:"
    printf '  - %s\n' "${failed[@]}"
    echo "Download them by hand into the folders listed in QUALITY-SETUP.md."
else
    echo "All downloads complete."
fi

cat <<MANUAL

MANUAL STEP - the two detail LoRAs
----------------------------------
Civitai requires a logged-in session, so these can't be scripted reliably.
Search Civitai for each, download the SDXL version, and save to:

    $ROOT/models/Lora/

  1. "Detail Tweaker XL"   (add-detail-xl)
  2. "XL More Art - Full"  (xl_more_art-full)

MANUAL STEP - ADetailer (biggest win for photoreal faces)
---------------------------------------------------------
Extensions -> Install from URL -> https://github.com/Bing-su/adetailer
Restart the WebUI afterwards; it downloads its detection models on first run.

Then apply the settings in QUALITY-SETUP.md.
MANUAL
