# -*- coding: utf-8 -*-
"""Partner Center Store listings CSV を store-listings.json から生成。"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
WIN_DIR = SCRIPTS.parent
DEFAULT_JSON = SCRIPTS / "store-listings.json"
DEFAULT_TEMPLATE = SCRIPTS / "listing-csv-template.csv"
DEFAULT_OUT = WIN_DIR / "build" / "msix" / "listingData-9N4C1P9HZ3VV.csv"

LANG_MAP = (
    ("en-us", "en-US"),
    ("ja-jp", "ja-JP"),
    ("zh-hans", "zh-CN"),
)

ASSET_FIELD_PREFIXES = (
    "DesktopScreenshot",
    "MobileScreenshot",
    "XboxScreenshot",
    "StoreLogo",
    "PosterArt",
    "Square44x44Logo",
    "Square150x150Logo",
    "Wide310x150Logo",
    "Square310x310Logo",
    "Screenshot",
    "Image",
    "Icon",
)

COPYRIGHT = "Copyright © 2026 tomippe. All rights reserved."


def strip_foreign_assets(rows: list[list[str]], header_l: list[str]) -> None:
    """Remove sample URLs from borrowed listing templates (other apps)."""
    lang_cols = {name for _, name in LANG_MAP}
    lang_idx = [i for i, name in enumerate(header_l) if name in lang_cols]
    for row in rows:
        if not row:
            continue
        field = row[0]
        if not any(field.startswith(p) for p in ASSET_FIELD_PREFIXES):
            continue
        for i in lang_idx:
            if i < len(row) and row[i] and (
                "developer.microsoft.com" in row[i]
                or row[i].startswith("http")
            ):
                row[i] = ""


def load_store_data(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    listings = data.get("listings")
    if not isinstance(listings, dict):
        raise SystemExit(f"ERROR: missing listings in {path}")
    for key, _ in LANG_MAP:
        if key not in listings:
            raise SystemExit(f"ERROR: missing listings.{key} in {path}")
    return data


def fill_csv(
    template_path: Path,
    out_path: Path,
    listings: dict,
    *,
    desktop_screenshots: list[str] | None = None,
) -> None:
    with template_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)

    header_l = [h.strip() for h in header]
    col = {name: i for i, name in enumerate(header_l)}

    def set_lang(row: list[str], lang_col: str, value: str) -> None:
        idx = col.get(lang_col)
        if idx is None:
            return
        while len(row) <= idx:
            row.append("")
        row[idx] = value

    for row in rows:
        if not row:
            continue
        while len(row) < len(header):
            row.append("")
        field = row[0]

        if field == "Title":
            for src, dest in LANG_MAP:
                set_lang(row, dest, str(listings[src].get("title") or ""))
            continue

        if field in ("Description", "ShortDescription", "ReleaseNotes"):
            json_key = {
                "Description": "description",
                "ShortDescription": "shortDescription",
                "ReleaseNotes": "releaseNotes",
            }[field]
            for src, dest in LANG_MAP:
                set_lang(row, dest, str(listings[src].get(json_key) or ""))
            continue

        m = re.fullmatch(r"Feature(\d+)", field)
        if m:
            idx = int(m.group(1)) - 1
            for src, dest in LANG_MAP:
                feats = listings[src].get("features") or []
                set_lang(
                    row,
                    dest,
                    feats[idx] if isinstance(feats, list) and idx < len(feats) else "",
                )
            continue

        m = re.fullmatch(r"Keywords?(\d+)", field)
        if m:
            idx = int(m.group(1)) - 1
            for src, dest in LANG_MAP:
                keys = listings[src].get("keywords") or []
                set_lang(
                    row,
                    dest,
                    keys[idx] if isinstance(keys, list) and idx < len(keys) else "",
                )
            continue

        if field in (
            "CopyrightTrademarkInformation",
            "CopyrightAndTrademarkInfo",
            "Copyright",
        ):
            for _, dest in LANG_MAP:
                set_lang(row, dest, COPYRIGHT)
            continue

    strip_foreign_assets(rows, header_l)

    screenshot_names = desktop_screenshots or []
    if isinstance(screenshot_names, list):
        for n, name in enumerate(screenshot_names, start=1):
            if not name or not str(name).strip():
                continue
            want = f"DesktopScreenshot{n}"
            for row in rows:
                if row and row[0] == want:
                    for _, dest in LANG_MAP:
                        set_lang(row, dest, str(name).strip())
                    break

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", type=Path, default=DEFAULT_JSON)
    ap.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    ap.add_argument("-o", "--output", type=Path, default=DEFAULT_OUT)
    ap.add_argument(
        "--import-dir",
        type=Path,
        default=None,
        help="Partner Center Import listings folder (CSV + screenshot files)",
    )
    ap.add_argument(
        "--screenshot-src",
        type=Path,
        default=None,
        help="Source PNG for DesktopScreenshot1 (copied into --import-dir)",
    )
    args = ap.parse_args()

    if not args.json.is_file():
        print(f"ERROR: listings json not found: {args.json}", file=sys.stderr)
        return 1
    if not args.template.is_file():
        print(f"ERROR: template not found: {args.template}", file=sys.stderr)
        return 1

    data = load_store_data(args.json)
    listings = data["listings"]
    desktop_screenshots = list(data.get("desktopScreenshots") or [])

    import_dir = args.import_dir
    if import_dir is not None:
        import_dir.mkdir(parents=True, exist_ok=True)
        shot_name = "DesktopScreenshot1.png"
        if args.screenshot_src and args.screenshot_src.is_file():
            import shutil

            dest = import_dir / shot_name
            shutil.copy2(args.screenshot_src, dest)
            desktop_screenshots = [shot_name]
        fill_csv(
            args.template,
            import_dir / args.output.name,
            listings,
            desktop_screenshots=desktop_screenshots,
        )
        print(f"Import folder: {import_dir}")
        print(f"  CSV: {import_dir / args.output.name}")
        if desktop_screenshots:
            print(f"  Screenshots: {', '.join(desktop_screenshots)}")

    fill_csv(
        args.template,
        args.output,
        listings,
        desktop_screenshots=desktop_screenshots,
    )
    print(f"Listing CSV: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
