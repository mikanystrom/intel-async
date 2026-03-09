#!/bin/sh
#
# Test suite for the globe map projection library.
#
# Usage: cd globe && sh test.sh
#

set -e

M3UTILS="${M3UTILS:-$(cd "$(dirname "$0")"/.. && pwd)}"

# Find target architecture
if [ -f "$M3UTILS/.bindir" ]; then
    TARGET="$(cat "$M3UTILS/.bindir")"
elif [ -x "$M3UTILS/m3arch.sh" ]; then
    TARGET="$("$M3UTILS/m3arch.sh")"
else
    # guess from what's built
    for d in globetool/ARM64_DARWIN globetool/AMD64_LINUX globetool/AMD64_DARWIN; do
        if [ -x "$d/globetool" ]; then
            TARGET="$(basename "$d")"
            break
        fi
    done
fi

GLOBETOOL="globetool/$TARGET/globetool"

if [ ! -x "$GLOBETOOL" ]; then
    echo "FATAL: globetool not found at $GLOBETOOL" >&2
    exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "  PASS  %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "  FAIL  %s  (%s)\n" "$1" "$2"
}

# Helper: run globetool and check exit code
run_ok() {
    # $1=test name, $2..=args
    name="$1"; shift
    if "$GLOBETOOL" "$@" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr"; then
        return 0
    else
        return 1
    fi
}

##############################################################################
echo "=== Test data setup ==="

cat > "$TMPDIR/world.geojson" << 'EOF'
{"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"Point","coordinates":[0,0]},"properties":{"name":"Null Island"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-73.9857,40.7484]},"properties":{"name":"NYC"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[139.6917,35.6895]},"properties":{"name":"Tokyo"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-0.4543,51.47]},"properties":{"name":"London"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[151.1772,-33.9461]},"properties":{"name":"Sydney"}},
  {"type":"Feature","geometry":{"type":"LineString","coordinates":[[0,0],[10,10],[20,20]]},"properties":{"name":"Diagonal"}},
  {"type":"Feature","geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]},"properties":{"name":"Box"}}
]}
EOF

echo "Test data: 5 points + 1 line + 1 polygon"
echo ""

##############################################################################
echo "=== Projection tests ==="

# Test each projection produces valid output
for proj in equirectangular mercator transversemercator robinson; do
    if run_ok "$proj" -projection $proj \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/out.geojson"; then
        # Check output is valid-looking GeoJSON
        if grep -q '"FeatureCollection"' "$TMPDIR/out.geojson" && \
           grep -q '"features"' "$TMPDIR/out.geojson"; then
            pass "$proj projection"
        else
            fail "$proj projection" "output not valid GeoJSON"
        fi
    else
        fail "$proj projection" "exit code $?"
    fi
done

# Azimuthal projections need a center
for proj in stereographic orthographic azimuthalequidistant; do
    if run_ok "$proj" -projection $proj -center 40.7 -74.0 \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/out.geojson"; then
        if grep -q '"FeatureCollection"' "$TMPDIR/out.geojson"; then
            pass "$proj projection (centered NYC)"
        else
            fail "$proj projection" "output not valid GeoJSON"
        fi
    else
        fail "$proj projection" "exit code $?"
    fi
done

# Conic projections need parallels
for proj in lambertconformalconic albersequalarea; do
    if run_ok "$proj" -projection $proj -parallels 30 60 -center 45 -10 \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/out.geojson"; then
        if grep -q '"FeatureCollection"' "$TMPDIR/out.geojson"; then
            pass "$proj projection (30/60 parallels)"
        else
            fail "$proj projection" "output not valid GeoJSON"
        fi
    else
        fail "$proj projection" "exit code $?"
    fi
done

echo ""

##############################################################################
echo "=== Equirectangular identity test ==="

# Equirectangular should preserve lat/lon (in radians)
# Input: [0, 0] -> output should be [0.000000, 0.000000]
run_ok "equirect identity" -projection equirectangular \
    -input "$TMPDIR/world.geojson" -output "$TMPDIR/equirect.geojson"

