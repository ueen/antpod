#!/usr/bin/env python3
"""
Collect labelled podcast ad segments from PodcastIndex chapter data.

Episodes that have structured chapter JSON often have sponsor/ad segments
clearly labelled in chapter titles or marked with toc=false.  This script:

  1. Searches PodcastIndex for podcasts likely to have chapter data.
  2. Fetches recent episodes and checks for a chaptersUrl.
  3. Downloads the chapters JSON and finds sponsor segments.
  4. Downloads the episode audio and extracts mel-spectrogram patches.
  5. Saves ad/ and content/ .npy files ready for CNN training.

Usage:
  pip install requests librosa numpy soundfile
  export PI_KEY=<your PodcastIndex API key>
  export PI_SECRET=<your PodcastIndex API secret>
  python tools/collect_training_data.py

Output layout:
  training_data/
    ad/        episode-id_chapter-idx.npy   (labelled ad segments)
    content/   episode-id_chapter-idx.npy   (labelled content segments)
    manifest.csv                            (path, label, episode, title)
"""

import csv
import hashlib
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import requests

# ── Config ────────────────────────────────────────────────────────────────────

PI_KEY    = os.environ.get("PI_KEY",    "")
PI_SECRET = os.environ.get("PI_SECRET", "")

if not PI_KEY or not PI_SECRET:
    sys.exit("Set PI_KEY and PI_SECRET environment variables.")

SAMPLE_RATE   = 22050
N_MELS        = 128
PATCH_SECONDS = 3.0      # mel patch duration fed to CNN per window
PATCH_HOP     = 1.0      # stride between patches
MIN_AD_S      = 10.0
MAX_AD_S      = 120.0
SILENCE_DB    = -50.0    # dBFS floor for trimming extracted segments

OUT_DIR       = Path("training_data")

# Podcasts commonly known for structured chapter marking with sponsor sections.
# These are just seed queries — the script works on any podcast with chapters.
SEARCH_QUERIES = [
    "technology startup chapters sponsor",
    "science podcast chapters",
    "developer podcast sponsor chapters",
    "business interview chapters sponsor",
    "history podcast chapters sponsor",
]

SPONSOR_KEYWORDS = [
    "sponsor", "advertisement", " ad ", "promo", "commercial",
    "brought to you", "support", "partner", "message from",
]

# ── PodcastIndex API helpers ──────────────────────────────────────────────────

def _pi_headers() -> dict:
    ts = int(datetime.now().timestamp())
    h  = hashlib.sha1(f"{PI_KEY}{PI_SECRET}{ts}".encode()).hexdigest()
    return {
        "X-Auth-Date":  str(ts),
        "X-Auth-Key":   PI_KEY,
        "Authorization": h,
        "User-Agent":   "AntPod-AdDetect-DataCollector/1.0",
    }

def pi_get(path: str, **params) -> dict:
    r = requests.get(
        f"https://api.podcastindex.org/api/1.0{path}",
        params=params,
        headers=_pi_headers(),
        timeout=15,
    )
    r.raise_for_status()
    return r.json()

# ── Sponsor-chapter detection ──────────────────────────────────────────────────

def is_sponsor(chapter: dict) -> bool:
    title = (chapter.get("title") or "").lower()
    toc   = chapter.get("toc", True)
    return not toc or any(kw in title for kw in SPONSOR_KEYWORDS)

def fetch_chapters(url: str) -> list[dict]:
    try:
        r = requests.get(url, timeout=10)
        if r.status_code == 200:
            return r.json().get("chapters") or []
    except Exception:
        pass
    return []

def chapter_segments(chapters: list[dict]) -> tuple[list[tuple], list[tuple]]:
    """Return (ad_segments, content_segments) as (start, end, title) tuples."""
    ads, content = [], []
    for i, ch in enumerate(chapters):
        start = float(ch.get("startTime") or 0)
        nxt   = chapters[i + 1] if i + 1 < len(chapters) else None
        end   = float(nxt.get("startTime") or start + 60) if nxt else start + 60
        dur   = end - start
        if dur < MIN_AD_S or dur > MAX_AD_S:
            continue
        title = ch.get("title") or ""
        if is_sponsor(ch):
            ads.append((start, end, title))
        else:
            content.append((start, end, title))
    return ads, content

# ── Audio download & mel extraction ───────────────────────────────────────────

def download_audio(url: str, dest: Path) -> bool:
    if dest.exists():
        return True
    try:
        r = requests.get(url, stream=True, timeout=60)
        r.raise_for_status()
        dest.write_bytes(b"".join(r.iter_content(8192)))
        return True
    except Exception as e:
        print(f"    download failed: {e}")
        return False

