# LU AI — Photorealism Pack for Juggernaut XL v9 (ComfyUI)

Setup notes for the local ComfyUI install launched by the **LU AI** desktop
shortcut, running **Juggernaut XL v9**.

Run `install-quality-pack.ps1` to download the VAE and upscalers into the right
places, then build the node chain in §7. No admin rights needed — see §0.

---

## 0. Where things actually live

LU AI splits across two locations, which is what makes this confusing:

| | Path |
|---|---|
| Launcher / UI shell | `C:\Program Files\Locally Uncensored` |
| **ComfyUI backend and all models** | **`C:\Users\13024\ComfyUI`** |

Everything in this guide targets the second one. It's inside your user profile,
so **no administrator rights are needed** — ignore the Program Files folder
entirely; it holds only the packaged app shell.

Your model folders:

```
C:\Users\13024\ComfyUI\models\checkpoints      <- Juggernaut XL v9 lives here
C:\Users\13024\ComfyUI\models\vae              <- §2
C:\Users\13024\ComfyUI\models\upscale_models   <- §4
C:\Users\13024\ComfyUI\models\loras            <- §5
```

> **ComfyUI's folder names are lowercase and differ from other WebUIs.** It's
> `vae`, `loras`, `upscale_models` — not `VAE`, `Lora`, `ESRGAN`. A file in the
> wrong folder doesn't error; it just never appears in the node dropdown.

Create `vae`, `upscale_models`, or `loras` if they don't exist yet — ComfyUI
picks them up on startup.

### Verified downloads

These three URLs are confirmed working (sizes as installed):

| File | Size | Folder |
|---|---|---|
| `sdxl_vae.safetensors` | 319.1 MB | `models\vae` |
| `4x-UltraSharp.pth` | 63.9 MB | `models\upscale_models` |
| `4x_NMKD-Siax_200k.pth` | 63.9 MB | `models\upscale_models` |

If a re-download ever comes back far smaller than these, it's an HTML error page,
not a model — delete it and use the fallback mirror in the installer.

**Run the installer** from a normal PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\install-quality-pack.ps1"
```

If Windows refuses to run it because it was downloaded from the internet:

```powershell
Unblock-File "$env:USERPROFILE\Desktop\install-quality-pack.ps1"
```

After any change here, **fully quit and relaunch LU AI**. A browser refresh
won't do it — model files are only scanned when the backend starts.

---

## 1. Install ComfyUI Manager (do this first)

ComfyUI ships with only base nodes. The Manager adds one-click installation for
everything else, including the face detailer in §6. Without it you're editing
folders and git-cloning by hand.

Check first — if there's a **Manager** button in the ComfyUI menu, you already
have it (most packaged builds like LU AI include it).

If not, from `C:\Users\13024\ComfyUI\custom_nodes\`:

```
git clone https://github.com/ltdrdata/ComfyUI-Manager
```

Restart ComfyUI. The **Manager** button appears in the menu panel.

---

## 2. VAE — fixes washed-out color

The VAE decodes the model's latent output into actual pixels. A mismatched or
overflowing VAE gives you the gray, milky, slightly-blown look that gets blamed
on the checkpoint.

**Juggernaut v9 has the corrected VAE baked in**, so loading it separately may
change nothing. Do it anyway — the moment you try a different checkpoint, an
explicit VAE means one less variable when output goes gray.

**File:** `sdxl_vae.safetensors` → `C:\Users\13024\ComfyUI\models\vae\`

**Nodes:** add **Load VAE**, pick `sdxl_vae.safetensors`, and run its `VAE`
output into the `vae` input of your **VAE Decode** node — replacing the wire
coming from the checkpoint loader.

To use the baked-in one instead, wire `Load Checkpoint`'s `VAE` output there.
Whichever you choose, the point is that you can see which one is connected.

---

## 3. Sampler and CFG — texture and micro-detail

In the **KSampler** node these are two separate dropdowns; ComfyUI doesn't bundle
them into one name like "DPM++ 2M Karras" does elsewhere.

| Field | Set to |
|---|---|
| `sampler_name` | **`dpmpp_2m`** |
| `scheduler` | **`karras`** |
| `steps` | **35** |
| `cfg` | **4.0** |
| `denoise` | 1.0 (first pass only — see §4) |

`dpmpp_2m` + `karras` **is** DPM++ 2M Karras. For faster iteration, `uni_pc` at
20–25 steps gives near-identical quality; re-roll keepers on `dpmpp_2m`.

**CFG is the setting most worth getting right.** Juggernaut v9 is tuned to run
low — 3 to 6. CFG 8+ burns contrast and produces exactly the plastic, over-saturated
skin that reads as AI at a glance. Start at 4. If the image ignores part of your
prompt, weight that term — `(wool coat:1.3)` — rather than raising CFG.

Steps past ~40 buy almost nothing. Spend that time on §4 instead.

---

## 4. Hi-Res Fix — the biggest single quality jump

There is **no Hi-Res Fix checkbox in ComfyUI.** It's a feature of other WebUIs
that ComfyUI expects you to build, because it's really just a second sampling
pass at a larger size — which is exactly why it works. Raw 1024×1024 SDXL is
soft; the second pass paints in detail that never existed in the first. This is
not the same as upscaling afterward, which only enlarges what's already there.

**Files:** `4x-UltraSharp.pth`, `4x_NMKD-Siax_200k.pth` → `C:\Users\13024\ComfyUI\models\upscale_models\`

**The node chain** — insert between your first KSampler and the final Save Image:

```
KSampler (pass 1)
   └─> VAE Decode ──> Upscale Image (using Model) ──> Upscale Image By ──┐
                            ▲                          (scale 0.5)       │
              Load Upscale Model                                         │
              (4x-UltraSharp.pth)                                        ▼
                                                                    VAE Encode
                                                                         │
                                                                         ▼
                                              KSampler (pass 2, denoise 0.40)
                                                                         │
                                                                         ▼
                                                    VAE Decode ──> Save Image
