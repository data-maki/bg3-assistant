// Leaflet: map init, marker icons + rendering, fanned positions, the live
// player beacon, position polling, and manual position. Leaflet's `L` is the
// global from the classic vendor script. Actions that must re-render the app
// (marker/background clicks) are injected as callbacks from app.js; the only
// cross-module render call is the detail-card refresh when the player moves.

import { state, els, escapeHtml, markerClass, isResolved, iconUrl } from "./state.js";
import { renderDetail } from "./panels.js";

const TRANSPARENT_PX = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";

const shortName = (marker) => (marker.name.length > 26 ? `${marker.name.slice(0, 24)}…` : marker.name);

export function initMap({ onBackgroundClick }) {
  const cfg = state.data.mapgenie;
  const map = L.map(els.mapEl, {
    zoomControl: false,
    attributionControl: true,
    minZoom: cfg.minZoom + 2,
    maxZoom: cfg.maxZoom,
    zoomSnap: 0.5,
    wheelPxPerZoomLevel: 90,
  });
  map.setView([cfg.start.lat, cfg.start.lng], cfg.start.zoom);

  // The MapGenie tileset only covers a small rectangle near the world centre.
  // Constrain requests to that rectangle so out-of-bounds tiles (which 403) are
  // never fetched, and swap any stray error tile for a transparent pixel.
  const tileBounds = L.latLngBounds([[0, -1.406], [1.406, 0]]);
  L.tileLayer(cfg.tileUrl, {
    minZoom: cfg.minZoom,
    maxZoom: cfg.maxZoom,
    minNativeZoom: cfg.minZoom,
    maxNativeZoom: cfg.maxZoom,
    bounds: tileBounds,
    noWrap: true,
    errorTileUrl: TRANSPARENT_PX,
    attribution: cfg.attribution,
    crossOrigin: true,
  }).addTo(map);

  map.setMaxBounds(tileBounds.pad(0.1));
  state.map = map;
  state.markerLayer = L.layerGroup().addTo(map);

  map.on("click", () => onBackgroundClick());
  map.on("contextmenu", (event) => setManualPosition(event.latlng));
  map.on("dragstart", () => setFollow(false));
  window.addEventListener("resize", () => map.invalidateSize());
  setTimeout(() => map.invalidateSize(), 60);
}

// ---------------------------------------------------------------------------
// Live player position (fed by the Mac app's screenshot → map-align loop)
// ---------------------------------------------------------------------------

function positionAgeSeconds() {
  if (!state.player) return Infinity;
  return Date.now() / 1000 - state.player.updated_at;
}

function renderLiveStatus() {
  const age = positionAgeSeconds();
  let cls = "none";
  let text = "No live position";
  if (state.player) {
    const label = state.player.source === "map-align" ? "Game map" : state.player.source;
    if (age < 30) { cls = "live"; text = `${label} · ${Math.max(0, Math.round(age))}s ago`; }
    else if (age < 600) { cls = "stale"; text = `${label} · ${Math.round(age / 60)}m ago`; }
    else { cls = "stale"; text = `${label} · stale`; }
  }
  els.liveStatus.className = `live-status live-status--${cls}`;
  els.liveStatus.innerHTML = `<i></i>${escapeHtml(text)}`;
}

function renderPlayer() {
  if (!state.map) return;
  if (!state.player) { if (state.playerMarker) { state.playerMarker.remove(); state.playerMarker = null; } return; }
  const latlng = [state.player.lat, state.player.lng];
  const stale = positionAgeSeconds() > 30;
  const icon = L.divIcon({
    className: "player-wrap",
    html: `<span class="player-beacon ${stale ? "player-beacon--stale" : ""}"><span class="player-beacon__pulse"></span><span class="player-beacon__core"></span></span>`,
    iconSize: [26, 26],
    iconAnchor: [13, 13],
  });
  if (!state.playerMarker) {
    state.playerMarker = L.marker(latlng, { icon, zIndexOffset: 2000, interactive: true });
    state.playerMarker.bindTooltip("You are here (estimated)", { direction: "top", offset: [0, -12] });
    state.playerMarker.addTo(state.map);
  } else {
    state.playerMarker.setLatLng(latlng);
    state.playerMarker.setIcon(icon);
  }
}

