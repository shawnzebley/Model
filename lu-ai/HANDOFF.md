# Handoff — Juggernaut XL v9 photorealism setup (ComfyUI via LU AI)

Context for continuing this work in another session.

## The setup

| Piece | Detail |
|---|---|
| App | **LU AI** ("Locally Uncensored") — packaged front end for local AI engines |
| Launcher | `C:\Program Files\Locally Uncensored` — app shell only, nothing to edit |
| Image engine | **ComfyUI** at `C:\Users\13024\ComfyUI` — installed by LU AI, no admin needed |
| ComfyUI web UI | `http://127.0.0.1:8188` while LU AI runs — full node canvas, current frontend |
| Checkpoint | `Juggernaut-XL_v9.safetensors` (capital J), from LU AI's built-in model store |
| OS / shell | Windows, PowerShell |

LU AI's twelve advertised backends (Ollama, LM Studio, vLLM, KoboldCpp, etc.) are
all **text** LLM engines. Images go through ComfyUI only.

## Installed and working

- `models\vae\sdxl_vae.safetensors` — 319.1 MB
- `models\upscale_models\4x-UltraSharp.pth` — 63.9 MB
- `models\upscale_models\4x_NMKD-Siax_200k.pth` — 63.9 MB
- Custom nodes already shipped with LU AI: **ComfyUI-Impact-Pack**,
  **ComfyUI-Impact-Subpack**, ComfyUI-RMBG, ComfyUI-FramePackWrapper
- A working two-pass workflow, run successfully with no errors

Note: `ComfyUI-AnimateDiff-Evolved` fails to import (video animation, unrelated,
ignored).

## The workflow

`juggernaut-hires.json` — 14 nodes, loads fully wired by dragging onto the canvas:

```
Load Checkpoint ─┬─> CLIP Text Encode (pos) ─┐
                 └─> CLIP Text Encode (neg) ─┤
Empty Latent 1024x1024 ─────────────────────┴─> KSampler PASS 1
   -> VAE Decode -> Upscale Image (4x-UltraSharp) -> Image Scale By 0.5
   -> VAE Encode -> KSampler PASS 2 (denoise 0.40) -> VAE Decode -> Save Image
```

`Load VAE` (sdxl_vae) feeds all three VAE inputs. Both KSamplers share one pair
of conditioning nodes.

`juggernaut-hires-lora.json` — same plus a `Load LoRA` node in the MODEL/CLIP
path ahead of both samplers and both text encoders, weight 0.4.

## Settings in use

```
Sampler:          dpmpp_2m        (sampler_name)
Scheduler:        karras
Pass 1:           35 steps, cfg 4.0, denoise 1.0
Upscale:          4x-UltraSharp -> Image Scale By 0.5  (net 2x, 1024 -> 2048)
Pass 2:           22 steps, cfg 4.0, denoise 0.40
Resolution:       1024x1024 (SDXL-native; also 832x1216, 1216x832)
```

**CFG 3–6 for Juggernaut v9, default 4.** Higher burns contrast into plastic skin.

## Outstanding

1. **Detail LoRA (§5)** — not downloaded. Civitai needs a browser login. Get
   "Detail Tweaker XL" (SDXL version) into `C:\Users\13024\ComfyUI\models\loras`,
   restart LU AI, then load `juggernaut-hires-lora.json` and pick the file in the
   `Load LoRA` dropdown. Weight 0.3–0.5. Optional second: "XL More Art - Full".
2. **FaceDetailer (§6)** — Impact Pack is installed and imports fine; the nodes
   just need placing. Add `FaceDetailer` and `UltralyticsDetectorProvider`
   (`bbox/face_yolov8m.pt`) after the final VAE Decode, rewire Save Image to
   FaceDetailer's IMAGE output, set denoise 0.40 / cfg 4.0 / dpmpp_2m / karras.
   Wiring table is in QUALITY-SETUP.md §6.
3. **A/B the second pass** — set both KSampler seeds to `fixed`, compare pass 2
   denoise 0.0 vs 0.40 to confirm it's earning its runtime.

## Gotchas hit along the way

- ComfyUI folders are **lowercase** and differ from other WebUIs: `vae`, `loras`,
  `upscale_models` — not `VAE`, `Lora`, `ESRGAN`.
- Filenames match **exactly**, including case (`Juggernaut-XL_v9`, capital J).
- `<lora:name:0.4>` prompt syntax is Automatic1111 only — inert in ComfyUI, where
  a LoRA is a node.
- Templates tagged **API** (Seedream, GPT Image, Grok, Qwen) call paid cloud
  services and do not use the local checkpoint.
- Node search is **double-click on empty canvas**, not the Nodes panel in the
  left rail — the left rail does not surface custom nodes the same way.
- `UltralyticsDetectorProvider` lives in Impact **Subpack**, not the main pack.
- `Invoke-RestMethod` on `/object_info` returns an array; check for a node with
  a raw string search on `Invoke-WebRequest ... .Content` instead.
- Startup log: `C:\Users\13024\ComfyUI\comfyui.log`, grep `IMPORT FAILED`.

## Prompting Juggernaut

Photographic language works; quality-tag soup backfires.

Good: camera + lens (`shot on Canon EOS R5, 85mm f/1.4`), a named light source,
imperfection (`film grain`, `visible skin texture`, `flyaway hairs`), framing
(`candid`, `documentary photo`).

Avoid: `masterpiece, best quality, 8k, hyperrealistic, trending on artstation` —
these pull toward CGI and digital art.

Negative prompt, kept short:
```
cartoon, illustration, 3d render, painting, plastic skin, airbrushed, watermark, text
```

## Files

On branch `claude/lu-ai-quality-settings-0jwtbt` of `shawnzebley/Model`, in `lu-ai/`:

- `QUALITY-SETUP.md` — the full guide, §0–§8 plus troubleshooting
- `juggernaut-hires.json` — working two-pass workflow
- `juggernaut-hires-lora.json` — same plus LoRA node
- `install-quality-pack.ps1` — downloader for VAE and upscalers