```

The `Upscale Image By` at **0.5** is not a mistake — the upscale model is 4x, so
1024 → 4096, and scaling back down by half lands you at 2048 (a clean 2x) while
keeping the sharpness the model added. Want 1.5x instead? Use 0.375.

**Pass-2 KSampler settings:** same sampler and CFG, steps 20–25, and
**`denoise` 0.35–0.45** — this is the number that matters. Below 0.3 the pass
does nothing and you've wasted the time. Above 0.55 it starts inventing content:
extra fingers, drifting faces, duplicated subjects. **0.4.**

Both KSamplers take the same positive and negative conditioning — wire the same
CLIP Text Encode outputs into both.

**Upscaler choice:** `4x-UltraSharp` is crisp and general-purpose;
`4x_NMKD-Siax_200k` is gentler on skin. Both are in the dropdown once installed —
swap and compare on the same seed.

**Simpler alternative:** drop an **Upscale Latent By** (scale 2.0) between the two
KSamplers and skip the decode/encode entirely. Fewer nodes, slightly softer
result. Fine while you're getting the graph working.

**VRAM:** 2048px is a real jump. If pass 2 OOMs, use 1.5x (scale 0.375), or add
`--lowvram` to the launch arguments.

---

## 5. Detail LoRAs — micro-texture injection

LoRAs are small weight patches loaded on top of the checkpoint, trained to push
high-frequency texture (pores, thread, bark, grain) without touching composition —
so you can add one to a prompt you already like and get the same image, sharper.

**Files:** the `.safetensors` files → `C:\Users\13024\ComfyUI\models\loras\`

> **`<lora:name:0.4>` tags in the prompt do nothing in ComfyUI.** That's
> Automatic1111 syntax. In ComfyUI a LoRA is a node in the graph; typed into a
> prompt box it's just ignored text. This trips up nearly everyone coming from
> another WebUI.

**Nodes:** insert **Load LoRA** between `Load Checkpoint` and your CLIP Text
Encode nodes:

```
Load Checkpoint ─ MODEL ─> Load LoRA ─ MODEL ─> KSampler
                └─ CLIP ─>          └─ CLIP ──> CLIP Text Encode (both of them)
```

Chain a second `Load LoRA` after the first to stack them.

| LoRA | strength_model / strength_clip | Notes |
|---|---|---|
| **Detail Tweaker XL** | 0.3 – 0.6 | Negative values smooth instead — try `-0.4` for clean product shots. |
| **XL More Art (Full)** | 0.2 – 0.5 | Painterly richness. Above 0.6 it imposes its own style. |

Set `strength_model` and `strength_clip` to the same value unless you have a
reason not to. Both at low weight works well; both at 0.8 gives you crunchy,
over-etched skin that reads as AI immediately.

---

## 6. FaceDetailer — the missing piece for photoreal faces

Not in your original list, but it does more for photorealism than any LoRA.
SDXL spreads its pixel budget across the whole frame, so a face occupying 8% of
a 1024px image gets ~80px of real detail — which is why anything but a close-up
comes back with a mushy, uncanny face while the rest of the shot looks great.

This is ADetailer's job in other WebUIs. **ComfyUI's equivalent is the
`FaceDetailer` node from ComfyUI-Impact-Pack**, which detects faces, re-renders
each at full resolution, and composites them back.

**Install:** Manager → **Custom Nodes Manager** → search `Impact Pack` → install
**ComfyUI-Impact-Pack** → restart ComfyUI. On first launch it downloads its
detection models; give it a minute.

**Use:** place a **FaceDetailer** node after the *final* VAE Decode, before Save
Image. It needs an image, the model, both conditionings, the vae, and a
**UltralyticsDetectorProvider** set to `bbox/face_yolov8m.pt`.

- `denoise`: **0.4** — above 0.5 the face stops matching the body
- `guide_size` 512, `max_size` 1024, `feather` 5

Run it after the Hi-Res pass, not instead of it. They fix different problems.

---

## 7. Recommended baseline

```
Checkpoint:      juggernautXL_v9Rundiffusionphoto2.safetensors
VAE:             sdxl_vae.safetensors  (via Load VAE node)
Resolution:      1024x1024 | 832x1216 portrait | 1216x832 landscape

