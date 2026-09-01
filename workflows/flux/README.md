# FLUX.1 Schnell workflows for ComfyUI / LU

Three ComfyUI **API-format** graphs (the format LU imports, same as the Z-Image
workflow), plus a script that checks your local install and tells you which one
to use.

## Which file do I import?

It depends on which base model you downloaded, because the two FLUX Schnell
releases are packaged differently:

| Base model on disk | Size | Goes in | Import |
|---|---|---|---|
| `flux1-schnell-fp8.safetensors` (Comfy-Org all-in-one) | ~17.2 GB | `models\checkpoints` | `flux1-schnell-checkpoint-lora-api.json` |
| `flux1-schnell.safetensors` (bare UNet, BFL) | ~23.8 GB | `models\diffusion_models` | `flux1-schnell-fp8-lora-api.json` |

The all-in-one FP8 checkpoint already contains T5-XXL, CLIP-L and the VAE, so it
loads through `CheckpointLoaderSimple` and ignores your separate encoder files.
The bare UNet loads through `UNETLoader` and needs `t5xxl_fp8_e4m3fn`,
`clip_l` and `ae` supplied separately — which is what the split workflows wire up.

`flux1-schnell-fp8-api.json` is the split graph **without** the LoRA, for a clean
base-only run.

## Add-ons included

`flux_topless_v1.safetensors` is wired in as a LoRA in both `-lora` graphs:

* checkpoint graph → `LoraLoader` at `strength_model` / `strength_clip` **0.80**
* split-UNet graph → `LoraLoaderModelOnly` at `strength_model` **0.80**
  (a UNet-only load, since the split graph's CLIP comes from `DualCLIPLoader`)

Its metadata is inconsistent, so if output looks scrambled, drop the strength to
0.5 or import the base-only graph to confirm the model itself is fine first.

## Files

| Path | What it is |
|---|---|
| `flux1-schnell-fp8-api.json` | Split UNet + T5/CLIP-L + ae, no LoRA |
| `flux1-schnell-fp8-lora-api.json` | Same, with the LoRA add-on |
| `flux1-schnell-checkpoint-lora-api.json` | All-in-one FP8 checkpoint + LoRA |
| `Install-FluxSchnell.ps1` | Verifies file placement, picks the right graph |

## Install / verify

From PowerShell on the machine running ComfyUI:

```powershell
# report only - nothing is moved
.\Install-FluxSchnell.ps1

# actually move files out of Downloads into the model folders
.\Install-FluxSchnell.ps1 -Apply

# add SHA-256 of each file in place
.\Install-FluxSchnell.ps1 -Apply -Hash
```

It never stops ComfyUI and never touches the GPU, so it is safe to run while a
training job is going. After moving files, refresh the ComfyUI tab — it rescans
the model folders on refresh; a restart is not required.

## Settings baked into the graphs

Schnell is a 4-step, guidance-distilled model, so: **steps 4, cfg 1.0, euler /
simple**, and the negative prompt is a `ConditioningZeroOut` rather than a real
prompt — a negative prompt does nothing at CFG 1.0. Resolution defaults to
1024×1024; on a 6 GB card drop node `6` to 768×768 if you hit an OOM before
offloading kicks in.

`seed` is `0` in the JSON. LU overrides it per generation; if you run the graph
straight against the ComfyUI API instead, randomize it yourself.

## Krea 2 — not covered here

Krea 2 is a separate model family: it does not use FLUX's T5-XXL, CLIP-L or
`ae.safetensors`. It still needs `krea2_turbo_fp8_scaled` (diffusion_models),
`qwen3vl_4b_fp8_scaled` (text_encoders) and `qwen_image_vae` (vae) before a
workflow can be built. Your three Krea 2 LoRAs are already in the right place.
