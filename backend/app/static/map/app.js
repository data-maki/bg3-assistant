// Entry module: filtering, tabs, selection, the single render() invalidation
// point, ALL event delegation, and boot. The modules under ./js/ export pure
// render/template functions and state mutators; only this file binds listeners
// and re-renders, so no module ever needs to import app.js back.

import {
  state, els, escapeHtml, persistLocal, syncRunState, restoreRunState,
  isItemEquipped, isResolved, toggleEquipped, toggleMemberEquipment,
  normalizeRoster, syncPartyProjection, updateRosterMember, toggleStoryOutcome, recomputeEquipped,
} from "./js/state.js";
import { initMap, renderMarkers, pollPosition, setFollow } from "./js/map-layer.js";
import { renderWalkthrough, setWalkthroughStatus, focusWalkthroughStep } from "./js/walkthrough.js";
import {
  renderRoute, renderParty, renderEquipment, renderWarnings, updateWarningsBadge,
  renderDetail, previewMarkerExport, downloadMarkerExport, confirmMarkerExport,
} from "./js/panels.js";

// ---------------------------------------------------------------------------
// Filtering (shared by the route list and the map)
// ---------------------------------------------------------------------------

function markerMatches(marker) {
  if (els.region.value !== "all" && marker.region !== els.region.value) return false;
  if (marker.type === "fight" && marker.importance === "major" && !els.major.checked) return false;
  if (marker.type === "fight" && marker.importance === "minor" && !els.minor.checked) return false;
  if (marker.type === "item" && !els.item.checked) return false;
  if (marker.type === "item" && els.build.value !== "all" && !marker.buildIds.includes(els.build.value)) return false;
  if (state.missingOnly && marker.type === "item" && isItemEquipped(marker)) return false;
  if (state.missingOnly && marker.type === "fight") return false;
  if (els.hideDone.checked && isResolved(marker)) return false;
  const query = els.search.value.trim().toLowerCase();
  if (query && !`${marker.name} ${marker.area} ${marker.advice} ${marker.why || ""}`.toLowerCase().includes(query)) return false;
  return true;
}

function visibleMarkers() {
  return state.data.markers.filter(markerMatches).sort((a, b) => {
    if (a.type !== b.type) return a.type === "fight" ? -1 : 1;
    return (a.minimumLevel || 99) - (b.minimumLevel || 99) || a.name.localeCompare(b.name);
  });
}

function populateFilters() {
  els.equipmentActLabel.textContent = `ACT ${state.data.act} LOADOUTS`;
  els.region.innerHTML = `<option value="all">All Act 1 regions</option>${state.data.regions
    .map((region) => `<option value="${escapeHtml(region)}">${escapeHtml(region)}</option>`).join("")}`;
  els.region.value = state.data.regions.includes("Wilderness") ? "Wilderness" : "all";
  state.lastRegion = els.region.value;
  els.build.innerHTML = `<option value="all">All build items</option>${state.data.builds
    .map((build) => `<option value="${escapeHtml(build.id)}">${escapeHtml(build.name)}</option>`).join("")}`;
  els.mapgenie.href = state.data.mapgenieUrl;
}