KSampler pass 1:  dpmpp_2m / karras / 35 steps / cfg 4.0 / denoise 1.0
Upscale:          4x-UltraSharp -> Upscale Image By 0.5   (net 2x)
KSampler pass 2:  dpmpp_2m / karras / 22 steps / cfg 4.0 / denoise 0.40
FaceDetailer:     bbox/face_yolov8m.pt, denoise 0.40
LoRA:             Detail Tweaker XL @ 0.4
```

**Use SDXL-native resolutions.** SDXL was trained on ~1-megapixel buckets. Asking
for 512×512 gives worse output than 1024×1024, not faster-and-similar. Valid
sizes: 1024×1024, 1152×896, 896×1152, 1216×832, 832×1216, 1344×768, 768×1344.

Once the graph works, **Workflow → Export** and keep it. Rebuilding this by hand
every session is how people give up on ComfyUI.

---

## 8. Prompting Juggernaut for photorealism

Settings get you most of the way; prompt style covers the rest. Juggernaut v9
responds to **photographic** language, not quality-tag soup.

**Works:**

```
candid photo of a woman in a wool coat on a rainy Chicago street at dusk,
shot on Canon EOS R5, 85mm f/1.4, shallow depth of field, natural window light,
film grain, visible skin texture
```

**Backfires:** `masterpiece, best quality, 8k, ultra HD, photorealistic,
hyperrealistic, award winning, trending on artstation`. Those tags are heavily
represented in *rendered and illustrated* training data, so they pull toward CGI
and digital art — the opposite of what you're asking for.

The levers that actually read as "real photo":

| Lever | Examples |
|---|---|
| Camera + lens | `shot on Fujifilm X-T4`, `35mm`, `85mm f/1.8`, `wide angle` |
| Light source | `overcast daylight`, `golden hour backlight`, `single softbox`, `harsh midday sun` |
| Imperfection | `film grain`, `visible pores`, `slight motion blur`, `flyaway hairs`, `asymmetrical` |
| Framing | `candid`, `snapshot`, `documentary photo`, `off-center composition` |

Keep the negative short — Juggernaut v9 needs very little, and a long negative
fights the model and flattens output. A reasonable floor:

```
cartoon, illustration, 3d render, painting, plastic skin, airbrushed, watermark, text
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Download fails, "access denied" | Pointed at Program Files | Target `C:\Users\13024\ComfyUI` instead (§0) |
| Script won't run, "not digitally signed" | Windows blocked the download | `Unblock-File` on the .ps1 (§0) |
| Model not in the dropdown | Wrong folder, or ComfyUI not restarted | Check lowercase `vae` / `loras` / `upscale_models` (§0), then restart — not just refresh |
| Still not there after restart | `extra_model_paths.yaml` redirects the path | Put the file where that file points (§0) |
| Gray / washed out | Wrong VAE connected | Wire `Load VAE` into VAE Decode (§2) |
| Plastic, over-contrasted skin | CFG too high | Drop to 4 |
| Soft, blurry, "smeared" | Single-pass generation | Build the second pass (§4) |
| Duplicated limbs after pass 2 | `denoise` too high | 0.35–0.40 |
| Second pass changes nothing | `denoise` too low | Raise to 0.4 |
| Black image output | fp16 VAE overflow | Launch with `--fp32-vae` |
| `<lora:...>` tag does nothing | A1111 syntax | Use a Load LoRA node (§5) |
| Crunchy, over-etched skin | LoRA weight too high | 0.3–0.4, or one LoRA not two |
| Mushy face in half/full-body shots | Face too small for the pixel budget | FaceDetailer (§6) |
| Face doesn't match the body | FaceDetailer denoise too high | 0.35–0.40 |
| Output looks like a 3D render | Quality-tag soup | Strip `8k, masterpiece, hyperrealistic` (§8) |
| Ignores the prompt | Reaching for CFG | Weight the term — `(wool coat:1.3)` |
| OOM on pass 2 | VRAM | `Upscale Image By` 0.375, or `--lowvram` |
