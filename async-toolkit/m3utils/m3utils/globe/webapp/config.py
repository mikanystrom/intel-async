"""Configuration constants for the globe map webapp."""

import os
import re

WEBAPP_DIR = os.path.dirname(os.path.abspath(__file__))
GLOBE_DIR = os.path.dirname(WEBAPP_DIR)

DATA_DIR = os.path.join(WEBAPP_DIR, "data")
BUILTIN_DATA_DIR = os.path.join(WEBAPP_DIR, "static", "data")

MAX_INPUT_SIZE = 50 * 1024 * 1024  # 50 MB
RENDER_TIMEOUT = 60  # seconds
MAX_SVG_WIDTH = 4096
MAX_SVG_HEIGHT = 4096

COLOR_PATTERN = re.compile(r"^(#[0-9a-fA-F]{3,8}|[a-zA-Z]{1,30}|none|transparent)$")
AIRPORT_CODE_PATTERN = re.compile(r"^[A-Za-z]{3,4}$")

# Environment variable overrides
GLOBETOOL_BIN = os.environ.get("GLOBETOOL_BIN")
TMPDIR = os.environ.get("GLOBEMAP_TMPDIR")

PROJECTIONS = {
    "equirectangular":      {"needsCenter": False, "needsParallels": False,
                             "label": "Equirectangular"},
    "mercator":             {"needsCenter": False, "needsParallels": False,
                             "label": "Mercator"},
    "transversemercator":   {"needsCenter": True,  "needsParallels": False,
                             "label": "Transverse Mercator"},
    "stereographic":        {"needsCenter": True,  "needsParallels": False,
                             "label": "Stereographic"},
    "orthographic":         {"needsCenter": True,  "needsParallels": False,
                             "label": "Orthographic"},
    "azimuthalequidistant": {"needsCenter": True,  "needsParallels": False,
                             "label": "Azimuthal Equidistant"},
    "lambertconformalconic":{"needsCenter": True,  "needsParallels": True,
                             "label": "Lambert Conformal Conic"},
    "albersequalarea":      {"needsCenter": True,  "needsParallels": True,
                             "label": "Albers Equal-Area"},
    "robinson":             {"needsCenter": False, "needsParallels": False,
                             "label": "Robinson"},
}