export async function pollPosition() {
  try {
    const response = await fetch("/api/position");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const payload = await response.json();
    const previous = state.player;
    state.player = payload.position || null;
    renderPlayer();
    renderLiveStatus();
    const moved = state.player && (!previous
      || Math.abs(previous.lat - state.player.lat) > 1e-6
      || Math.abs(previous.lng - state.player.lng) > 1e-6);
    if (moved && state.follow) {
      state.map.panTo([state.player.lat, state.player.lng], { animate: true, duration: 0.5 });
    }
    if (moved && state.selectedId) renderDetail();
  } catch {
    renderLiveStatus();
  }
}

async function setManualPosition(latlng) {
  try {
    const response = await fetch("/api/position", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ lat: latlng.lat, lng: latlng.lng, source: "manual" }),
    });
    const payload = await response.json();
    state.player = payload.position || state.player;
    renderPlayer();
    renderLiveStatus();
    if (state.selectedId) renderDetail();
  } catch { /* backend offline; ignore */ }
}

export function setFollow(enabled) {
  state.follow = enabled;
  els.followBtn.classList.toggle("active", enabled);
  if (enabled && state.player) state.map.panTo([state.player.lat, state.player.lng]);
}

// Fan out markers that share the exact same coordinate (coarse area anchors)
// so each one stays clickable instead of hiding beneath the others.
function fannedPositions(markers) {
  const groups = new Map();
  markers.forEach((marker) => {
    const key = `${marker.lat.toFixed(5)},${marker.lng.toFixed(5)}`;
    (groups.get(key) || groups.set(key, []).get(key)).push(marker);
  });
  const positions = new Map();
  const GOLDEN = 2.399963;
  groups.forEach((group) => {
    group.forEach((marker, index) => {
      if (group.length === 1 || index === 0) {
        positions.set(marker.id, [marker.lat, marker.lng]);
        return;
      }
      const radius = 0.0034 + 0.0018 * (index - 1);
      const angle = index * GOLDEN;
      positions.set(marker.id, [
        marker.lat + Math.sin(angle) * radius,
        marker.lng + Math.cos(angle) * radius,
      ]);
    });
  });
  return positions;
}

function markerIcon(marker) {
  const type = markerClass(marker);
  const selected = state.selectedId === marker.id;
  const resolved = isResolved(marker);
  const classes = [
    "pin", `pin--${type}`,
    marker.precision !== "exact" ? "pin--area" : "",
    resolved ? "pin--done" : "",
    selected ? "pin--selected" : "",
  ].filter(Boolean).join(" ");
  const label = (state.showLabels || selected)
    ? `<span class="pin__label">${escapeHtml(shortName(marker))}</span>`
    : "";
  const ring = marker.precision !== "exact" ? '<span class="pin__ring"></span>' : "";
  const icon = marker.type === "item" && iconUrl(marker)
    ? `<span class="pin__img" style="background-image:url('${iconUrl(marker)}')"></span>`
    : '<span class="pin__dot"></span>';
  const equippedTick = resolved && marker.type === "item" ? '<span class="pin__tick">✓</span>' : "";
  const skull = marker.type === "fight" && marker.legendaryAction && !resolved ? '<span class="pin__skull">☠</span>' : "";
  return L.divIcon({
    className: "pin-wrap",
    html: `<span class="${classes}">${ring}${icon}${equippedTick}${skull}${label}</span>`,
    iconSize: [24, 24],
    iconAnchor: [12, 12],
  });
}

export function renderMarkers(markers, { fit = false, onSelect } = {}) {
  if (!state.map) return;
  state.markerLayer.clearLayers();
  state.leafletMarkers.clear();
  els.emptyMap.hidden = markers.length > 0;

  const positions = fannedPositions(markers);
  const latlngs = [];
  markers.forEach((marker) => {
    const pos = positions.get(marker.id);
    latlngs.push(pos);
    const leafletMarker = L.marker(pos, {
      icon: markerIcon(marker),
      zIndexOffset: state.selectedId === marker.id ? 1000 : (marker.type === "fight" ? 200 : 0),
      riseOnHover: true,
    });
    leafletMarker.bindTooltip(marker.name, { direction: "top", offset: [0, -10], opacity: 0.95 });
    leafletMarker.on("click", (event) => {
      L.DomEvent.stopPropagation(event);
      onSelect(marker);
    });
    leafletMarker.addTo(state.markerLayer);
    state.leafletMarkers.set(marker.id, leafletMarker);
  });

  if (fit && latlngs.length) {
    state.map.fitBounds(L.latLngBounds(latlngs).pad(0.25), { maxZoom: state.data.mapgenie.maxZoom - 2 });
  }
}
