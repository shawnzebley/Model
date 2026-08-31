"""Sort photos into per-person folders using face detection + clustering.

Runs entirely on your own machine. Nothing is uploaded anywhere.

Typical use on Windows:

    py -m pip install -r requirements.txt
    py sort_photos_by_person.py "C:\\Users\\13024\\Pictures"                  # dry run
    py sort_photos_by_person.py "C:\\Users\\13024\\Pictures" --apply          # actually copy

See README.md for the full walkthrough.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from collections import defaultdict
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}
CACHE_NAME = ".face_cache.json"
NO_FACE_DIR = "_No Faces"
UNREADABLE_DIR = "_Unreadable"


# --------------------------------------------------------------------------
# Model loading (imports are deferred so --help works without torch installed)
# --------------------------------------------------------------------------

def load_models(device: str):
    import torch
    from facenet_pytorch import MTCNN, InceptionResnetV1

    if device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")

    detector = MTCNN(
        image_size=160,
        margin=14,
        min_face_size=40,
        keep_all=True,
        post_process=True,
        device=device,
    )
    embedder = InceptionResnetV1(pretrained="vggface2").eval().to(device)
    return detector, embedder, device


# --------------------------------------------------------------------------
# Scanning
# --------------------------------------------------------------------------

def find_images(root: Path, recursive: bool, skip_dirs: set[str]) -> list[Path]:
    files: list[Path] = []
    walker = os.walk(root) if recursive else [(str(root), [], os.listdir(root))]
    for dirpath, dirnames, filenames in walker:
        dirnames[:] = [d for d in dirnames if d not in skip_dirs and not d.startswith(".")]
        for name in filenames:
            if Path(name).suffix.lower() in IMAGE_EXTS:
                files.append(Path(dirpath) / name)
    return sorted(files)


def file_key(path: Path) -> str:
    st = path.stat()
    raw = f"{path.resolve()}|{st.st_size}|{int(st.st_mtime)}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


# --------------------------------------------------------------------------
# Embedding
# --------------------------------------------------------------------------

def embed_image(path: Path, detector, embedder, device, min_confidence: float):
    """Return a list of 512-d face embeddings for one image."""
    import numpy as np
    import torch
    from PIL import Image, ImageOps

    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        # Big images slow detection down without helping accuracy much.
        im.thumbnail((1600, 1600))
        faces, probs = detector(im, return_prob=True)

    if faces is None:
        return []
    if faces.ndim == 3:  # single face comes back unbatched
        faces = faces.unsqueeze(0)
        probs = [probs]

    keep = [i for i, p in enumerate(probs) if p is not None and p >= min_confidence]
    if not keep:
        return []

    with torch.no_grad():
        batch = faces[keep].to(device)
        vecs = embedder(batch).cpu().numpy()

    vecs = vecs / np.linalg.norm(vecs, axis=1, keepdims=True)
    return [v.astype(float).tolist() for v in vecs]


def build_index(images, detector, embedder, device, cache_path: Path, min_confidence: float):
    cache = {}
    if cache_path.exists():
        try:
            cache = json.loads(cache_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            print("Cache unreadable, starting fresh.")

    index: dict[str, list] = {}
    unreadable: list[Path] = []
    total = len(images)

    for n, path in enumerate(images, 1):
        try:
            key = file_key(path)
        except OSError:
            unreadable.append(path)
            continue

        if key in cache:
            index[str(path)] = cache[key]
        else:
            try:
                vecs = embed_image(path, detector, embedder, device, min_confidence)
            except Exception as exc:  # a corrupt or exotic file shouldn't stop the run
                print(f"  ! skipping {path.name}: {exc}")
                unreadable.append(path)
                continue
            cache[key] = vecs
            index[str(path)] = vecs

        if n % 25 == 0 or n == total:
            print(f"  scanned {n}/{total}")
        if n % 200 == 0:
            cache_path.write_text(json.dumps(cache), encoding="utf-8")

    cache_path.write_text(json.dumps(cache), encoding="utf-8")
    return index, unreadable


# --------------------------------------------------------------------------
# Known faces (optional naming)
# --------------------------------------------------------------------------

def load_known_faces(known_dir: Path, detector, embedder, device, min_confidence: float):
    """known_dir/<Person Name>/*.jpg -> one averaged embedding per person."""
    import numpy as np

    people: dict[str, list] = {}
    if not known_dir.is_dir():
        return people

    for person_dir in sorted(p for p in known_dir.iterdir() if p.is_dir()):
        vecs = []
        for img in sorted(person_dir.iterdir()):
            if img.suffix.lower() not in IMAGE_EXTS:
                continue
            try:
                found = embed_image(img, detector, embedder, device, min_confidence)
            except Exception as exc:
                print(f"  ! reference {img.name}: {exc}")
                continue
            if len(found) != 1:
                print(f"  ! {img.name}: expected exactly 1 face, found {len(found)} — skipped")
                continue
            vecs.append(found[0])
        if vecs:
            mean = np.mean(np.array(vecs), axis=0)
            people[person_dir.name] = (mean / np.linalg.norm(mean)).tolist()
            print(f"  reference: {person_dir.name} ({len(vecs)} photo(s))")
    return people


# --------------------------------------------------------------------------
# Clustering
# --------------------------------------------------------------------------

def cluster_faces(index, threshold: float):
    """Agglomerative clustering over all face embeddings.

    Returns (labels, face_owners) where face_owners[i] is the image path of face i.
    """
    import numpy as np
    from sklearn.cluster import AgglomerativeClustering

    vectors, owners = [], []
    for path, vecs in index.items():
        for v in vecs:
            vectors.append(v)
            owners.append(path)

    if not vectors:
        return [], []
    if len(vectors) == 1:
        return [0], owners

    model = AgglomerativeClustering(
        n_clusters=None,
        distance_threshold=threshold,
        metric="cosine",
        linkage="average",
    )
    labels = model.fit_predict(np.array(vectors))
    return labels.tolist(), owners


def name_clusters(labels, owners, index, known, match_threshold: float):
    """Give each cluster a folder name, borrowing names from reference photos."""
    import numpy as np

    vectors = [v for path in index for v in index[path]]
    by_cluster: dict[int, list[int]] = defaultdict(list)
    for i, lab in enumerate(labels):
        by_cluster[lab].append(i)

    # Biggest clusters get the lowest numbers, so Person_01 is the most common face.
    order = sorted(by_cluster, key=lambda c: -len(by_cluster[c]))
    known_names = list(known)
    known_matrix = np.array([known[n] for n in known_names]) if known_names else None

    names: dict[int, str] = {}
    used: set[str] = set()
    for rank, cluster in enumerate(order, 1):
        centroid = np.mean(np.array([vectors[i] for i in by_cluster[cluster]]), axis=0)
        centroid /= np.linalg.norm(centroid)

        label = None
        if known_matrix is not None:
            sims = known_matrix @ centroid
            best = int(np.argmax(sims))
            if 1 - sims[best] <= match_threshold and known_names[best] not in used:
                label = known_names[best]
                used.add(label)

        if label is None:
            label = f"Person_{rank:02d}"
        names[cluster] = label

    return names, by_cluster


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def safe_dest(dest_dir: Path, src: Path) -> Path:
    dest = dest_dir / src.name
    stem, suffix = src.stem, src.suffix
    n = 2
    while dest.exists():
        dest = dest_dir / f"{stem} ({n}){suffix}"
        n += 1
    return dest


def place(src: Path, dest_dir: Path, move: bool, apply: bool) -> Path:
    dest = safe_dest(dest_dir, src)
    if apply:
        dest_dir.mkdir(parents=True, exist_ok=True)
        if move:
            shutil.move(str(src), str(dest))
        else:
            shutil.copy2(str(src), str(dest))
    return dest


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Sort photos into folders by who appears in them.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("source", type=Path, help="folder of photos to sort")
    ap.add_argument("-o", "--output", type=Path, default=None,
                    help="where the person folders go (default: <source>/Sorted by Person)")
    ap.add_argument("--apply", action="store_true",
                    help="actually copy/move files (without this it only reports the plan)")
    ap.add_argument("--move", action="store_true",
                    help="move instead of copy — note a photo with 2 people can only land in one folder")
    ap.add_argument("--known", type=Path, default=None,
                    help="folder of <Person Name>/photo.jpg references, to name clusters")
    ap.add_argument("--threshold", type=float, default=0.42,
                    help="cluster distance cutoff; lower = stricter, more folders")
    ap.add_argument("--match-threshold", type=float, default=0.45,
                    help="cutoff for matching a cluster to a --known reference")
    ap.add_argument("--min-confidence", type=float, default=0.95,
                    help="minimum face-detection confidence")
    ap.add_argument("--min-photos", type=int, default=2,
                    help="clusters smaller than this go to _Unsorted instead of their own folder")
    ap.add_argument("--no-recursive", action="store_true", help="do not descend into subfolders")
    ap.add_argument("--device", default="auto", choices=["auto", "cpu", "cuda"])
    args = ap.parse_args()

    source: Path = args.source.expanduser()
    if not source.is_dir():
        print(f"Not a folder: {source}", file=sys.stderr)
        return 1

    output: Path = (args.output or source / "Sorted by Person").expanduser()
    if args.move and not args.apply:
        print("Note: --move has no effect during a dry run.\n")

    skip_dirs = {output.name, NO_FACE_DIR, UNREADABLE_DIR, "_Unsorted"}
    print(f"Scanning {source} ...")
    images = find_images(source, not args.no_recursive, skip_dirs)
    if not images:
        print("No images found.")
        return 0
    print(f"Found {len(images)} image(s).\n")

    detector, embedder, device = load_models(args.device)

    known = {}
    if args.known:
        print("\nReading reference faces...")
        known = load_known_faces(args.known.expanduser(), detector, embedder, device,
                                 args.min_confidence)
        if not known:
            print("  (no usable references found)")

    print("\nDetecting faces...")
    index, unreadable = build_index(images, detector, embedder, device,
                                    source / CACHE_NAME, args.min_confidence)

    faces_total = sum(len(v) for v in index.values())
    print(f"\n{faces_total} face(s) across {sum(1 for v in index.values() if v)} photo(s).")

    print("Grouping faces...")
    labels, owners = cluster_faces(index, args.threshold)
    names, by_cluster = name_clusters(labels, owners, index, known, args.match_threshold)

    # Which photos belong to which person folder.
    plan: dict[str, set[str]] = defaultdict(set)
    for i, lab in enumerate(labels):
        cluster_size = len({owners[j] for j in by_cluster[lab]})
        folder = names[lab] if cluster_size >= args.min_photos else "_Unsorted"
        plan[folder].add(owners[i])

    for path, vecs in index.items():
        if not vecs:
            plan[NO_FACE_DIR].add(path)
    for path in unreadable:
        plan[UNREADABLE_DIR].add(str(path))

    print("\nPlan:")
    for folder in sorted(plan, key=lambda f: (f.startswith("_"), -len(plan[f]), f)):
        print(f"  {folder:<24} {len(plan[folder])} photo(s)")

    if args.move:
        # A photo can only be moved once; give it to the largest group it belongs to.
        claimed: dict[str, str] = {}
        for folder in sorted(plan, key=lambda f: (f.startswith("_"), -len(plan[f]), f)):
            for path in plan[folder]:
                claimed.setdefault(path, folder)
        plan = defaultdict(set)
        for path, folder in claimed.items():
            plan[folder].add(path)

    if not args.apply:
        print(f"\nDry run — nothing was changed. Re-run with --apply to write into {output}")
        return 0

    print(f"\n{'Moving' if args.move else 'Copying'} into {output} ...")
    written = 0
    for folder, paths in plan.items():
        for path in sorted(paths):
            src = Path(path)
            if not src.exists():
                continue
            place(src, output / folder, args.move, apply=True)
            written += 1
    print(f"Done. {written} file(s) written.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
