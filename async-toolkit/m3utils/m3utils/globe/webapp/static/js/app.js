/**
 * Main application logic: dataset loading, rendering, SVG interaction.
 */

let currentSvg = null;
let debounceTimer = null;
let renderInProgress = false;

/* ── Dataset loading ── */

async function loadDatasets() {
  const container = document.getElementById("datasets");
  try {
    const resp = await fetch("/api/datasets");
    const datasets = await resp.json();
    if (datasets.length === 0) {
      container.innerHTML = '<div class="loading-text">No datasets found.</div>';
      return;
    }
    container.innerHTML = "";
    datasets.forEach((ds, i) => {
      const div = document.createElement("div");
      div.className = "dataset-item";

      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.id = "ds-" + i;
      cb.value = ds.id;
      // Auto-select the first (minimal) dataset
      if (i === 0) cb.checked = true;

      const label = document.createElement("label");
      label.htmlFor = "ds-" + i;
      label.textContent = ds.name;

      const size = document.createElement("span");
      size.className = "size";
      size.textContent = formatSize(ds.size);

      div.appendChild(cb);
      div.appendChild(label);
      div.appendChild(size);
      container.appendChild(div);
    });
  } catch (e) {
    container.innerHTML = '<div class="loading-text">Failed to load datasets.</div>';
  }
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

/* ── Parameter collection ── */

function collectParams() {
  const fillNone = document.getElementById("fillNone").checked;

  const params = {
    projection: document.getElementById("projection").value,
    centerLat:  parseFloat(document.getElementById("centerLat").value) || 0,
    centerLon:  parseFloat(document.getElementById("centerLon").value) || 0,
    parallel1:  parseFloat(document.getElementById("parallel1").value) || 29.5,
    parallel2:  parseFloat(document.getElementById("parallel2").value) || 45.5,
    obliqueMode: document.getElementById("obliqueMode").value,
    obliqueLat1: parseFloat(document.getElementById("obliqueLat1").value) || 0,
    obliqueLon1: parseFloat(document.getElementById("obliqueLon1").value) || 0,
    obliqueLat2: parseFloat(document.getElementById("obliqueLat2").value) || 0,
    obliqueLon2: parseFloat(document.getElementById("obliqueLon2").value) || 0,
    airport1:   document.getElementById("airport1").value.trim(),
    airport2:   document.getElementById("airport2").value.trim(),
    width:      parseInt(document.getElementById("width").value) || 1024,
    height:     parseInt(document.getElementById("height").value) || 512,
    stroke:     document.getElementById("stroke").value,
    fill:       fillNone ? "none" : document.getElementById("fill").value,
    background: document.getElementById("background").value,
    strokeWidth: parseFloat(document.getElementById("strokeWidth").value) || 0.5,
    pointRadius: parseFloat(document.getElementById("pointRadius").value) || 2.0,
    overlayEarthEquator: document.getElementById("overlayEarthEquator").checked,
    overlayProjEquator: document.getElementById("overlayProjEquator").checked,
    datasets:   getSelectedDatasets(),
  };
  return params;
}

function getSelectedDatasets() {
  const checkboxes = document.querySelectorAll('#datasets input[type="checkbox"]:checked');
  return Array.from(checkboxes).map(cb => cb.value);
}

/* ── Projection helpers ── */

function currentProjectionNeedsCenter() {
  const proj = document.getElementById("projection").value;
  const meta = PROJECTION_META[proj];
  return meta ? meta.needsCenter : false;
}

/* ── Rendering ── */

async function renderMap() {
  if (renderInProgress) return;
  renderInProgress = true;

  const params = collectParams();
  if (params.datasets.length === 0) {
    setStatus("Select at least one dataset.", true);
    renderInProgress = false;
    return;
  }

  const overlay = document.getElementById("loadingOverlay");
  const container = document.getElementById("svgContainer");
  const placeholder = document.getElementById("placeholder");
  const renderBtn = document.getElementById("renderBtn");

  overlay.style.display = "";
  renderBtn.disabled = true;
  setStatus("Rendering...");

  const t0 = performance.now();

  try {
    const resp = await fetch("/api/render", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });

    if (!resp.ok) {
      let msg;
      const ct = resp.headers.get("Content-Type") || "";
      if (ct.includes("json")) {
        const err = await resp.json();
        msg = err.error || "Render failed";
      } else {
        msg = await resp.text();
      }
      setStatus(msg, true);
      return;
    }

    const svg = await resp.text();
    currentSvg = svg;

    if (placeholder) placeholder.style.display = "none";

    // Insert SVG into container
    container.innerHTML = svg;
    document.getElementById("downloadBtn").disabled = false;

    const elapsed = ((performance.now() - t0) / 1000).toFixed(2);
    setStatus("Rendered in " + elapsed + "s");

    initSvgInteraction();
  } catch (e) {
    setStatus("Network error: " + e.message, true);
  } finally {
    overlay.style.display = "none";
    renderBtn.disabled = false;
    renderInProgress = false;
  }
}

/* ── SVG zoom/pan interaction ── */

