# LU AI — High-Quality Settings & Extensions

Setup notes for a local Stable Diffusion XL install (Automatic1111 / Forge / reForge).
Run `install-quality-pack.ps1` (Windows) or `install-quality-pack.sh` (Linux/macOS)
from your WebUI root to download the files, then apply the settings below.

---

## 1. VAE — fixes washed-out color

The VAE is the decoder that turns the model's latent output into actual pixels.
SDXL's baked-in fp16 VAE overflows on bright areas, which is what produces the
gray, milky, slightly-blown look people blame on the checkpoint.

**Juggernaut v9 ships with the corrected VAE baked in**, so you may see no change.
Set it explicitly anyway: the moment you swap checkpoints (or load a merge that
doesn't include one) you'll otherwise get the washed-out look back and spend an
hour blaming the prompt.

**File:** `sdxl_vae.safetensors` → `models/VAE/`

**Apply:** Settings → VAE → *SD VAE* = `sdxl_vae.safetensors` (not "Automatic").
Also tick Settings → User Interface → *Quicksettings list* → add `sd_vae` so it
sits at the top of the page and you can see which VAE is live.

If your checkpoint already ships a good VAE baked in (most modern SDXL merges do),
"Automatic" is fine — but setting it explicitly means you always know what you got.

---

## 2. Sampler — texture and micro-detail

| Sampler | Steps | Use it for |
|---|---|---|
| **DPM++ 2M Karras** | 30–40 | Juggernaut's own recommended sampler. Sharpest skin/fabric texture. |
| **UniPC** | 20–25 | Same quality, fewer steps. Good for fast iteration, then re-roll the keeper on 2M. |
| DPM++ SDE Karras | 30–40 | Slower, sometimes richer. Non-deterministic — same seed ≠ same image. |

**CFG scale: 3–6.** Juggernaut v9 is tuned to run at low CFG — lower than SDXL
generally and much lower than SD 1.5 habits suggest. CFG 8+ burns contrast and
produces exactly the plastic, over-saturated skin that reads as AI. **Start at 4.**
If the image ignores your prompt, add prompt weight before you add CFG.

Steps past ~40 buy you almost nothing — spend that budget on Hi-Res Fix instead.

---

## 3. Hi-Res Fix — the biggest single quality jump

Raw 1024×1024 SDXL is soft. Hi-Res Fix generates at base resolution, upscales the
latent, then runs a second denoise pass at the larger size, so the model paints in
detail that never existed in the first pass. This is not the same as upscaling
afterward in Extras — that only enlarges what's already there.

**Files:** `4x-UltraSharp.pth`, `4x_NMKD-Siax_200k.pth` → `models/ESRGAN/`
(some builds use `models/RealESRGAN/` — the script handles both).

**Apply — txt2img → Hi-Res Fix:**

- Upscaler: **4x-UltraSharp** (crisp, general purpose) or **4x_NMKD-Siax_200k** (gentler on skin)
- Upscale by: **1.5** (safe) to **2.0** (best, more VRAM)
- Hi-Res steps: **0** (means "same as sampling steps") or 15
- **Denoising strength: 0.35–0.45** ← the one that matters

Denoise below 0.3 changes nothing and wastes the pass. Above 0.55 the second pass
starts inventing new content — extra fingers, drifting faces, duplicated subjects.
0.4 is the sweet spot.

VRAM: 1024 × 2.0 = 2048px. On 8GB, use 1.5x and add `--medvram-sdxl` to
`COMMANDLINE_ARGS` in `webui-user.bat`. On 12GB+, 2x is comfortable.

---

## 4. Detail LoRAs — micro-texture injection

LoRAs are small weight patches loaded on top of the checkpoint. Detail LoRAs are
trained to push high-frequency texture (pores, thread, bark, grain) without touching
composition — so you can add them to a prompt you already like and get the same
image, sharper.

**Files:** `.safetensors` → `models/Lora/`

| LoRA | Weight | Notes |
|---|---|---|
| **Detail Tweaker XL** | 0.3 – 0.6 | Positive = more detail, negative = smoother. Try `-0.4` for clean product/graphic work. |
| **XL More Art (Full)** | 0.2 – 0.5 | Adds painterly richness. Above 0.6 it starts imposing its own style. |

**Apply:** append to the end of your positive prompt:

```
<lora:add-detail-xl:0.4>
<lora:xl_more_art-full_v1:0.3>
```

The filename inside `<lora:...>` must match the file in `models/Lora/` exactly,
minus the extension. Easiest path: click the Lora tab in the WebUI and let it
insert the tag for you.

Stacking both at low weight works well. Stacking both at 0.8 does not — you get
crunchy, over-etched skin that reads as AI immediately.

---

## 5. ADetailer — the missing piece for photoreal faces

Not in the original list, but it does more for photorealism than any LoRA. SDXL
spends its pixel budget on the whole frame, so a face occupying 8% of a 1024px
image gets ~80px of actual detail — which is why anything but a close-up portrait
comes back with a mushy, uncanny face while the rest of the image looks great.

ADetailer detects faces (and hands) after generation, crops each one, re-renders
it at full resolution, and composites it back. Half-body and full-body shots stop
falling apart.

**Install:** Extensions → Available → *Load from* → search `adetailer` → Install →
restart the WebUI. (Or Extensions → Install from URL:
`https://github.com/Bing-su/adetailer`.)

**Apply — the ADetailer panel under txt2img:**

- Enable ADetailer: ticked
- Model: `face_yolov8n.pt`
- Inpaint denoising strength: **0.4** (0.5+ and the face stops matching the body)
- Mask blur: 4, Inpaint padding: 32

Add a second unit with `hand_yolov8n.pt` if hands matter for the shot. It runs
after Hi-Res Fix, so leave both on together — they fix different problems.

---

## 6. Prompting Juggernaut for photorealism

Settings get you most of the way; prompt style covers the rest. Juggernaut v9
responds to **photographic** language, not quality-tag soup.

**Works:**

```
candid photo of a woman in a wool coat on a rainy Chicago street at dusk,
shot on Canon EOS R5, 85mm f/1.4, shallow depth of field, natural window light,
film grain, visible skin texture
```

**Backfires:** `masterpiece, best quality, 8k, ultra HD, photorealistic, hyperrealistic,
award winning, trending on artstation`. Those tags are heavily represented in
*rendered and illustrated* training data, so they pull toward CGI and digital art —
the opposite of what you're asking for.

The levers that actually read as "real photo":

| Lever | Examples |
|---|---|
| Camera + lens | `shot on Fujifilm X-T4`, `35mm`, `85mm f/1.8`, `wide angle` |
| Light source | `overcast daylight`, `golden hour backlight`, `single softbox`, `harsh midday sun` |
| Imperfection | `film grain`, `visible pores`, `slight motion blur`, `flyaway hairs`, `asymmetrical` |
| Framing | `candid`, `snapshot`, `documentary photo`, `off-center composition` |

Keep the negative prompt short. Juggernaut v9 needs very little — a long negative
fights the model and flattens output. A reasonable floor:

```
cartoon, illustration, 3d render, painting, plastic skin, airbrushed, watermark, text
```

---

## Recommended baseline

```
Checkpoint:         juggernautXL_v9Rundiffusionphoto2
Sampler:            DPM++ 2M Karras
Steps:              35
CFG:                4.0
Resolution:         1024x1024  (or 832x1216 portrait, 1216x832 landscape)
VAE:                sdxl_vae.safetensors
Hi-Res Fix:         on
  Upscaler:         4x-UltraSharp
  Upscale by:       2.0
  Hi-Res steps:     0
  Denoise:          0.4
LoRAs:              <lora:add-detail-xl:0.4>
ADetailer:          on, face_yolov8n.pt, denoise 0.4
```

**Use SDXL-native resolutions.** SDXL was trained on ~1 megapixel buckets. Asking
for 512×512 gives you worse output than 1024×1024, not faster-and-similar. Valid
sizes: 1024×1024, 1152×896, 896×1152, 1216×832, 832×1216, 1344×768, 768×1344.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Gray / washed out | Wrong or overflowing VAE | Set VAE explicitly (§1) |
| Plastic, over-contrasted | CFG too high | Drop to 4–6 |
| Soft, blurry, "smeared" | No Hi-Res Fix | Enable at 1.5–2x, denoise 0.4 |
| Duplicated limbs after Hi-Res | Denoise too high | Drop to 0.35–0.4 |
| Black image output | fp16 VAE overflow | Add `--no-half-vae` to COMMANDLINE_ARGS |
| Crunchy, over-etched skin | LoRA weight too high | Drop to 0.3–0.4, or one LoRA not two |
| OOM at 2x Hi-Res | VRAM | 1.5x, or `--medvram-sdxl` |
| LoRA tag does nothing | Filename mismatch | Insert the tag from the Lora tab |
| Mushy face in half/full-body shots | Face too small for the pixel budget | Enable ADetailer (§5) |
| Face doesn't match the body after ADetailer | Inpaint denoise too high | Drop to 0.35–0.4 |
| Output looks CGI / like a 3D render | Quality-tag soup in the prompt | Strip `8k, masterpiece, hyperrealistic` (§6) |
| Ignores the prompt | Reaching for CFG | Weight the term — `(wool coat:1.3)` — before raising CFG |