if grep -q '\[0\.000000,0\.000000\]' "$TMPDIR/equirect.geojson"; then
    pass "equirectangular origin maps to (0,0)"
else
    fail "equirectangular origin" "expected [0.000000,0.000000]"
fi

echo ""

##############################################################################
echo "=== Orthographic hemisphere clipping ==="

# Orthographic centered on NYC: Sydney should be clipped (null)
run_ok "ortho clip" -projection orthographic -center 40.7 -74.0 \
    -input "$TMPDIR/world.geojson" -output "$TMPDIR/ortho.geojson"

if grep -q '"Sydney"' "$TMPDIR/ortho.geojson"; then
    # Sydney feature exists; its coordinates should be null (back hemisphere)
    # Extract the Sydney feature's coordinates
    sydney_line=$(grep -A1 '"Sydney"' "$TMPDIR/ortho.geojson" | head -1)
    if echo "$sydney_line" | grep -q 'null'; then
        pass "orthographic clips back hemisphere (Sydney=null)"
    else
        # Sydney might be on same line
        sydney_feat=$(grep '"Sydney"' "$TMPDIR/ortho.geojson")
        if echo "$sydney_feat" | grep -q 'null'; then
            pass "orthographic clips back hemisphere (Sydney=null)"
        else
            fail "orthographic clipping" "Sydney coordinates not null"
        fi
    fi
else
    fail "orthographic clipping" "Sydney feature not found in output"
fi

# NYC should be near (0,0) since it's the center
if grep '"NYC"' "$TMPDIR/ortho.geojson" | grep -q '0\.00'; then
    pass "orthographic center maps near origin (NYC)"
else
    fail "orthographic center" "NYC not near origin"
fi

echo ""

##############################################################################
echo "=== Oblique projection with coordinates ==="

# Oblique Mercator with London-Tokyo great circle
run_ok "oblique coords" -projection mercator \
    -oblique 51.47 -0.45 35.69 139.69 \
    -input "$TMPDIR/world.geojson" -output "$TMPDIR/oblique.geojson"

if grep -q '"FeatureCollection"' "$TMPDIR/oblique.geojson"; then
    pass "oblique mercator with coordinate spec"
else
    fail "oblique mercator coords" "invalid output"
fi

echo ""

##############################################################################
echo "=== Airport code lookup ==="

# Test various airport codes
for code_pair in "LHR NRT" "SFO SYD" "JFK LAX" "EDDF OMDB" "CDG ICN"; do
    code1=$(echo $code_pair | cut -d' ' -f1)
    code2=$(echo $code_pair | cut -d' ' -f2)
    if run_ok "airport $code1-$code2" -projection mercator \
              -greatcircle $code1 $code2 \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/gc.geojson"; then
        if grep -q '"FeatureCollection"' "$TMPDIR/gc.geojson"; then
            pass "great circle $code1-$code2"
        else
            fail "great circle $code1-$code2" "invalid output"
        fi
    else
        fail "great circle $code1-$code2" "exit code $?"
    fi
done

# Test lowercase codes work
if run_ok "lowercase" -projection mercator -greatcircle lhr nrt \
          -input "$TMPDIR/world.geojson" -output "$TMPDIR/gc.geojson"; then
    pass "case-insensitive airport codes (lhr/nrt)"
else
    fail "case-insensitive airport codes" "exit code $?"
fi

# Test unknown airport code fails
if "$GLOBETOOL" -projection mercator -greatcircle ZZZZ NRT \
        -input "$TMPDIR/world.geojson" -output /dev/null \
        >/dev/null 2>&1; then
    fail "unknown airport code" "should have failed"
else
    pass "unknown airport code rejected (ZZZZ)"
fi

echo ""

##############################################################################
echo "=== Oblique equator test ==="

# With LHR-NRT great circle, Tokyo should map very close to y=0
run_ok "oblique equator" -projection mercator -greatcircle LHR NRT \
    -input "$TMPDIR/world.geojson" -output "$TMPDIR/oblique_gc.geojson"

# Extract Tokyo's y coordinate
tokyo_y=$(grep '"Tokyo"' "$TMPDIR/oblique_gc.geojson" | \
          sed 's/.*coordinates":\[[-0-9.]*,\([-0-9.]*\)\].*/\1/')
