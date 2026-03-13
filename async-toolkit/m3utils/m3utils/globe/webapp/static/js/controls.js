/**
 * Sidebar control visibility logic.
 *
 * Shows/hides center, parallels, and oblique input groups
 * based on the selected projection and oblique mode.
 */

const PROJECTION_META = {
  equirectangular:      { needsCenter: false, needsParallels: false, isMercator: false },
  mercator:             { needsCenter: false, needsParallels: false, isMercator: true  },
  transversemercator:   { needsCenter: true,  needsParallels: false, isMercator: false },
  stereographic:        { needsCenter: true,  needsParallels: false, isMercator: false },
  orthographic:         { needsCenter: true,  needsParallels: false, isMercator: false },
  azimuthalequidistant: { needsCenter: true,  needsParallels: false, isMercator: false },
  lambertconformalconic:{ needsCenter: true,  needsParallels: true,  isMercator: false },
  albersequalarea:      { needsCenter: true,  needsParallels: true,  isMercator: false },
  robinson:             { needsCenter: false, needsParallels: false, isMercator: false },
};

function updateProjectionControls() {
  const proj = document.getElementById("projection").value;
  const meta = PROJECTION_META[proj] || { needsCenter: false, needsParallels: false };

  document.getElementById("center-group").style.display = "";
  document.getElementById("parallels-group").style.display =
    meta.needsParallels ? "" : "none";
  document.getElementById("mercator-lat-group").style.display =
    meta.isMercator ? "" : "none";
}

function updateObliqueControls() {
  const mode = document.getElementById("obliqueMode").value;

  document.getElementById("oblique-coords-group").style.display =
    mode === "coordinates" ? "" : "none";
  document.getElementById("oblique-airports-group").style.display =
    mode === "airports" ? "" : "none";
  document.getElementById("oblique-pole-group").style.display =
    mode === "pole" ? "" : "none";
  document.getElementById("oblique-pole-airports-group").style.display =
    mode === "pole_airports" ? "" : "none";
}

function initControls() {
  document.getElementById("projection").addEventListener("change", updateProjectionControls);
  document.getElementById("obliqueMode").addEventListener("change", updateObliqueControls);

  // Range slider value display
  document.getElementById("strokeWidth").addEventListener("input", function() {
    document.getElementById("strokeWidthVal").textContent = this.value;
  });
  document.getElementById("pointRadius").addEventListener("input", function() {
    document.getElementById("pointRadiusVal").textContent = this.value;
  });

  // Fill "none" toggle
  document.getElementById("fillNone").addEventListener("change", function() {
    document.getElementById("fill").disabled = this.checked;
  });

  updateProjectionControls();
  updateObliqueControls();
}

document.addEventListener("DOMContentLoaded", initControls);