def extract_patches(audio_path: Path, start_s: float, end_s: float) -> list[np.ndarray]:
    """
    Decode [start_s, end_s] from the audio file and return a list of
    (N_MELS × time_frames) log-mel spectrogram patches of PATCH_SECONDS length.
    """
    try:
        import librosa
    except ImportError:
        sys.exit("pip install librosa")

    dur = end_s - start_s
    y, _ = librosa.load(
        str(audio_path),
        sr=SAMPLE_RATE,
        offset=start_s,
        duration=dur,
        mono=True,
    )
    if len(y) < SAMPLE_RATE * 1.0:
        return []

    mel   = librosa.feature.melspectrogram(y=y, sr=SAMPLE_RATE, n_mels=N_MELS, fmax=8000)
    logm  = librosa.power_to_db(mel, ref=np.max)

    # Slice into fixed-width patches
    frames_per_patch = int(PATCH_SECONDS * SAMPLE_RATE / 512)   # hop_length=512
    frames_per_hop   = int(PATCH_HOP    * SAMPLE_RATE / 512)
    total_frames     = logm.shape[1]

    patches = []
    pos = 0
    while pos + frames_per_patch <= total_frames:
        patch = logm[:, pos:pos + frames_per_patch]
        patches.append(patch.astype(np.float32))
        pos += frames_per_hop

    return patches

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    (OUT_DIR / "ad").mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "content").mkdir(parents=True, exist_ok=True)

    manifest_path = OUT_DIR / "manifest.csv"
    manifest_rows = []

    seen_episodes: set[str] = set()
    seen_feeds:    set[str] = set()
    ad_count = content_count = 0

    for query in SEARCH_QUERIES:
        print(f"\n── Searching: {query!r}")
        try:
            feeds = pi_get("/search/byterm", q=query, max=20).get("feeds", [])
        except Exception as e:
            print(f"  search failed: {e}")
            continue

        for feed in feeds:
            feed_id = str(feed["id"])
            if feed_id in seen_feeds:
                continue
            seen_feeds.add(feed_id)
            print(f"  Podcast: {feed.get('title', feed_id)[:60]}")

            try:
                items = pi_get("/episodes/byfeedid", id=feed_id, max=50).get("items", [])
            except Exception:
                continue

            episodes_with_chapters = [ep for ep in items if ep.get("chaptersUrl")]
            if not episodes_with_chapters:
                continue

            for ep in episodes_with_chapters:
                ep_id = str(ep["id"])
                if ep_id in seen_episodes:
                    continue
                seen_episodes.add(ep_id)

                chapters  = fetch_chapters(ep["chaptersUrl"])
                ads, cont = chapter_segments(chapters)
                if not ads:
                    continue

                audio_url = ep.get("enclosureUrl", "")
                if not audio_url:
                    continue

                audio_path = OUT_DIR / f"{ep_id}.mp3"
                ep_title   = (ep.get("title") or ep_id)[:60]
                print(f"    [{ep_id}] {ep_title}")

                if not download_audio(audio_url, audio_path):
                    continue

                def save_patches(segs, label, base_idx):
                    nonlocal ad_count, content_count
                    subdir = OUT_DIR / label
                    for seg_i, (start, end, title) in enumerate(segs):
                        patches = extract_patches(audio_path, start, end)
                        for patch_i, patch in enumerate(patches):
                            fname = f"{ep_id}_{base_idx + seg_i}_{patch_i}.npy"
                            np.save(str(subdir / fname), patch)
                            manifest_rows.append({
                                "path":    f"{label}/{fname}",
                                "label":   label,
                                "episode": ep_id,
                                "title":   title,
                                "start":   round(start, 2),
                                "end":     round(end, 2),
                            })
                            if label == "ad":
                                ad_count += 1
                            else:
                                content_count += 1

                save_patches(ads,  "ad",      0)
                # Balanced negatives: 2× ad segments worth of content
                save_patches(cont[:len(ads) * 2], "content", 0)

                time.sleep(0.5)  # be polite to PodcastIndex

    # Write manifest
    if manifest_rows:
        with open(manifest_path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["path", "label", "episode", "title", "start", "end"])
            w.writeheader()
            w.writerows(manifest_rows)

    print(f"\n✓ {ad_count} ad patches, {content_count} content patches")
    print(f"  Manifest: {manifest_path}")
    print(f"  Next: python tools/train_cnn.py")


if __name__ == "__main__":
    main()
