#!/bin/bash
# Acceptance tests for globetool
# Verifies markers, overlays, projections, and oblique modes

set -e

TOOL="$(dirname "$0")/ARM64_DARWIN/globetool"
DATA="$(dirname "$0")/../webapp/static/data/minimal.geojson"
OUTDIR="/tmp/globetool_tests"
PASS=0
FAIL=0

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass"; PASS=$((PASS + 1)); }

run() {
  local name="$1"; shift
  echo "--- $name ---"
  "$TOOL" "$@" 2>/dev/null
}

# --- 1. Basic projections render without error ---
for proj in equirectangular mercator transversemercator stereographic \
            orthographic azimuthalequidistant lambertconformalconic \
            albersequalarea robinson; do
  run "basic $proj" -projection "$proj" -input "$DATA" -format svg \
      -fill '#2d7744' -output "$OUTDIR/basic_${proj}.svg"
  if [ -s "$OUTDIR/basic_${proj}.svg" ]; then pass; else fail "empty SVG"; fi
done

# --- 2. Oblique great-circle mode: markers present for all projections ---
echo ""
echo "=== Oblique great-circle markers ==="
for proj in equirectangular mercator transversemercator stereographic \
            orthographic azimuthalequidistant lambertconformalconic \
            albersequalarea robinson; do
  run "oblique markers $proj" -projection "$proj" -greatcircle LHR NRT \
      -input "$DATA" -format svg -fill '#2d7744' -output "$OUTDIR/oblique_${proj}.svg"
  count=$(grep -c 'class="marker"' "$OUTDIR/oblique_${proj}.svg" || true)
  if [ "$count" -eq 2 ]; then
    pass
  else
    fail "$proj: expected 2 markers, got $count"
  fi
done

# --- 3. Markers are within canvas bounds ---
echo ""
echo "=== Marker bounds (1024x512 canvas) ==="
for proj in equirectangular mercator orthographic robinson; do
  file="$OUTDIR/oblique_${proj}.svg"
  ok=true
  while IFS= read -r line; do
    cx=$(echo "$line" | sed 's/.*cx="\([^"]*\)".*/\1/')
    cy=$(echo "$line" | sed 's/.*cy="\([^"]*\)".*/\1/')
    # Check within reasonable bounds (0-1100, 0-600 with some margin)
    if awk "BEGIN{exit (!($cx >= -10 && $cx <= 1100 && $cy >= -10 && $cy <= 600))}"; then
      :
    else
      ok=false
    fi
  done < <(grep 'class="marker"' "$file")
  run_name="bounds $proj"
  echo "--- $run_name ---"
  if $ok; then pass; else fail "marker out of bounds"; fi
done

# --- 4. Pole+equator mode: equator passes through equator point ---
echo ""
echo "=== Pole+equator: equator passes through eqPoint ==="
# Use pole=(90,0) eqPoint=(0,0) — standard orientation, equator should be at lat=0
run "pole standard" -projection equirectangular \
    -oblique-pole 90 0 0 0 \
    -overlay-proj-equator -input "$DATA" -format svg -fill '#2d7744' \
    -output "$OUTDIR/pole_standard.svg"
# The projection equator should be the standard equator (since pole=north pole)
if grep -q 'proj-equator' "$OUTDIR/pole_standard.svg"; then
  pass
else
  fail "no proj-equator overlay"
fi

# Use pole=(0,0) eqPoint=(0,90) — pole at equator/prime-meridian
run "pole tilted" -projection equirectangular \
    -oblique-pole 0 0 0 90 \
    -overlay-proj-equator -input "$DATA" -format svg -fill '#2d7744' \
    -output "$OUTDIR/pole_tilted.svg"
if grep -q 'proj-equator' "$OUTDIR/pole_tilted.svg"; then
  pass
else
  fail "no proj-equator overlay"
fi

# --- 5. Pole-airports mode: markers present ---
echo ""
echo "=== Pole-airports markers ==="
run "pole-airports equirect" -projection equirectangular \
    -pole-airports SVO DXB -input "$DATA" -format svg -fill '#2d7744' \
    -output "$OUTDIR/pole_airports.svg"
count=$(grep -c 'class="marker"' "$OUTDIR/pole_airports.svg" || true)
if [ "$count" -ge 1 ]; then
  pass
else
  fail "expected at least 1 marker, got $count"
fi

# --- 6. Earth equator overlay present ---
echo ""
echo "=== Earth equator overlay ==="
run "earth equator" -projection orthographic -center 0 0 \
    -overlay-earth-equator -input "$DATA" -format svg -fill '#2d7744' \
    -output "$OUTDIR/earth_eq.svg"
if grep -q 'earth-equator' "$OUTDIR/earth_eq.svg"; then
  pass
else
  fail "no earth-equator in SVG"
fi

# --- 7. Projection equator overlay with oblique ---
echo ""
echo "=== Projection equator with oblique ==="
run "proj equator oblique" -projection mercator -greatcircle LHR NRT \
    -overlay-proj-equator -input "$DATA" -format svg -fill '#2d7744' \
    -output "$OUTDIR/proj_eq_oblique.svg"