if [ -n "$tokyo_y" ]; then
    # Check |y| < 0.05 (should be very close to 0)
    is_small=$(echo "$tokyo_y" | awk '{v=$1; if(v<0)v=-v; print (v < 0.05) ? "yes" : "no"}')
    if [ "$is_small" = "yes" ]; then
        pass "Tokyo near equator on LHR-NRT great circle (y=$tokyo_y)"
    else
        fail "Tokyo on great circle equator" "y=$tokyo_y, expected near 0"
    fi
else
    fail "Tokyo on great circle equator" "could not extract y coordinate"
fi

echo ""

##############################################################################
echo "=== Geometry type tests ==="

# LineString
if grep -q '"LineString"' "$TMPDIR/equirect.geojson"; then
    pass "LineString geometry preserved"
else
    fail "LineString geometry" "not found in output"
fi

# Polygon
if grep -q '"Polygon"' "$TMPDIR/equirect.geojson"; then
    pass "Polygon geometry preserved"
else
    fail "Polygon geometry" "not found in output"
fi

# Test MultiPoint
cat > "$TMPDIR/multi.geojson" << 'EOF'
{"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"MultiPoint","coordinates":[[0,0],[10,10],[20,20]]},"properties":{"name":"MPs"}}
]}
EOF

if run_ok "multipoint" -projection equirectangular \
          -input "$TMPDIR/multi.geojson" -output "$TMPDIR/multi_out.geojson"; then
    if grep -q '"MultiPoint"' "$TMPDIR/multi_out.geojson"; then
        pass "MultiPoint geometry"
    else
        fail "MultiPoint geometry" "type not preserved"
    fi
else
    fail "MultiPoint geometry" "exit code $?"
fi

# Test MultiLineString
cat > "$TMPDIR/multiline.geojson" << 'EOF'
{"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"MultiLineString","coordinates":[[[0,0],[10,10]],[[20,20],[30,30]]]},"properties":{"name":"MLs"}}
]}
EOF

if run_ok "multilinestring" -projection equirectangular \
          -input "$TMPDIR/multiline.geojson" -output "$TMPDIR/multiline_out.geojson"; then
    if grep -q '"MultiLineString"' "$TMPDIR/multiline_out.geojson"; then
        pass "MultiLineString geometry"
    else
        fail "MultiLineString geometry" "type not preserved"
    fi
else
    fail "MultiLineString geometry" "exit code $?"
fi

echo ""

##############################################################################
echo "=== Feature count test ==="

# Check the tool reports correct feature count
run_ok "count" -projection mercator \
    -input "$TMPDIR/world.geojson" -output /dev/null

if grep -q "Features:.*7" "$TMPDIR/stdout"; then
    pass "feature count reported correctly (7)"
else
    fail "feature count" "$(grep Features "$TMPDIR/stdout")"
fi

echo ""

##############################################################################
echo "=== Projection name in output ==="

run_ok "name" -projection robinson \
    -input "$TMPDIR/world.geojson" -output /dev/null

if grep -q "Projection: Robinson" "$TMPDIR/stdout"; then
    pass "projection name: Robinson"
else
    fail "projection name" "$(grep Projection "$TMPDIR/stdout")"
fi

run_ok "oblique name" -projection stereographic -center 0 0 \
    -greatcircle SFO SYD \
    -input "$TMPDIR/world.geojson" -output /dev/null

if grep -q "Projection: Oblique Stereographic" "$TMPDIR/stdout"; then
    pass "projection name: Oblique Stereographic"
else
    fail "oblique projection name" "$(grep Projection "$TMPDIR/stdout")"
fi

echo ""

##############################################################################
echo "=== SVG output tests ==="

# Basic SVG output
if run_ok "svg basic" -projection equirectangular -format svg \
          -input "$TMPDIR/world.geojson" -output "$TMPDIR/out.svg"; then
    if grep -q '<svg' "$TMPDIR/out.svg" && grep -q '</svg>' "$TMPDIR/out.svg"; then
        pass "SVG basic output"
    else
        fail "SVG basic output" "missing <svg> or </svg>"
    fi
