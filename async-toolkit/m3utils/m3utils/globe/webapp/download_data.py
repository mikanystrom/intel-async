#!/usr/bin/env python3
"""Download Natural Earth GeoJSON datasets for the globe map webapp.

Usage:
    python download_data.py              # 110m quick-start (~700KB total)
    python download_data.py --scale 50m  # 50m standard (~10MB total)
    python download_data.py --scale 10m  # 10m detailed (~50MB total)
    python download_data.py --all        # all three scales
    python download_data.py --force      # re-download existing files
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error

BASE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/"
)

DATASETS = {
    "110m": [
        "ne_110m_land.geojson",
        "ne_110m_admin_0_countries.geojson",
        "ne_110m_coastline.geojson",
        "ne_110m_lakes.geojson",
        "ne_110m_rivers_lake_centerlines.geojson",
        "ne_110m_graticules_30.geojson",
    ],
    "50m": [
        "ne_50m_land.geojson",
        "ne_50m_admin_0_countries.geojson",
        "ne_50m_coastline.geojson",
        "ne_50m_lakes.geojson",
        "ne_50m_rivers_lake_centerlines.geojson",
        "ne_50m_admin_1_states_provinces_lines.geojson",
        "ne_50m_populated_places_simple.geojson",
        "ne_50m_graticules_10.geojson",
    ],
    "10m": [
        "ne_10m_land.geojson",
        "ne_10m_admin_0_countries.geojson",
        "ne_10m_coastline.geojson",
        "ne_10m_lakes.geojson",
        "ne_10m_rivers_lake_centerlines.geojson",
        "ne_10m_admin_1_states_provinces_lines.geojson",
        "ne_10m_populated_places_simple.geojson",
        "ne_10m_airports.geojson",
        "ne_10m_ports.geojson",
        "ne_10m_geographic_lines.geojson",
        "ne_10m_graticules_10.geojson",
    ],
}

def download_file(url, dest, force=False):
    """Download a file from url to dest. Skip if exists and not force."""
    if os.path.exists(dest) and not force:
        print(f"  skip (exists): {os.path.basename(dest)}")
        return True

    print(f"  downloading: {os.path.basename(dest)} ...", end=" ", flush=True)
    try:
        urllib.request.urlretrieve(url, dest)
        size = os.path.getsize(dest)
        print(f"({size / 1024:.0f} KB)")
        return True
    except urllib.error.URLError as e:
        print(f"FAILED: {e}")
        return False


def write_manifest(data_dir, downloaded):
    """Write a manifest.json listing downloaded datasets."""
    manifest = {}
    for path in downloaded:
        name = os.path.basename(path)
        manifest[name] = {
            "size": os.path.getsize(path),
            "path": name,
        }
    manifest_path = os.path.join(data_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"\nWrote manifest: {manifest_path}")


def main():
    parser = argparse.ArgumentParser(description="Download Natural Earth datasets")
    parser.add_argument("--scale", choices=["110m", "50m", "10m"], default="110m",
                        help="Resolution scale (default: 110m)")
    parser.add_argument("--all", action="store_true",
                        help="Download all three scales")
    parser.add_argument("--force", action="store_true",
                        help="Re-download existing files")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, "data")
    os.makedirs(data_dir, exist_ok=True)

    scales = ["110m", "50m", "10m"] if args.all else [args.scale]

    downloaded = []
    failed = 0

    for scale in scales:
        files = DATASETS[scale]
        print(f"\n=== {scale} ({len(files)} files) ===")
        for filename in files:
            url = BASE_URL + filename
            dest = os.path.join(data_dir, filename)
            if download_file(url, dest, args.force):
                downloaded.append(dest)
            else:
                failed += 1

    write_manifest(data_dir, downloaded)

    if failed:
        print(f"\n{failed} download(s) failed.")
        sys.exit(1)
    else:
        print(f"\nDone. {len(downloaded)} dataset(s) ready in {data_dir}")


if __name__ == "__main__":
    main()
