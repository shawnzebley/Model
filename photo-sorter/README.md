# Photo Sorter — group photos by who's in them

Runs on your own PC. Reads your photos, finds faces, groups the same person
together, and puts each person's photos in their own folder.

Nothing is uploaded. The face models run locally; the only network use is the
one-time download of the model weights (~100 MB) on first run.

## Setup (Windows)

1. Install Python 3.10 or newer from https://python.org (tick **Add python.exe
   to PATH** during install).
2. Open PowerShell and run:

```powershell
cd path\to\photo-sorter
py -m pip install -r requirements.txt
```

The `torch` download is large (~2 GB) and takes a while the first time.

## Use it

**Step 1 — dry run.** This changes nothing; it just shows you the grouping it
found.

```powershell
py sort_photos_by_person.py "C:\Users\13024\Pictures"
```

You'll get something like:

```
Plan:
  Person_01                142 photo(s)
  Person_02                 87 photo(s)
  Person_03                 12 photo(s)
  _No Faces                 63 photo(s)
  _Unsorted                  9 photo(s)
```

**Step 2 — do it for real.**

```powershell
py sort_photos_by_person.py "C:\Users\13024\Pictures" --apply
```

Photos are **copied** into `C:\Users\13024\Pictures\Sorted by Person\Person_01\`
and so on. Your originals stay exactly where they are — check the result, then
delete the originals yourself if you're happy. Add `--move` if you'd rather
relocate them.

Then just rename `Person_01` to the actual name in File Explorer.

## Getting real names instead of Person_01

If you'd rather have the folders named up front, make a reference folder — one
subfolder per person, with 1–3 clear photos of just that person's face:

```
C:\Users\13024\Pictures\known\
    Shawn\shawn1.jpg
    Mom\mom1.jpg
    Mom\mom2.jpg
```

Then:

```powershell
py sort_photos_by_person.py "C:\Users\13024\Pictures" --known "C:\Users\13024\Pictures\known" --apply
```

Anyone without a reference still gets a `Person_NN` folder.

## Things worth knowing

- **A photo with two people is copied into both folders.** That's usually what
  you want. With `--move` it can only go to one, so it goes to the larger group.
- **`_No Faces`** — landscapes, screenshots, documents.
- **`_Unsorted`** — faces that only turned up in one photo (raise or lower with
  `--min-photos`).
- **A `.face_cache.json` file** is written in your Pictures folder so re-runs are
  fast. Safe to delete.
- **HEIC photos from an iPhone are skipped** unless you also run
  `py -m pip install pillow-heif`. (Add the extension yourself, or convert first.)

## Tuning

| Flag | Does what |
|---|---|
| `--threshold 0.42` | Lower = stricter: more folders, less chance of two people mixed together. Try `0.35` if someone's folder has a stranger in it. Try `0.50` if one person is split across several folders. |
| `--match-threshold 0.45` | How close a cluster must be to a `--known` reference to take its name. |
| `--min-photos 2` | Groups smaller than this go to `_Unsorted`. |
| `--min-confidence 0.95` | Raise to `0.98` if it's picking up faces in patterns/backgrounds. |
| `--no-recursive` | Only the top folder, don't descend into subfolders. |
| `--output "D:\Sorted"` | Write the person folders somewhere else. |
| `--device cuda` | Use an NVIDIA GPU (much faster on big libraries). |

## Expected speed

On a CPU, roughly 1–3 photos per second. A 5,000-photo library is a coffee break
or two. Re-runs after that are near-instant thanks to the cache.