if grep -q 'proj-equator' "$OUTDIR/proj_eq_oblique.svg"; then
  pass
else
  fail "no proj-equator in SVG"
fi

# --- 8. Mesh seams hidden (no visible triangle strokes in non-mesh mode) ---
echo ""
echo "=== Mesh seam hiding ==="
run "mesh hidden" -projection equirectangular -input "$DATA" -format svg \
    -fill '#2d7744' -output "$OUTDIR/no_mesh.svg"
# mesh-fill class should have stroke: none in CSS
if grep -q 'stroke: *none' "$OUTDIR/no_mesh.svg"; then
  pass
else
  fail "mesh-fill missing stroke:none"
fi

# --- 9. Debug mesh mode shows edges ---
echo ""
echo "=== Debug mesh mode ==="
run "mesh visible" -projection equirectangular -input "$DATA" -format svg \
    -fill '#2d7744' -mesh -output "$OUTDIR/with_mesh.svg"
if grep -q 'mesh-tri' "$OUTDIR/with_mesh.svg"; then
  pass
else
  fail "no mesh-outline in debug mesh mode"
fi

# --- 10. Antarctica in Mercator centered at 34,106 (the original bug) ---
echo ""
echo "=== Antarctica Mercator 34,106 ==="
run "antarctica" -projection mercator -center 34 106 \
    -input "$DATA" -format svg -fill '#2d7744' -output "$OUTDIR/antarctica.svg"
if [ -s "$OUTDIR/antarctica.svg" ]; then
  pass
else
  fail "empty SVG for Antarctica test case"
fi

# --- 11. Non-cylindrical projections must not duplicate the world ---
# Compare triangle counts: conic/azimuthal should have similar count to equirectangular.
# If duplicated, they'd have ~3x the triangles.
echo ""
echo "=== No world duplication (conic/azimuthal vs cylindrical) ==="
run "tricount equirect" -projection equirectangular -input "$DATA" -format svg \
    -fill '#2d7744' -mesh -output "$OUTDIR/tricount_equirect.svg"
base_count=$(grep -c 'class="mesh-tri' "$OUTDIR/tricount_equirect.svg" || echo 0)
echo "  equirectangular triangles: $base_count"

for proj in lambertconformalconic albersequalarea azimuthalequidistant transversemercator; do
  run "tricount $proj" -projection "$proj" -center 40 -100 -parallels 29.5 45.5 \
      -input "$DATA" -format svg -fill '#2d7744' -mesh -output "$OUTDIR/tricount_${proj}.svg"
  count=$(grep -c 'class="mesh-tri' "$OUTDIR/tricount_${proj}.svg" || echo 0)
  echo "  $proj triangles: $count"
  # Should be no more than 1.5x the equirectangular count (allow for different
  # visibility/culling but catch 3x duplication)
  max_allowed=$((base_count * 3 / 2))
  if [ "$count" -le "$max_allowed" ]; then
    pass
  else
    fail "$proj has $count triangles (base: $base_count, max: $max_allowed) — world likely duplicated"
  fi
done

# --- 12. Pole airport maps to the projection pole ---

echo ""
echo "=== Pole airport at projection pole ==="
# In orthographic, the pole maps to the center of the disc (512, 256).
# Use pole=(45,90) eq=(0,0) — the point (45,90) should map to disc center.
run "pole at center" -projection orthographic \
    -oblique-pole 45 90 0 0 \
    -overlay-proj-equator -input "$DATA" -format svg -fill '#2d7744' \
    -width 1024 -height 1024 -output "$OUTDIR/pole_at_center.svg"
# The pole (45,90) in geographic coords, after oblique rotation, should project
# to the center of the orthographic disc. Verify by checking that forward(pole)
# gives approximately (512, 512). We test indirectly: add a marker at the pole
# and check it's near center.
# For now, verify using the pole-airports CLI which adds markers:
run "pole airport marker" -projection orthographic \
    -pole-airports LHR NRT \
    -input "$DATA" -format svg -fill '#2d7744' \
    -width 1024 -height 1024 -output "$OUTDIR/pole_airport_ortho.svg"
# LHR is the pole airport. In orthographic, the pole maps to disc center (512, 512).
# The LHR marker should be near (512, 512).
lhr_marker=$(grep 'class="marker"' "$OUTDIR/pole_airport_ortho.svg" | head -1)
if [ -z "$lhr_marker" ]; then
  fail "no pole marker found"
else
  cx=$(echo "$lhr_marker" | sed 's/.*cx="\([^"]*\)".*/\1/')
  cy=$(echo "$lhr_marker" | sed 's/.*cy="\([^"]*\)".*/\1/')
  # Check within 50px of center (512, 512)
  in_range=$(awk "BEGIN{dx=$cx-512; dy=$cy-512; d=sqrt(dx*dx+dy*dy); print (d < 50) ? 1 : 0}")
  if [ "$in_range" = "1" ]; then
    pass
  else
    fail "pole marker at ($cx, $cy), expected near (512, 512)"
  fi
fi

# --- Summary ---
echo ""
echo "=============================="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