function applyURLIntent() {
  const params = new URLSearchParams(window.location.search);
  const level = Number(params.get("level"));
  if (Number.isInteger(level) && level >= 1 && level <= 12) els.level.value = String(level);

  const build = params.get("build");
  const partyBuilds = (params.get("builds") || "").split(",").filter((id) => state.data.builds.some((entry) => entry.id === id));
  const completed = (params.get("done") || "").split(",").filter((id) => state.data.markers.some((entry) => entry.type === "fight" && entry.id === id));
  if (params.has("party")) {
    try {
      const party = JSON.parse(params.get("party") || "[]");
      state.party = Array.isArray(party) ? party.filter((member) => member?.id && member?.name && Number.isInteger(member.level)) : [];
      state.roster = normalizeRoster([], state.party);
      syncPartyProjection();
    } catch { state.party = []; }
  }
  if (params.has("roster")) {
    try {
      const roster = JSON.parse(params.get("roster") || "[]");
      state.roster = Array.isArray(roster)
        ? roster.filter((member) => member?.id && member?.name && Number.isInteger(member.level))
        : state.roster;
      syncPartyProjection();
    } catch { /* retain migrated roster */ }
  }
  if (params.has("walkthrough")) {
    try {
      const nativeProgress = JSON.parse(params.get("walkthrough") || "{}");
      Object.entries(nativeProgress).forEach(([stepId, status]) => {
        if (status === "completed") state.walkthroughStatuses[stepId] = "done";
        else if (status === "skipped") state.walkthroughStatuses[stepId] = "skipped";
        else if (status === "pending") state.walkthroughStatuses[stepId] = "revisit";
      });
    } catch { /* retain local walkthrough progress */ }
  }
  if (params.has("equipped")) {
    try {
      const equipped = JSON.parse(params.get("equipped") || "{}");
      if (equipped && typeof equipped === "object" && !Array.isArray(equipped)) {
        state.equippedByMember = equipped;
        recomputeEquipped();
      }
    } catch { /* retain local equipment ownership */ }
  }
  if (params.has("storyOutcomes")) {
    try {
      const outcomes = JSON.parse(params.get("storyOutcomes") || "[]");
      if (Array.isArray(outcomes)) state.storyOutcomes = [...new Set(outcomes.filter((value) => typeof value === "string"))];
    } catch { /* retain local story outcomes */ }
  }
  if (params.has("includeCamp")) state.includeCampPlans = params.get("includeCamp") === "true";
  const focused = params.get("focus");
  if (focused && state.data.walkthrough.some((step) => step.id === focused)) state.focusedWalkthroughStepId = focused;
  if (params.has("builds")) state.activeBuilds = [...new Set(partyBuilds)];
  if (params.has("done")) state.done = new Set(completed);
  if (build && state.data.builds.some((entry) => entry.id === build)) {
    els.build.value = build;
    if (!params.has("builds")) state.activeBuilds = [build];
  }

  const item = params.get("item");
  if (item) {
    els.region.value = "all";
    state.lastRegion = "all";
    els.search.value = item;
    els.item.checked = true;
  }

  const requestedTab = params.get("tab");
  const tab = requestedTab === "loadout" ? "party" : requestedTab;
  if (["walkthrough", "route", "party", "equipment", "warnings"].includes(tab)) setTab(tab);
  if (["party", "roster", "builds", "done", "walkthrough", "equipped", "storyOutcomes", "includeCamp"].some((key) => params.has(key))) syncRunState();
  return item ? state.data.markers.find((marker) => marker.type === "item" && marker.name === item) : null;
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

function setTab(tab) {
  state.tab = tab;
  Object.entries(els.tabs).forEach(([name, button]) => {
    button.classList.toggle("active", name === tab);
    button.setAttribute("aria-selected", String(name === tab));
  });
  Object.entries(els.pages).forEach(([name, page]) => { page.hidden = name !== tab; });
  if (tab === "walkthrough") renderWalkthrough();
  if (tab === "party") renderParty();
  if (tab === "equipment") renderEquipment();
  if (tab === "warnings") renderWarnings();
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

function clearSelection() {
  if (state.selectedId === null) return;
  state.selectedId = null;
  render();
}

function selectMarker(marker, center) {
  state.selectedId = marker.id;
  render();
  const target = state.leafletMarkers.get(marker.id);
  if (target) {
    const latlng = target.getLatLng();
    if (center) {
      state.map.flyTo(latlng, Math.max(state.map.getZoom(), 13), { duration: 0.6 });
    } else {
      state.map.panTo(latlng, { animate: true, duration: 0.4 });
    }
    target.openTooltip();
  }
}

function showWalkthroughMarker(markerId) {
  const marker = state.data.markers.find((entry) => entry.id === markerId);
  if (!marker) return;
  els.region.value = state.data.regions.includes(marker.region) ? marker.region : "all";
  state.lastRegion = els.region.value;
  if (marker.type === "fight") {
    els.major.checked = true;
    els.minor.checked = true;
  } else {
    els.item.checked = true;
  }
  selectMarker(marker, true);
}

// ---------------------------------------------------------------------------
// Top-level render
// ---------------------------------------------------------------------------

// Single invalidation entry: every state change funnels through here so no
// call site has to remember which panels to refresh.
function render({ fit = false } = {}) {
  els.levelValue.textContent = els.level.value;
  const markers = visibleMarkers();
  if (state.selectedId && !markers.some((marker) => marker.id === state.selectedId)) {
    state.selectedId = null;
  }
  renderRoute(markers);
  renderWalkthrough();
  renderMarkers(markers, { fit, onSelect: (marker) => selectMarker(marker, false) });
  renderDetail();
  updateWarningsBadge();
  renderEquipment();
  if (state.tab === "party") renderParty();
  if (state.tab === "warnings") renderWarnings();
}

function setMissingOnly(enabled) {
  state.missingOnly = enabled;
  if (enabled) els.item.checked = true;
  render({ fit: enabled });
  if (state.tab === "equipment") renderEquipment();
}

function bindEvents() {
  els.region.addEventListener("change", () => {
    const changed = els.region.value !== state.lastRegion;
    state.lastRegion = els.region.value;
    render({ fit: changed });
  });
  [els.level, els.build, els.search, els.major, els.minor, els.item, els.hideDone]
    .forEach((control) => control.addEventListener("input", () => render()));
  els.labels.addEventListener("input", () => { state.showLabels = els.labels.checked; render(); });

  document.querySelector("#resetButton").addEventListener("click", () => {
    els.region.value = state.data.regions.includes("Wilderness") ? "Wilderness" : "all";
    state.lastRegion = els.region.value;
    els.level.value = "4"; els.build.value = "all"; els.search.value = "";
    els.major.checked = true; els.minor.checked = true; els.item.checked = true;
    els.hideDone.checked = true; els.labels.checked = false; state.showLabels = false;
    state.missingOnly = false;
    render({ fit: true });
  });

  Object.entries(els.tabs).forEach(([name, button]) => button.addEventListener("click", () => setTab(name)));
  els.missingOnlyBtn.addEventListener("click", () => setMissingOnly(!state.missingOnly));
  els.exportMarkersBtn.addEventListener("click", () => {
    previewMarkerExport().catch((error) => { els.summary.textContent = error.message; });
  });
  els.downloadMarkersBtn.addEventListener("click", downloadMarkerExport);
  els.confirmMarkersBtn.addEventListener("click", () => {
    confirmMarkerExport().catch((error) => { els.markerExportWarnings.innerHTML = `<p>⚠ ${escapeHtml(error.message)}</p>`; });
  });

  // Panels re-render their innerHTML constantly, so events are delegated to
  // the stable containers instead of re-bound per render.
  els.walkthroughList.addEventListener("click", (event) => {
    const closeDetail = event.target.closest("[data-walk-detail-close]");
    if (closeDetail) {
      state.selectedWalkthroughStepId = null;
      render();
      return;
    }
    const focus = event.target.closest("[data-walk-focus]");
    if (focus) {
      if (focusWalkthroughStep(focus.dataset.walkFocus)) render();
      return;
    }
    const outcome = event.target.closest("[data-walk-outcome]");
    if (outcome) {
      state.walkthroughOutcomes[outcome.dataset.stepId] = outcome.dataset.walkOutcome;
      if (setWalkthroughStatus(outcome.dataset.stepId, "done")) render();
      return;
    }
    const action = event.target.closest("[data-walk-status]");
    if (action) {
      if (action.dataset.walkStatus === "revisit") delete state.walkthroughOutcomes[action.dataset.stepId];
      if (setWalkthroughStatus(action.dataset.stepId, action.dataset.walkStatus)) render();
      return;
    }
    const mapButton = event.target.closest("[data-walk-map]");
    if (mapButton) { showWalkthroughMarker(mapButton.dataset.walkMap); return; }
    const select = event.target.closest("[data-walk-select]");
    if (select) {
      state.selectedWalkthroughStepId = state.selectedWalkthroughStepId === select.dataset.walkSelect ? null : select.dataset.walkSelect;
      render();
    }
  });

  els.routeList.addEventListener("click", (event) => {
    const equip = event.target.closest("[data-equip]");
    if (equip) { toggleEquipped(equip.dataset.equip); render(); return; }
    const card = event.target.closest(".route-card");
    if (!card) return;
    const marker = state.data.markers.find((entry) => entry.id === card.dataset.id);
    if (!marker) return;
    if (event.target.matches("input[type=checkbox]")) {
      if (event.target.checked) state.done.add(marker.id); else state.done.delete(marker.id);
      syncRunState();
      render();
      return;
    }
    selectMarker(marker, true);
  });

  // The detail card rebuilds its innerHTML each render, so its equip button
  // is delegated here instead of re-bound per render.
  els.detail.addEventListener("click", (event) => {
    const equip = event.target.closest("[data-equip]");
    if (equip) { toggleEquipped(equip.dataset.equip); render(); }
  });

  els.partyPanel.addEventListener("click", (event) => {
    const outcome = event.target.closest("[data-story-outcome]");
    if (outcome) {
      toggleStoryOutcome(outcome.dataset.storyOutcome);
      render();
      return;
    }
    const pick = event.target.closest("[data-pick]");
    if (pick) {
      const id = pick.dataset.pick;
      state.activeBuilds = state.activeBuilds.includes(id)
        ? state.activeBuilds.filter((entry) => entry !== id)
        : [...state.activeBuilds, id].slice(0, 4);
      syncRunState();
      render();
    }
  });
  els.partyPanel.addEventListener("change", (event) => {
    const status = event.target.closest("[data-roster-status]");
    if (status) {
      const member = state.roster.find((entry) => entry.id === status.dataset.rosterStatus);
      if (["dead", "departed"].includes(status.value) && member?.status !== status.value) {
        const impact = member?.status === "active" ? "They will stop contributing to readiness. " : "";
        const preserved = member?.buildId ? "Their saved build, level, and equipment plan will be preserved. " : "Their level and notes will be preserved. ";
        if (!window.confirm(`${impact}${preserved}Story outcomes and rewards remain separate confirmations.`)) {
          status.value = member?.status || "camp";
          return;
        }
      }
      if (!updateRosterMember(status.dataset.rosterStatus, { status: status.value })) {
        const reason = status.value === "active" && !["active", "camp"].includes(member?.status)
          ? `Confirm that ${member?.name || "this companion"} is available again before activating them.`
          : "Active party is full. Send someone to camp first.";
        window.alert(reason);
        status.value = state.roster.find((member) => member.id === status.dataset.rosterStatus)?.status || "camp";
      }
      render();
      return;
    }
    const level = event.target.closest("[data-roster-level]");
    if (level) {
      updateRosterMember(level.dataset.rosterLevel, { level: Number(level.value) });
      render();
      return;
    }
    const build = event.target.closest("[data-roster-build]");
    if (build) {
      updateRosterMember(build.dataset.rosterBuild, { buildId: build.value || null });
      render();
      return;
    }
    const includeCamp = event.target.closest("[data-include-camp]");
    if (includeCamp) {
      state.includeCampPlans = includeCamp.checked;
      syncRunState();
      render();
    }
  });

  els.equipmentPanel.addEventListener("click", (event) => {
    const assignment = event.target.closest("[data-member-equip]");
    if (assignment) {
      toggleMemberEquipment(assignment.dataset.memberId, assignment.dataset.memberEquip);
      render();
      return;
    }
    const card = event.target.closest(".equip-card");
    if (card) {
      const marker = state.data.markers.find((entry) => entry.id === card.dataset.id);
      if (marker) { setTab("route"); selectMarker(marker, true); }
    }
  });
  els.equipmentPanel.addEventListener("change", (event) => {
    const includeCamp = event.target.closest("[data-include-camp]");
    if (!includeCamp) return;
    state.includeCampPlans = includeCamp.checked;
    syncRunState();
    render();
  });

  els.warningsPanel.addEventListener("click", (event) => {
    if (event.target.closest(".ack")) return; // handled by the change listener
    const card = event.target.closest(".warning-card[data-id]");
    if (!card) return;
    const marker = state.data.markers.find((entry) => entry.id === card.dataset.id);
    if (marker) { setTab("route"); selectMarker(marker, true); }
  });
  els.warningsPanel.addEventListener("change", (event) => {
    const box = event.target.closest("[data-ack]");
    if (!box) return;
    if (box.checked) state.ackTimed.add(box.dataset.ack); else state.ackTimed.delete(box.dataset.ack);
    persistLocal();
    renderWarnings();
  });

  document.querySelector("#zoomIn").addEventListener("click", () => state.map.zoomIn());
  document.querySelector("#zoomOut").addEventListener("click", () => state.map.zoomOut());
  document.querySelector("#fitMap").addEventListener("click", () => render({ fit: true }));
  els.followBtn.addEventListener("click", () => setFollow(!state.follow));
  els.locateBtn.addEventListener("click", () => {
    if (state.player) state.map.flyTo([state.player.lat, state.player.lng], Math.max(state.map.getZoom(), 13), { duration: 0.5 });
  });
}

fetch("/api/act1/markers")
  .then((response) => { if (!response.ok) throw new Error(`HTTP ${response.status}`); return response.json(); })
  .then(async (data) => {
    state.data = data;
    await restoreRunState();
    populateFilters();
    initMap({ onBackgroundClick: clearSelection });
    bindEvents();
    const requestedMarker = applyURLIntent();
    render({ fit: true });
    if (requestedMarker) selectMarker(requestedMarker, true);
    pollPosition();
    setInterval(pollPosition, 2000);
  })
  .catch((error) => { els.summary.textContent = "Map failed to load"; els.routeList.innerHTML = `<p>${escapeHtml(error.message)}</p>`; });
