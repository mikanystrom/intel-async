#!/bin/sh
#
# gen-atlas.sh — generate curvature atlas figures for the Al(Ga) report
#
# Usage: gen-atlas.sh <datadir> <figdir>
#   datadir: directory containing 550_1_*/Face_*.ply files
#   figdir:  output directory for PNG figures
#
# Requires: plydemo (built from Al_Ga/plydemo), gnuplot
#

set -e

if [ $# -lt 2 ]; then
  echo "usage: $0 <datadir> <figdir>" >&2
  exit 1
fi

DATADIR="$1"
FIGDIR="$2"
SCRIPTDIR=$(cd "$(dirname "$0")/.." && pwd)
DEMO="$SCRIPTDIR/plydemo/ARM64_DARWIN/plydemo"
TMPDIR="${TMPDIR:-/tmp}/al-ga-atlas.$$"

if [ ! -x "$DEMO" ]; then
  echo "error: plydemo not found at $DEMO" >&2
  echo "       build it first: cd Al_Ga/plydemo/src && cm3 -override" >&2
  exit 1
fi

mkdir -p "$FIGDIR" "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

CBMIN=-3
CBMAX=3

# nice_tick: compute a nice tick interval for a given range
# picks from 100, 200, 500, 1000, 2000, 5000, 10000, 20000
nice_tick() {
  awk -v range="$1" 'BEGIN {
    # aim for 4-8 ticks
    target = range / 6
    # round to a nice number
    p = 10 ^ int(log(target) / log(10))
    n = target / p
    if (n < 1.5)      nice = 1 * p
    else if (n < 3.5)  nice = 2 * p
    else if (n < 7.5)  nice = 5 * p
    else                nice = 10 * p
    printf "%.0f\n", nice
  }'
}

count=0
for sample_dir in "$DATADIR"/550_1_*; do
  [ -d "$sample_dir" ] || continue
  sample=$(basename "$sample_dir")

  for ply in "$sample_dir"/Face_*; do
    [ -f "$ply" ] || continue
    bn=$(basename "$ply" .ply)
    bn=$(echo "$bn" | sed 's/_mesh//')
    tag="${sample}_${bn}"
    outname=$(echo "$tag" | tr '_' '-')
    contourdir="$TMPDIR/$tag"

    mkdir -p "$contourdir"
    echo -n "$tag... "

    # generate contour data
    "$DEMO" -contour "$contourdir" "$ply" > /dev/null 2>&1

    # compute data extent (non-NaN cells only)
    extent=$(grep -v NaN "$contourdir/face_curvature.dat" | awk '
      NR==1 { xmin=$1; xmax=$1; ymin=$2; ymax=$2 }
      { if($1<xmin) xmin=$1; if($1>xmax) xmax=$1
        if($2<ymin) ymin=$2; if($2>ymax) ymax=$2 }
      END { printf "%f %f %f %f", xmin, xmax, ymin, ymax }
    ')

    xmin=$(echo "$extent" | awk '{print $1}')
    xmax=$(echo "$extent" | awk '{print $2}')
    ymin=$(echo "$extent" | awk '{print $3}')
    ymax=$(echo "$extent" | awk '{print $4}')
    dx=$(echo "$xmax $xmin" | awk '{printf "%.0f", $1 - $2}')
    dy=$(echo "$ymax $ymin" | awk '{printf "%.0f", $1 - $2}')

    # use the larger range for tick calculation
    maxrange=$(echo "$dx $dy" | awk '{print ($1 > $2) ? $1 : $2}')
    tick=$(nice_tick "$maxrange")

    # compute PNG dimensions to match aspect ratio
    # base: longest axis gets 1000px, add margins for labels
    dims=$(echo "$dx $dy" | awk '{
      if ($1 > $2) { pw = 1000; ph = int(1000 * $2 / $1) }
      else         { ph = 1000; pw = int(1000 * $1 / $2) }
      printf "%d,%d", pw + 400, ph + 200
    }')
    pw=$(echo "$dims" | cut -d, -f1)
    ph=$(echo "$dims" | cut -d, -f2)

    label=$(echo "$tag" | sed 's/_/ /g')

    gnuplot -e "
      set terminal pngcairo size ${pw},${ph} font ',11';
      set output '${FIGDIR}/${outname}.png';
      set title '${label} --- Mean Curvature H (mm^{-1})' font ',13';
      set xlabel 'x ({/Symbol m}m)';
      set ylabel 'y ({/Symbol m}m)';
      set cblabel 'H (mm^{-1})';
      set pm3d map;
      set palette defined (-1 '#1a3399', 0 '#707070', 1 '#cc3333');
      set cbrange [${CBMIN}:${CBMAX}];
      set size ratio -1;
      set xtics ${tick};
      set ytics ${tick};
      splot '${contourdir}/face_curvature.dat' with pm3d notitle
    " 2>/dev/null

    count=$((count + 1))
    echo "ok"
  done
done

echo ""
echo "$count figures written to $FIGDIR/"