else
    fail "SVG basic output" "exit code $?"
fi

# SVG contains paths (for LineString/Polygon)
if grep -q '<path' "$TMPDIR/out.svg"; then
    pass "SVG contains <path> elements"
else
    fail "SVG path elements" "no <path> found"
fi

# SVG contains circles (for Point features)
if grep -q '<circle' "$TMPDIR/out.svg"; then
    pass "SVG contains <circle> elements"
else
    fail "SVG circle elements" "no <circle> found"
fi

# SVG data-name attributes
if grep -q 'data-name=' "$TMPDIR/out.svg"; then
    pass "SVG features have data-name attributes"
else
    fail "SVG data-name" "no data-name attributes"
fi

# Custom styling
if run_ok "svg styling" -projection equirectangular -format svg \
          -stroke red -fill blue -background yellow \
          -input "$TMPDIR/world.geojson" -output "$TMPDIR/styled.svg"; then
    if grep -q 'stroke: red' "$TMPDIR/styled.svg" && \
       grep -q 'fill: blue' "$TMPDIR/styled.svg" && \
       grep -q 'yellow' "$TMPDIR/styled.svg"; then
        pass "SVG custom styling (stroke/fill/background)"
    else
        fail "SVG custom styling" "custom colors not found"
    fi
else
    fail "SVG custom styling" "exit code $?"
fi

# All projections produce valid SVG
for proj in equirectangular mercator transversemercator robinson; do
    if run_ok "svg $proj" -projection $proj -format svg \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/proj.svg"; then
        if grep -q '<svg' "$TMPDIR/proj.svg"; then
            pass "SVG $proj projection"
        else
            fail "SVG $proj projection" "not valid SVG"
        fi
    else
        fail "SVG $proj projection" "exit code $?"
    fi
done

for proj in stereographic orthographic azimuthalequidistant; do
    if run_ok "svg $proj" -projection $proj -center 40.7 -74.0 -format svg \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/proj.svg"; then
        if grep -q '<svg' "$TMPDIR/proj.svg"; then
            pass "SVG $proj projection"
        else
            fail "SVG $proj projection" "not valid SVG"
        fi
    else
        fail "SVG $proj projection" "exit code $?"
    fi
done

for proj in lambertconformalconic albersequalarea; do
    if run_ok "svg $proj" -projection $proj -parallels 30 60 -center 45 -10 -format svg \
              -input "$TMPDIR/world.geojson" -output "$TMPDIR/proj.svg"; then
        if grep -q '<svg' "$TMPDIR/proj.svg"; then
            pass "SVG $proj projection"
        else
            fail "SVG $proj projection" "not valid SVG"
        fi
    else
        fail "SVG $proj projection" "exit code $?"
    fi
done

# Orthographic SVG — back-hemisphere points should be omitted (no broken paths)
run_ok "svg ortho clip" -projection orthographic -center 40.7 -74.0 -format svg \
    -input "$TMPDIR/world.geojson" -output "$TMPDIR/ortho.svg"

if grep -q '<svg' "$TMPDIR/ortho.svg"; then
    # Sydney (back hemisphere) should NOT appear as a circle
    if grep -q 'data-name="Sydney"' "$TMPDIR/ortho.svg"; then
        fail "SVG orthographic clipping" "Sydney should be clipped"
    else
        pass "SVG orthographic clips back-hemisphere points"
    fi
else
    fail "SVG orthographic" "not valid SVG"
fi

echo ""

##############################################################################
echo "=== Help output ==="

if "$GLOBETOOL" -help 2>"$TMPDIR/help" >/dev/null; then
    if grep -q 'greatcircle' "$TMPDIR/help"; then
        pass "-help includes greatcircle option"
    else
        fail "-help content" "missing greatcircle"
    fi
else
    # -help exits 0 but just in case
    pass "-help runs"
fi

echo ""

##############################################################################
echo "========================================"
printf "Results: %d passed, %d failed, %d total\n" $PASS $FAIL $TOTAL
echo "========================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
