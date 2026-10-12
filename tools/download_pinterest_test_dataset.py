#!/usr/bin/env python3
"""Build a local, source-attributed Pinterest image set for PoseCoach testing.

The downloader searches public Pinterest pins through DuckDuckGo Images, downloads
the linked pin image, removes metadata, normalizes it to JPEG and validates that
MediaPipe detects exactly one usable pose. It is resumable: accepted records are
written to manifest.csv immediately.

The images are third-party material. Keep them local and use them only for
internal testing; the repository .gitignore intentionally excludes the output.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import http.cookiejar
import io
import json
import random
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

try:
    import mediapipe as mp
    import numpy as np
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    from PIL import Image, ImageOps, UnidentifiedImageError
except ImportError as exc:
    raise SystemExit(
        "Missing image-validation dependencies. Run this script with the shared "
        "Python environment documented in testdata/README.md.\n"
        f"Import error: {exc}"
    ) from exc


USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
CSV_FIELDS = [
    "file",
    "category",
    "intended_gender",
    "intended_angle",
    "pin_url",
    "image_url",
    "title",
    "query",
    "width",
    "height",
    "pose_count",
    "sha256",
    "dhash",
]
BLOCKED_TITLE_WORDS = {
    "anime",
    "cartoon",
    "drawing",
    "illustration",
    "sketch",
    "manga",
    "couple",
    "family",
    "group",
    "wedding",
    "child",
    "children",
    "kid",
    "kids",
    "teen",
    "schoolgirl",
    "schoolboy",
    "ai",
    "ia",
    "generated",
    "midjourney",
    "virtual",
}


@dataclass(frozen=True)
class Bucket:
    category: str
    gender: str
    angle: str
    quota_at_100: int
    phrases: tuple[str, ...]

    def quota(self, limit: int) -> int:
        """Scale the 100-image plan while keeping every bucket represented."""
        if limit == 100:
            return self.quota_at_100
        category_total = 100
        raw = limit * self.quota_at_100 / category_total
        return max(1, round(raw))


def build_buckets(limit: int) -> list[tuple[Bucket, int]]:
    people = {
        "male": "young adult man in his 20s",
        "female": "young adult woman in her 20s",
    }
    styles = (
        "streetwear editorial",
        "casual fashion aesthetic",
        "modern urban fashion",
        "outdoor lifestyle fashion",
    )
    specs: list[tuple[str, str, str, int, tuple[str, ...]]] = []

    photographer_quota = {
        "male": {"ngang": 17, "duoi": 16, "tren-gan": 9, "tren-xa": 8},
        "female": {"ngang": 17, "duoi": 17, "tren-gan": 8, "tren-xa": 8},
    }
    angle_terms = {
        "ngang": ("eye level full body portrait standing", "full body pose eye level"),
        "duoi": ("low angle full body fashion portrait", "worm eye view standing portrait"),
        "tren-gan": ("high angle wide lens close fashion portrait", "high angle portrait pose"),
        "tren-xa": ("overhead high angle full body portrait", "high angle full body standing pose"),
    }
    for gender, quotas in photographer_quota.items():
        for angle, quota in quotas.items():
            phrases = tuple(
                f"{people[gender]} {term} {style}"
                for term in angle_terms[angle]
                for style in styles[:2]
            )
            specs.append(("photographer", gender, angle, quota, phrases))

    selfie_quota = {
        "male": {"ngang": 17, "duoi": 16, "tren": 17},
        "female": {"ngang": 17, "duoi": 17, "tren": 16},
    }
    selfie_terms = {
        "ngang": ("eye level selfie", "aesthetic close up selfie"),
        "duoi": ("low angle selfie blue sky", "low angle fashion selfie"),
        "tren": ("high angle selfie", "selfie from above aesthetic"),
    }
    concise_selfie_terms = {
        "ngang": (
            "aesthetic selfie",
            "close up selfie",
            "outdoor selfie",
            "casual phone selfie",
        ),
        "duoi": (
            "low angle selfie",
            "selfie from below",
            "blue sky selfie low angle",
            "looking down at camera selfie",
            "upward angle face selfie",
            "low camera selfie",
        ),
        "tren": (
            "high angle selfie",
            "selfie from above",
            "camera above head selfie",
            "looking up selfie",
            "overhead selfie portrait",
            "top angle face selfie",
        ),
    }
    for gender, quotas in selfie_quota.items():
        for angle, quota in quotas.items():
            styled_phrases = tuple(
                f"{people[gender]} {term} {style} single person"
                for term in selfie_terms[angle]
                for style in styles[:2]
            )
            subject = "man" if gender == "male" else "woman"
            concise_phrases = tuple(
                f"young adult {subject} {term}" for term in concise_selfie_terms[angle]
            )
            phrases = styled_phrases + concise_phrases
            specs.append(("selfie", gender, angle, quota, phrases))

    mirror_quota = {
        "male": {"ngang": 17, "duoi": 16, "tren": 17},
        "female": {"ngang": 17, "duoi": 17, "tren": 16},
    }
    mirror_terms = {
        "ngang": ("eye level full body mirror selfie", "mirror selfie outfit pose"),
        "duoi": ("low angle mirror selfie full body", "mirror selfie from below outfit"),
        "tren": ("high angle mirror selfie", "mirror selfie from above outfit"),
    }
    for gender, quotas in mirror_quota.items():
        for angle, quota in quotas.items():
            phrases = tuple(
                f"{people[gender]} {term} {style} single person"
                for term in mirror_terms[angle]
                for style in styles[:2]
            )
            specs.append(("mirror", gender, angle, quota, phrases))

    buckets = [
        Bucket(category, gender, angle, quota, phrases)
        for category, gender, angle, quota, phrases in specs
    ]

    if limit == 100:
        return [(bucket, bucket.quota_at_100) for bucket in buckets]

    # Largest-remainder apportionment gives each category exactly `limit` items.
    output: list[tuple[Bucket, int]] = []
    for category in ("photographer", "selfie", "mirror"):
        group = [b for b in buckets if b.category == category]
        exact = [(b, limit * b.quota_at_100 / 100) for b in group]
        assigned = {b: int(value) for b, value in exact}
        for b in group:
            if limit >= len(group) and assigned[b] == 0:
                assigned[b] = 1
        while sum(assigned.values()) < limit:
            candidate = max(
                group,
                key=lambda b: (limit * b.quota_at_100 / 100 - assigned[b], b.quota_at_100),
            )
            assigned[candidate] += 1
        while sum(assigned.values()) > limit:
            candidate = max(
                (b for b in group if assigned[b] > (1 if limit >= len(group) else 0)),
                key=lambda b: assigned[b] - limit * b.quota_at_100 / 100,
            )
            assigned[candidate] -= 1
        output.extend((b, assigned[b]) for b in group if assigned[b] > 0)
    return output


class HttpClient:
    def __init__(self, delay: float) -> None:
        self.delay = delay
        self.last_request = 0.0
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def get(
        self,
        url: str,
        *,
        accept: str = "*/*",
        attempts: int = 4,
        headers: dict[str, str] | None = None,
    ) -> bytes:
        for attempt in range(attempts):
            elapsed = time.monotonic() - self.last_request
            if elapsed < self.delay:
                time.sleep(self.delay - elapsed)
            request_headers = {
                "User-Agent": USER_AGENT,
                "Accept": accept,
                "Accept-Language": "en-US,en;q=0.8",
            }
            if headers:
                request_headers.update(headers)
            request = urllib.request.Request(url, headers=request_headers)
            try:
                with self.opener.open(request, timeout=35) as response:
                    data = response.read(16 * 1024 * 1024 + 1)
                self.last_request = time.monotonic()
                if len(data) > 16 * 1024 * 1024:
                    raise ValueError("image exceeds 16 MiB")
                return data
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
                self.last_request = time.monotonic()
                if attempt + 1 == attempts:
                    raise
                retry_after = 2 ** attempt + random.random()
                if isinstance(exc, urllib.error.HTTPError) and exc.code not in (403, 429, 500, 502, 503):
                    raise
                time.sleep(retry_after)
        raise RuntimeError("unreachable")


def pinterest_results(client: HttpClient, phrase: str, max_pages: int = 3):
    """Yield normalized public pins from Pinterest's web search resource."""
    base = "https://www.pinterest.com"
    source_url = "/search/pins/?" + urllib.parse.urlencode({"q": phrase, "rs": "typed"})
    page = client.get(base + source_url, accept="text/html")
    version_match = re.search(rb'"appVersion":"([^"]+)"', page)
    app_version = version_match.group(1).decode("ascii") if version_match else ""
    csrf = next((cookie.value for cookie in client.cookies if cookie.name == "csrftoken"), "")
    bookmark = None
    for _ in range(max_pages):
        options: dict[str, object] = {
            "article": "",
            "appliedProductFilters": "---",
            "price_max": None,
            "price_min": None,
            "query": phrase,
            "scope": "pins",
            "auto_correction_disabled": "",
            "top_pin_id": "",
            "filters": "",
            "page_size": 50,
        }
        if bookmark:
            options["bookmarks"] = [bookmark]
        data = json.dumps({"options": options, "context": {}}, separators=(",", ":"))
        api_url = base + "/resource/BaseSearchResource/get/?" + urllib.parse.urlencode(
            {"source_url": source_url, "data": data}
        )
        headers = {
            "Referer": base + source_url,
            "X-Requested-With": "XMLHttpRequest",
            "X-Pinterest-AppState": "active",
            "X-Pinterest-PWS-Handler": "www/search/[scope].js",
            "X-Pinterest-Source-Url": source_url,
        }
        if app_version:
            headers["X-App-Version"] = app_version
        if csrf:
            headers["X-CSRFToken"] = csrf
        payload = json.loads(
            client.get(api_url, accept="application/json", headers=headers).decode("utf-8")
        )
        response = payload.get("resource_response", {})
        data_payload = response.get("data", {})
        normalized = []
        for result in data_payload.get("results", []):
            pin = result.get("pin", result) if isinstance(result, dict) else {}
            pin_id = str(pin.get("id", ""))
            images = pin.get("images", {}) or {}
            original = images.get("orig", {}) or images.get("736x", {}) or {}
            image_url = str(original.get("url", ""))
            if not pin_id or not image_url:
                continue
            title = " ".join(
                str(pin.get(field, "") or "").strip()
                for field in ("title", "grid_title", "seo_alt_text", "alt_text", "description")
            ).strip()
            normalized.append(
                {
                    "url": f"{base}/pin/{pin_id}/",
                    "image": image_url,
                    "title": title,
                }
            )
        yield phrase, normalized
        next_bookmark = response.get("bookmark")
        if not next_bookmark or next_bookmark == bookmark or next_bookmark == "-end-":
            break
        bookmark = next_bookmark


