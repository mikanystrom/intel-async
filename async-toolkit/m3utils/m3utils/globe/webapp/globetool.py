"""Wrapper for the globetool CLI binary."""

import json
import os
import platform
import shutil
import subprocess
import tempfile

import config


def detect_target():
    """Return the CM3 target string for the current platform."""
    system = platform.system()
    machine = platform.machine()

    if system == "Darwin":
        if machine == "arm64":
            return "ARM64_DARWIN"
        return "AMD64_DARWIN"
    elif system == "Linux":
        if machine == "aarch64":
            return "ARM64_LINUX"
        if machine in ("i386", "i686"):
            return "I386_LINUX"
        return "AMD64_LINUX"
    elif system == "FreeBSD":
        return "AMD64_FREEBSD"
    else:
        return "AMD64_LINUX"


def find_globetool():
    """Locate the globetool binary.

    Search order:
    1. GLOBETOOL_BIN environment variable
    2. ../globetool/<TARGET>/globetool relative to webapp/
    3. globetool on PATH
    """
    if config.GLOBETOOL_BIN:
        if os.path.isfile(config.GLOBETOOL_BIN):
            return config.GLOBETOOL_BIN
        raise FileNotFoundError(
            f"GLOBETOOL_BIN set but not found: {config.GLOBETOOL_BIN}"
        )

    target = detect_target()
    relative = os.path.join(
        config.GLOBE_DIR, "globetool", target, "globetool"
    )
    if os.path.isfile(relative):
        return relative

    found = shutil.which("globetool")
    if found:
        return found

    raise FileNotFoundError(
        f"globetool binary not found. Looked in:\n"
        f"  $GLOBETOOL_BIN (not set)\n"
        f"  {relative}\n"
        f"  PATH"
    )


def merge_geojson_files(paths):
    """Merge multiple GeoJSON files into one FeatureCollection.

    Returns the path to a temporary file containing the merged data.
    The caller is responsible for deleting it.
    """
    if len(paths) == 1:
        return paths[0], False  # no temp file created

    all_features = []
    for idx, path in enumerate(paths):
        with open(path, "r") as f:
            data = json.load(f)
        if data.get("type") == "FeatureCollection":
            features = data.get("features", [])
        elif data.get("type") == "Feature":
            features = [data]
        else:
            # Bare geometry — wrap it
            features = [{"type": "Feature", "geometry": data, "properties": {}}]
        # Tag non-first datasets as secondary for lighter SVG styling
        if idx > 0:
            for feat in features:
                props = feat.get("properties") or {}
                props["_class"] = "secondary"
                feat["properties"] = props
        all_features.extend(features)

    merged = {"type": "FeatureCollection", "features": all_features}

    fd, tmp_path = tempfile.mkstemp(
        suffix=".geojson", prefix="globemap_", dir=config.TMPDIR
    )
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(merged, f)
    except Exception:
        os.unlink(tmp_path)
        raise

    return tmp_path, True


def render_svg(input_path, projection, center_lat=None, center_lon=None,
               parallel1=None, parallel2=None, oblique_mode=None,
               oblique_lat1=None, oblique_lon1=None,
               oblique_lat2=None, oblique_lon2=None,
               airport1=None, airport2=None,
               width=1024, height=512, stroke="#333333", fill="none",
               background="#ffffff", stroke_width=0.5, point_radius=2.0,
               overlay_earth_eq=False, overlay_proj_eq=False):
    """Invoke globetool and return the SVG output as a string."""

    binary = find_globetool()

    fd, output_path = tempfile.mkstemp(
        suffix=".svg", prefix="globemap_", dir=config.TMPDIR
    )
    os.close(fd)

    try:
        cmd = [
            binary,
            "-input", input_path,
            "-output", output_path,
            "-format", "svg",
            "-projection", projection,
            "-width", str(int(width)),
            "-height", str(int(height)),
            "-stroke", stroke,
            "-fill", fill,
            "-background", background,
            "-stroke-width", str(float(stroke_width)),
            "-point-radius", str(float(point_radius)),
        ]

        if center_lat is not None and center_lon is not None:
            cmd.extend(["-center", str(float(center_lat)), str(float(center_lon))])

        if parallel1 is not None and parallel2 is not None:
            cmd.extend(["-parallels", str(float(parallel1)), str(float(parallel2))])

        if oblique_mode == "coordinates":
            if all(v is not None for v in [oblique_lat1, oblique_lon1,
                                            oblique_lat2, oblique_lon2]):
                cmd.extend(["-oblique",
                            str(float(oblique_lat1)), str(float(oblique_lon1)),
                            str(float(oblique_lat2)), str(float(oblique_lon2))])
        elif oblique_mode == "airports":
            if airport1 and airport2:
                cmd.extend(["-greatcircle", airport1, airport2])

        if overlay_earth_eq:
            cmd.append("-overlay-earth-equator")
        if overlay_proj_eq:
            cmd.append("-overlay-proj-equator")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=config.RENDER_TIMEOUT,
        )

        if result.returncode != 0:
            stderr = result.stderr.strip()
            raise RuntimeError(f"globetool failed (exit {result.returncode}): {stderr}")

        with open(output_path, "r") as f:
            svg = f.read()

        return svg

    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)