function initSvgInteraction() {
  const svgEl = document.querySelector(".svg-container svg");
  if (!svgEl) return;

  // Parse original viewBox
  const vb = svgEl.getAttribute("viewBox");
  if (!vb) return;
  const parts = vb.split(/[\s,]+/).map(Number);
  if (parts.length !== 4) return;

  let [vx, vy, vw, vh] = parts;
  const origW = vw, origH = vh;
  let dragging = false;
  let rotateMode = false;
  let startX, startY, startVx, startVy, startLat, startLon;

  svgEl.addEventListener("wheel", function(e) {
    e.preventDefault();
    const scale = e.deltaY > 0 ? 1.15 : 1 / 1.15;

    // Zoom toward cursor position
    const rect = svgEl.getBoundingClientRect();
    const fx = (e.clientX - rect.left) / rect.width;
    const fy = (e.clientY - rect.top) / rect.height;

    const newW = vw * scale;
    const newH = vh * scale;
    vx += (vw - newW) * fx;
    vy += (vh - newH) * fy;
    vw = newW;
    vh = newH;

    svgEl.setAttribute("viewBox", vx + " " + vy + " " + vw + " " + vh);
  }, { passive: false });

  svgEl.addEventListener("mousedown", function(e) {
    if (e.button !== 0) return;
    dragging = true;
    startX = e.clientX;
    startY = e.clientY;
    rotateMode = currentProjectionNeedsCenter();
    if (rotateMode) {
      startLat = parseFloat(document.getElementById("centerLat").value) || 0;
      startLon = parseFloat(document.getElementById("centerLon").value) || 0;
    } else {
      startVx = vx;
      startVy = vy;
    }
    svgEl.style.cursor = "grabbing";
    e.preventDefault();
  });

  window.addEventListener("mousemove", function(e) {
    if (!dragging) return;
    const rect = svgEl.getBoundingClientRect();
    if (rotateMode) {
      // Convert pixel displacement to degrees
      // Full SVG width = 360° longitude, full height = 180° latitude
      const dLon = (e.clientX - startX) / rect.width * 360;
      const dLat = (e.clientY - startY) / rect.height * 180;
      // Drag right = globe rotates left = lon decreases (grab-and-drag)
      let newLon = startLon - dLon;
      let newLat = startLat + dLat;
      // Clamp latitude, wrap longitude
      newLat = Math.max(-90, Math.min(90, newLat));
      newLon = ((newLon + 180) % 360 + 360) % 360 - 180;
      document.getElementById("centerLat").value = Math.round(newLat);
      document.getElementById("centerLon").value = Math.round(newLon);
    } else {
      const dx = (e.clientX - startX) / rect.width * vw;
      const dy = (e.clientY - startY) / rect.height * vh;
      vx = startVx - dx;
      vy = startVy - dy;
      svgEl.setAttribute("viewBox", vx + " " + vy + " " + vw + " " + vh);
    }
  });

  window.addEventListener("mouseup", function() {
    if (!dragging) return;
    dragging = false;
    svgEl.style.cursor = "";
    if (rotateMode) {
      renderMap();
    }
  });
}

/* ── Arrow key rotation/pan ── */

function initArrowKeys() {
  let arrowDebounce = null;

  document.addEventListener("keydown", function(e) {
    // Skip when focus is in an input/select/textarea
    const tag = document.activeElement && document.activeElement.tagName;
    if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA") return;

    const key = e.key;
    if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(key)) return;
    e.preventDefault();

    const checkbox = document.getElementById("arrowRotate");
    const wantRotate = checkbox && checkbox.checked && currentProjectionNeedsCenter();

    if (wantRotate) {
      // Rotate center by 5° steps
      const latEl = document.getElementById("centerLat");
      const lonEl = document.getElementById("centerLon");
      let lat = parseFloat(latEl.value) || 0;
      let lon = parseFloat(lonEl.value) || 0;

      if (key === "ArrowUp")    lat = Math.min(90, lat + 5);
      if (key === "ArrowDown")  lat = Math.max(-90, lat - 5);
      if (key === "ArrowLeft")  lon = ((lon + 5 + 180) % 360 + 360) % 360 - 180;
      if (key === "ArrowRight") lon = ((lon - 5 + 180) % 360 + 360) % 360 - 180;

      latEl.value = Math.round(lat);
      lonEl.value = Math.round(lon);

      // Debounce render for rapid key presses
      clearTimeout(arrowDebounce);
      arrowDebounce = setTimeout(function() {
        renderMap();
      }, 300);
    } else {
      // Pan viewBox by 10%
      const svgEl = document.querySelector(".svg-container svg");
      if (!svgEl) return;
      const vb = svgEl.getAttribute("viewBox");
      if (!vb) return;
      const p = vb.split(/[\s,]+/).map(Number);
      if (p.length !== 4) return;

      const stepX = p[2] * 0.1;
      const stepY = p[3] * 0.1;

      if (key === "ArrowUp")    p[1] -= stepY;
      if (key === "ArrowDown")  p[1] += stepY;
      if (key === "ArrowLeft")  p[0] -= stepX;
      if (key === "ArrowRight") p[0] += stepX;

      svgEl.setAttribute("viewBox", p[0] + " " + p[1] + " " + p[2] + " " + p[3]);
    }
  });
}

/* ── Download ── */

function downloadSvg() {
  if (!currentSvg) return;
  const blob = new Blob([currentSvg], { type: "image/svg+xml" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "globe-map.svg";
  a.click();
  URL.revokeObjectURL(url);
}

/* ── Status bar ── */

function setStatus(msg, isError) {
  const bar = document.getElementById("statusBar");
  bar.textContent = msg;
  bar.className = "status-bar" + (isError ? " error" : "");
}

/* ── Initialization ── */

document.addEventListener("DOMContentLoaded", function() {
  loadDatasets();
  initArrowKeys();

  document.getElementById("renderBtn").addEventListener("click", renderMap);
  document.getElementById("downloadBtn").addEventListener("click", downloadSvg);

  // Ctrl+Enter shortcut
  document.addEventListener("keydown", function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
      e.preventDefault();
      renderMap();
    }
  });

  // Auto-render on param change with debounce
  const inputs = document.querySelectorAll("select, input");
  inputs.forEach(function(el) {
    el.addEventListener("change", function() {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(function() {
        if (currentSvg !== null) renderMap();
      }, 500);
    });
  });
});
