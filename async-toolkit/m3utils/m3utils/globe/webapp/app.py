"""Flask application for the globe map projection tool."""

import os

from flask import Flask, jsonify, render_template, request

import config
import globetool


def create_app():
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = config.MAX_INPUT_SIZE

    @app.route("/")
    def index():
        return render_template("index.html")

    @app.route("/api/projections")
    def projections():
        return jsonify(config.PROJECTIONS)

    @app.route("/api/datasets")
    def datasets():
        result = []
        for data_dir, prefix in [
            (config.BUILTIN_DATA_DIR, "builtin:"),
            (config.DATA_DIR, "data:"),
        ]:
            if not os.path.isdir(data_dir):
                continue
            for name in sorted(os.listdir(data_dir)):
                if not name.endswith(".geojson"):
                    continue
                path = os.path.join(data_dir, name)
                size = os.path.getsize(path)
                dataset_id = prefix + name
                label = name.replace(".geojson", "").replace("_", " ").replace("-", " ").title()
                result.append({
                    "id": dataset_id,
                    "name": label,
                    "filename": name,
                    "size": size,
                })
        return jsonify(result)

    @app.route("/api/render", methods=["POST"])
    def render():
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON body required"}), 400

        # Validate projection
        projection = data.get("projection", "equirectangular")
        if projection not in config.PROJECTIONS:
            return jsonify({"error": f"Unknown projection: {projection}"}), 400

        # Validate and collect datasets
        dataset_ids = data.get("datasets", [])
        if not dataset_ids:
            return jsonify({"error": "At least one dataset is required"}), 400

        paths = []
        for ds_id in dataset_ids:
            path = _resolve_dataset(ds_id)
            if path is None:
                return jsonify({"error": f"Unknown dataset: {ds_id}"}), 400
            paths.append(path)

        # Validate colors
        stroke = data.get("stroke", "#333333")
        fill = data.get("fill", "none")
        background = data.get("background", "#ffffff")
        for color_name, color_val in [("stroke", stroke), ("fill", fill),
                                       ("background", background)]:
            if not config.COLOR_PATTERN.match(color_val):
                return jsonify({"error": f"Invalid {color_name} color: {color_val}"}), 400

        # Validate numeric params
        width = _clamp_int(data.get("width", 1024), 64, config.MAX_SVG_WIDTH)
        height = _clamp_int(data.get("height", 512), 64, config.MAX_SVG_HEIGHT)
        stroke_width = _clamp_float(data.get("strokeWidth", 0.5), 0.0, 20.0)
        point_radius = _clamp_float(data.get("pointRadius", 2.0), 0.0, 50.0)

        # Validate center
        center_lat = _clamp_float(data.get("centerLat"), -90.0, 90.0)
        center_lon = _clamp_float(data.get("centerLon"), -180.0, 180.0)

        # Validate parallels
        parallel1 = _clamp_float(data.get("parallel1"), -90.0, 90.0)
        parallel2 = _clamp_float(data.get("parallel2"), -90.0, 90.0)

        # Validate oblique
        oblique_mode = data.get("obliqueMode")
        if oblique_mode not in (None, "none", "coordinates", "airports", "pole"):
            return jsonify({"error": f"Invalid oblique mode: {oblique_mode}"}), 400
        if oblique_mode == "none":
            oblique_mode = None

        oblique_lat1 = _clamp_float(data.get("obliqueLat1"), -90.0, 90.0)
        oblique_lon1 = _clamp_float(data.get("obliqueLon1"), -180.0, 180.0)
        oblique_lat2 = _clamp_float(data.get("obliqueLat2"), -90.0, 90.0)
        oblique_lon2 = _clamp_float(data.get("obliqueLon2"), -180.0, 180.0)

        airport1 = data.get("airport1", "")
        airport2 = data.get("airport2", "")
        if oblique_mode == "airports":
            if not airport1 or not airport2:
                return jsonify({"error": "Two airport codes required"}), 400
            if not config.AIRPORT_CODE_PATTERN.match(airport1):
                return jsonify({"error": f"Invalid airport code: {airport1}"}), 400
            if not config.AIRPORT_CODE_PATTERN.match(airport2):
                return jsonify({"error": f"Invalid airport code: {airport2}"}), 400

        pole_lat = _clamp_float(data.get("poleLat"), -90.0, 90.0)
        pole_lon = _clamp_float(data.get("poleLon"), -180.0, 180.0)
        eq_lat = _clamp_float(data.get("eqLat"), -90.0, 90.0)
        eq_lon = _clamp_float(data.get("eqLon"), -180.0, 180.0)

        # Overlay options
        overlay_earth_eq = bool(data.get("overlayEarthEquator", False))
        overlay_proj_eq = bool(data.get("overlayProjEquator", False))

        # Merge datasets and render
        merged_path = None
        is_temp = False
        try:
            merged_path, is_temp = globetool.merge_geojson_files(paths)
            svg = globetool.render_svg(
                input_path=merged_path,
                projection=projection,
                center_lat=center_lat,
                center_lon=center_lon,
                parallel1=parallel1,
                parallel2=parallel2,
                oblique_mode=oblique_mode,
                oblique_lat1=oblique_lat1,
                oblique_lon1=oblique_lon1,
                oblique_lat2=oblique_lat2,
                oblique_lon2=oblique_lon2,
                airport1=airport1,
                airport2=airport2,
                pole_lat=pole_lat,
                pole_lon=pole_lon,
                eq_lat=eq_lat,
                eq_lon=eq_lon,
                width=width,
                height=height,
                stroke=stroke,
                fill=fill,
                background=background,
                stroke_width=stroke_width,
                point_radius=point_radius,
                overlay_earth_eq=overlay_earth_eq,
                overlay_proj_eq=overlay_proj_eq,
            )
            return svg, 200, {"Content-Type": "image/svg+xml"}

        except FileNotFoundError as e:
            return jsonify({"error": str(e)}), 500
        except RuntimeError as e:
            return jsonify({"error": str(e)}), 422
        except subprocess.TimeoutExpired:
            return jsonify({"error": "Render timed out"}), 504
        finally:
            if is_temp and merged_path and os.path.exists(merged_path):
                os.unlink(merged_path)

    return app


def _resolve_dataset(ds_id):
    """Resolve a dataset ID to a file path, preventing path traversal."""
    if ds_id.startswith("builtin:"):
        name = ds_id[len("builtin:"):]
        base_dir = config.BUILTIN_DATA_DIR
    elif ds_id.startswith("data:"):
        name = ds_id[len("data:"):]
        base_dir = config.DATA_DIR
    else:
        return None

    # Prevent path traversal
    if "/" in name or "\\" in name or ".." in name:
        return None
    if not name.endswith(".geojson"):
        return None

    path = os.path.join(base_dir, name)
    # Verify the resolved path is within the expected directory
    real_path = os.path.realpath(path)
    real_base = os.path.realpath(base_dir)
    if not real_path.startswith(real_base + os.sep):
        return None
    if not os.path.isfile(path):
        return None
    return path


def _clamp_int(val, lo, hi):
    if val is None:
        return None
    try:
        return max(lo, min(hi, int(val)))
    except (TypeError, ValueError):
        return lo


def _clamp_float(val, lo, hi):
    if val is None:
        return None
    try:
        return max(lo, min(hi, float(val)))
    except (TypeError, ValueError):
        return lo


if __name__ == "__main__":
    app = create_app()
    app.run(debug=True, host="127.0.0.1", port=5050)