def normalize_pin_url(url: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return False
    host = (parsed.hostname or "").lower()
    return (host == "pinterest.com" or host.endswith(".pinterest.com")) and "/pin/" in parsed.path


def normalized_image_urls(url: str) -> list[str]:
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return []
    if (parsed.hostname or "").lower() != "i.pinimg.com":
        return []
    clean = urllib.parse.urlunparse(parsed._replace(query="", fragment=""))
    candidates = []
    upgraded = re.sub(r"/(?:236x|474x|564x|736x)/", "/originals/", clean)
    for item in (upgraded, clean):
        if item not in candidates:
            candidates.append(item)
    return candidates


def title_allowed(title: str) -> bool:
    words = set(re.findall(r"[a-z]+", html.unescape(title).lower()))
    return not words.intersection(BLOCKED_TITLE_WORDS)


def title_matches_category(title: str, category: str) -> bool:
    lowered = html.unescape(title).lower()
    if category == "mirror":
        return "mirror" in lowered
    if category == "selfie":
        is_self_photo = "selfie" in lowered or "self photo" in lowered or "front camera" in lowered
        return is_self_photo and "mirror" not in lowered and "reflection" not in lowered
    return "selfie" not in lowered and "mirror" not in lowered


def dhash(image: Image.Image, size: int = 8) -> int:
    gray = image.convert("L").resize((size + 1, size), Image.Resampling.LANCZOS)
    get_pixels = getattr(gray, "get_flattened_data", gray.getdata)
    pixels = list(get_pixels())
    value = 0
    for row in range(size):
        offset = row * (size + 1)
        for col in range(size):
            value = (value << 1) | int(pixels[offset + col] > pixels[offset + col + 1])
    return value


def hamming(left: int, right: int) -> int:
    return (left ^ right).bit_count()


def open_and_normalize(data: bytes) -> Image.Image:
    try:
        with Image.open(io.BytesIO(data)) as source:
            source.seek(0)
            image = ImageOps.exif_transpose(source).convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise ValueError("unsupported or damaged image") from exc
    width, height = image.size
    if min(width, height) < 480:
        raise ValueError("image is smaller than 480 px on its shortest side")
    ratio = width / height
    if ratio < 0.45 or ratio > 1.8:
        raise ValueError("extreme aspect ratio")
    image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
    return image


def visible(landmark, threshold: float = 0.45) -> bool:
    visibility = getattr(landmark, "visibility", 1.0) or 0.0
    presence = getattr(landmark, "presence", 1.0) or 0.0
    return visibility >= threshold and presence >= threshold


def pose_is_usable(result, category: str) -> tuple[bool, int]:
    poses = result.pose_landmarks
    if len(poses) != 1:
        return False, len(poses)
    points = poses[0]
    head = visible(points[0]) or visible(points[7]) or visible(points[8])
    shoulders = visible(points[11]) and visible(points[12])
    hips = visible(points[23]) or visible(points[24])
    if not head or not shoulders:
        return False, 1
    if category in ("photographer", "mirror") and not hips:
        return False, 1
    if category == "selfie":
        # App selfie templates are head/upper-body crops. Full-body fashion
        # portraits are a common search false positive and belong to photographer.
        visible_lower_legs = sum(visible(points[i], 0.50) for i in (25, 26, 27, 28, 29, 30, 31, 32))
        if visible_lower_legs >= 2:
            return False, 1
    visible_points = [p for p in points if visible(p, 0.35) and -0.15 <= p.x <= 1.15 and -0.15 <= p.y <= 1.15]
    if len(visible_points) < (12 if category == "selfie" else 18):
        return False, 1
    span = max(p.y for p in visible_points) - min(p.y for p in visible_points)
    minimum_span = 0.20 if category == "selfie" else 0.34
    if span < minimum_span:
        return False, 1
    if category == "photographer":
        knees_or_ankles = sum(visible(points[i], 0.35) for i in (25, 26, 27, 28))
        if knees_or_ankles < 2:
            return False, 1
    return True, 1


def filename_for(bucket: Bucket, number: int) -> str:
    prefix = bucket.angle
    if bucket.category == "selfie":
        prefix = f"selfie-{prefix}"
    elif bucket.category == "mirror":
        prefix = f"mirror-{prefix}"
    return f"{prefix}-test-{bucket.gender}-{number:03d}.jpg"


def read_manifest(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_record(path: Path, record: dict[str, object]) -> None:
    exists = path.exists() and path.stat().st_size > 0
    with path.open("a", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=CSV_FIELDS)
        if not exists:
            writer.writeheader()
        writer.writerow(record)


def write_notice(output: Path) -> None:
    text = """# Pinterest test dataset

This directory contains third-party images downloaded from public Pinterest pins.
They are retained locally for internal PoseCoach quality testing only. They are not
licensed for redistribution, production bundling, marketing, or model training.

`manifest.csv` records the source pin and image URL for every file. Review the
rights and obtain permission from each rights holder before any use beyond internal
testing. Delete a file by its manifest row if its source becomes unavailable or its
owner requests removal.
"""
    (output / "LICENSE-NOTICE.md").write_text(text, encoding="utf-8")


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=repo / "testdata" / "pinterest-posecoach",
        help="Local output directory (default: testdata/pinterest-posecoach)",
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=repo / "myposecoach1" / "myposecoach1" / "pose_landmarker_full.task",
        help="MediaPipe Pose Landmarker model",
    )
    parser.add_argument(
        "--limit-per-category",
        type=int,
        default=100,
        help="Number of accepted images for each top-level photo type",
    )
    parser.add_argument("--request-delay", type=float, default=0.35)
    parser.add_argument("--max-pages-per-query", type=int, default=3)
    parser.add_argument("--seed", type=int, default=20261010)
    parser.add_argument(
        "--fresh",
        action="store_true",
        help="Remove the existing generated dataset before starting",
    )
    args = parser.parse_args()
    if args.limit_per_category < 1:
        parser.error("--limit-per-category must be positive")
    if not args.model.is_file():
        parser.error(f"pose model not found: {args.model}")

    output = args.output.resolve()
    if args.fresh and output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    for category in ("photographer", "selfie", "mirror"):
        (output / category).mkdir(exist_ok=True)
    write_notice(output)
    manifest_path = output / "manifest.csv"
    existing = read_manifest(manifest_path)
    existing = [row for row in existing if (output / row.get("file", "")).is_file()]
    counts = Counter((row["category"], row["intended_gender"], row["intended_angle"]) for row in existing)
    used_pin_urls = {row["pin_url"] for row in existing}
    used_image_urls = {row["image_url"] for row in existing}
    hashes = {row["sha256"] for row in existing}
    perceptual_hashes = [int(row["dhash"], 16) for row in existing if row.get("dhash")]

    # Keep generated images distinct from the app's current templates as well.
    template_dir = repo / "myposecoach1" / "myposecoach1" / "templates"
    for path in template_dir.glob("*.jpg"):
        try:
            with Image.open(path) as template:
                perceptual_hashes.append(dhash(ImageOps.exif_transpose(template).convert("RGB")))
        except OSError:
            pass

    random.seed(args.seed)
    client = HttpClient(max(0.1, args.request_delay))
    base_options = mp_python.BaseOptions(model_asset_path=str(args.model.resolve()))
    options = vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.IMAGE,
        num_poses=2,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    rejected = Counter()
    accepted_this_run = 0

    print(f"Output: {output}", flush=True)
    print(f"Existing accepted images: {len(existing)}", flush=True)
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        for bucket, target in build_buckets(args.limit_per_category):
            key = (bucket.category, bucket.gender, bucket.angle)
            current = counts[key]
            if current >= target:
                print(f"SKIP {key}: {current}/{target}", flush=True)
                continue
            print(f"BUCKET {key}: {current}/{target}", flush=True)
            phrases = list(bucket.phrases)
            random.shuffle(phrases)
            exhausted = True
            for phrase in phrases:
                try:
                    pages = pinterest_results(client, phrase, args.max_pages_per_query)
                    for query, results in pages:
                        random.shuffle(results)
                        for item in results:
                            if counts[key] >= target:
                                exhausted = False
                                break
                            pin_url = str(item.get("url", ""))
                            image_url = str(item.get("image", ""))
                            title = html.unescape(str(item.get("title", ""))).strip()
                            if not normalize_pin_url(pin_url) or pin_url in used_pin_urls:
                                rejected["pin/source"] += 1
                                continue
                            candidates = normalized_image_urls(image_url)
                            if (
                                not candidates
                                or image_url in used_image_urls
                                or not title_allowed(title)
                                or not title_matches_category(title, bucket.category)
                            ):
                                rejected["url/title"] += 1
                                continue
                            data = None
                            final_url = None
                            for candidate in candidates:
                                try:
                                    data = client.get(candidate, accept="image/avif,image/webp,image/*,*/*;q=0.8")
                                    final_url = candidate
                                    break
                                except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError):
                                    continue
                            if data is None or final_url is None:
                                rejected["download"] += 1
                                continue
                            digest = hashlib.sha256(data).hexdigest()
                            if digest in hashes:
                                rejected["exact duplicate"] += 1
                                continue
                            try:
                                image = open_and_normalize(data)
                            except ValueError:
                                rejected["image quality"] += 1
                                continue
                            image_hash = dhash(image)
                            if any(hamming(image_hash, old) <= 4 for old in perceptual_hashes):
                                rejected["visual duplicate"] += 1
                                continue
                            array = np.asarray(image)
                            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=array)
                            try:
                                pose_result = landmarker.detect(mp_image)
                            except (RuntimeError, ValueError):
                                rejected["pose error"] += 1
                                continue
                            usable, pose_count = pose_is_usable(pose_result, bucket.category)
                            if not usable:
                                rejected[f"pose count/coverage ({pose_count})"] += 1
                                continue

                            next_number = 1
                            relative = Path(bucket.category) / filename_for(bucket, next_number)
                            destination = output / relative
                            while destination.exists():
                                next_number += 1
                                relative = Path(bucket.category) / filename_for(bucket, next_number)
                                destination = output / relative
                            image.save(destination, "JPEG", quality=90, optimize=True, progressive=True)
                            normalized_digest = hashlib.sha256(destination.read_bytes()).hexdigest()
                            record = {
                                "file": relative.as_posix(),
                                "category": bucket.category,
                                "intended_gender": bucket.gender,
                                "intended_angle": bucket.angle,
                                "pin_url": pin_url,
                                "image_url": final_url,
                                "title": title,
                                "query": query,
                                "width": image.width,
                                "height": image.height,
                                "pose_count": pose_count,
                                "sha256": normalized_digest,
                                "dhash": f"{image_hash:016x}",
                            }
                            write_record(manifest_path, record)
                            counts[key] += 1
                            accepted_this_run += 1
                            used_pin_urls.add(pin_url)
                            used_image_urls.add(image_url)
                            hashes.add(normalized_digest)
                            perceptual_hashes.append(image_hash)
                            category_count = sum(value for k, value in counts.items() if k[0] == bucket.category)
                            print(
                                f"ACCEPT {relative.as_posix()} | category {category_count}/{args.limit_per_category}",
                                flush=True,
                            )
                        if counts[key] >= target:
                            exhausted = False
                            break
                except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, json.JSONDecodeError) as exc:
                    print(f"WARN search failed for {phrase!r}: {exc}", file=sys.stderr, flush=True)
                if counts[key] >= target:
                    exhausted = False
                    break
            if exhausted and counts[key] < target:
                print(
                    f"WARN bucket {key} exhausted at {counts[key]}/{target}",
                    file=sys.stderr,
                    flush=True,
                )

    totals = Counter()
    for (category, _gender, _angle), value in counts.items():
        totals[category] += value
    print("\nAccepted totals:", flush=True)
    for category in ("photographer", "selfie", "mirror"):
        print(f"  {category}: {totals[category]}/{args.limit_per_category}", flush=True)
    print(f"Accepted this run: {accepted_this_run}", flush=True)
    if rejected:
        print("Rejected candidates:", flush=True)
        for reason, value in rejected.most_common():
            print(f"  {reason}: {value}", flush=True)
    return 0 if all(totals[category] >= args.limit_per_category for category in totals) and len(totals) == 3 else 2


if __name__ == "__main__":
    raise SystemExit(main())
