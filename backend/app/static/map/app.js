// Entry module: filtering, tabs, selection, the single render() invalidation
// point, ALL event delegation, and boot. The modules under ./js/ export pure
// render/template functions and state mutators; only this file binds listeners
// and re-renders, so no module ever needs to import app.js back.

import {
  state, els, escapeHtml, persistLocal, syncRunState, restoreRunState,
  isItemEquipped, isResolved, toggleEquipped, toggleMemberEquipment,
  updateRosterMember, toggleStoryOutcome,
  activateMember, recordRecruited, returnToCamp, addHireling, swapActiveMember,
  dismissMember, renameMember, assignBuild, applyAbilitySetup, resetMemberPlan,
  setIncludeCampPlans, toggleAbilitySource, sourceOwner, importBuild, canActivateRosterStatus,
} from "./js/state.js";
import { initMap, renderMarkers, pollPosition, setFollow } from "./js/map-layer.js";
import { renderWalkthrough, setWalkthroughStatus, focusWalkthroughStep } from "./js/walkthrough.js";
import {
  renderRoute, renderParty, renderEquipment, renderWarnings, updateWarningsBadge,
  renderDetail,
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

// View params (level, build filter, item search, tab) always apply. Returns
// the marker matching an `item` deep link so boot can select it.
function applyViewParams(params) {
  const level = Number(params.get("level"));
  if (Number.isInteger(level) && level >= 1 && level <= 12) els.level.value = String(level);

  const build = params.get("build");
  if (build && state.data.builds.some((entry) => entry.id === build)) els.build.value = build;

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

function focusPartyHeading() {
  requestAnimationFrame(() => els.partyPanel.querySelector(".party-page-title")?.focus());
}

// Confirmation wrapper around the assignBuild mutator: replacing a build
// clears transient state, so a build already carrying any asks first.
function assignBrowserBuild(member, buildId) {
  if ((member.buildId || null) === (buildId || null)) return true;
  const hasTransientState = (member.abilityModifiers || []).some((modifier) => modifier.kind !== "permanent")
    || (state.equippedByMember[member.id] || []).length || member.appliedAbilitySetupId;
  if (member.buildId && hasTransientState && !window.confirm("Replace this build? Permanent rewards stay with the character; temporary effects and setup confirmation will be cleared.")) return false;
  return assignBuild(member.id, buildId);
}

// ---------------------------------------------------------------------------
// Party actions. Templates emit data-action/data-id; these tables map each
// action to its state.js mutator. Handlers keep only confirm/alert prompts,
// focus management, and rendering — every mutation ends in the full render().
// ---------------------------------------------------------------------------

const PARTY_CLICK_ACTIONS = {
  "open-member": (el) => {
    state.partyMemberReturnView = state.partyView === "setup" ? "setup" : "guidance";
    state.selectedPartyMemberId = el.dataset.id;
    state.partyView = "member";
    render();
    focusPartyHeading();
  },
  "show-setup": () => {
    state.partyView = "setup";
    render();
    focusPartyHeading();
  },
  "show-guidance": () => {
    state.partyView = "guidance";
    state.selectedPartyMemberId = null;
    render();
    focusPartyHeading();
  },
  "activate-member": (el) => {
    if (!activateMember(el.dataset.id)) window.alert("The active party already has four members. Use Swap on an active slot.");
    render();
  },
  "record-recruited": (el) => {
    recordRecruited(el.dataset.id);
    render();
  },
  "return-camp": (el) => {
    returnToCamp(el.dataset.id);
    render();
  },
  "add-hireling": (el) => {
    if (addHireling(el.dataset.id)) render();
  },
  "apply-setup": (el) => {
    applyAbilitySetup(state.selectedPartyMemberId, el.dataset.id);
    render();
  },
  "toggle-ability-source": (el) => {
    const member = state.roster.find((entry) => entry.id === state.selectedPartyMemberId);
    const build = state.data.builds.find((entry) => entry.id === member?.buildId);
    const source = build?.abilitySources?.find((entry) => entry.id === el.dataset.id);
    if (!member || !source) return;
    const applied = el.dataset.sourceApplied === "true";
    if (!applied && (state.data.act < (source.minimumAct || 1) || Number(member.level) < source.minimumLevel)) {
      window.alert(`${source.label} is planned for Act ${source.minimumAct || 1}, level ${source.minimumLevel} or later.`);
      return;
    }
    if (!applied && source.uniqueAcrossParty) {
      const owner = sourceOwner(source);
      if (owner && owner.id !== member.id && !window.confirm(`Move ${source.label} from ${owner.name} to ${member.name}?`)) return;
    }
    toggleAbilitySource(member.id, source.id, applied);
    render();
  },
  "open-loadout": () => setTab("equipment"),
  "reset-member": (el) => {
    if (!state.roster.some((entry) => entry.id === el.dataset.id)) return;
    if (!window.confirm("Reset this planner record? This is not a Withers respec. The assigned build, recorded ability sources, and equipment confirmations will be removed.")) return;
    resetMemberPlan(el.dataset.id);
    render();
  },
  "dismiss-hireling": (el) => {
    const member = state.roster.find((entry) => entry.id === el.dataset.id);
    if (!member?.isHireling || member.status === "active") return;
    if (!window.confirm(`Dismiss ${member.name} and remove their equipment assignments?`)) return;
    dismissMember(member.id);
    state.partyView = "setup";
    state.selectedPartyMemberId = null;
    render();
    focusPartyHeading();
  },
  "import-build": (el) => {
    const input = els.partyPanel.querySelector("[data-build-import-url]");
    const url = input?.value.trim();
    if (!url) { input?.focus(); return; }
    el.disabled = true;
    importBuild(url)
      .then((build) => {
        const member = state.roster.find((entry) => entry.id === el.dataset.id);
        if (member) assignBrowserBuild(member, build.id);
        render();
      })
      .catch((error) => { window.alert(error.message); el.disabled = false; });
  },
  "toggle-story-outcome": (el) => {
    toggleStoryOutcome(el.dataset.id);
    render();
  },
};

const PARTY_CHANGE_ACTIONS = {
  "swap-member": (el) => {
    if (!el.value) return;
    swapActiveMember(el.dataset.id, el.value);
    render();
  },
  "set-status": (el) => {
    const member = state.roster.find((entry) => entry.id === el.dataset.id);
    if (["dead", "departed"].includes(el.value) && member?.status !== el.value) {
      const impact = member?.status === "active" ? "They will stop contributing to readiness. " : "";
      const preserved = member?.buildId ? "Their saved build, level, and equipment plan will be preserved. " : "Their level and notes will be preserved. ";
      if (!window.confirm(`${impact}${preserved}Story outcomes and rewards remain separate confirmations.`)) {
        el.value = member?.status || "camp";
        return;
      }
    }
    if (!updateRosterMember(el.dataset.id, { status: el.value })) {
      const reason = el.value === "active" && !canActivateRosterStatus(member?.status)
        ? `Confirm that ${member?.name || "this companion"} is available again before activating them.`
        : "Active party is full. Send someone to camp first.";
      window.alert(reason);
      el.value = state.roster.find((entry) => entry.id === el.dataset.id)?.status || "camp";
    }
    render();
  },
  "set-level": (el) => {
    updateRosterMember(el.dataset.id, { level: Number(el.value) });
    render();
  },
  "set-build": (el) => {
    const member = state.roster.find((entry) => entry.id === el.dataset.id);
    if (member && !assignBrowserBuild(member, el.value || null)) el.value = member.buildId || "";
    render();
  },
  "toggle-include-camp": (el) => {
    setIncludeCampPlans(el.checked);
    render();
  },
};

// The custom-character name field syncs on every keystroke without a
// re-render: rebuilding the panel mid-typing would drop the caret.
const PARTY_INPUT_ACTIONS = {
  "rename-member": (el) => renameMember(el.dataset.id, el.value),
};

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
    const el = event.target.closest("[data-action]");
    PARTY_CLICK_ACTIONS[el?.dataset.action]?.(el);
  });
  els.partyPanel.addEventListener("change", (event) => {
    const el = event.target.closest("[data-action]");
    PARTY_CHANGE_ACTIONS[el?.dataset.action]?.(el);
  });
  els.partyPanel.addEventListener("input", (event) => {
    const el = event.target.closest("[data-action]");
    PARTY_INPUT_ACTIONS[el?.dataset.action]?.(el);
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
    setIncludeCampPlans(includeCamp.checked);
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
    // Run state comes exclusively from the shared store (the native app
    // writes it before opening the map); the URL carries view intent only.
    await restoreRunState();
    populateFilters();
    initMap({ onBackgroundClick: clearSelection });
    bindEvents();
    const params = new URLSearchParams(window.location.search);
    const requestedMarker = applyViewParams(params);
    render({ fit: true });
    if (requestedMarker) selectMarker(requestedMarker, true);
    pollPosition();
    setInterval(pollPosition, 2000);
  })
  .catch((error) => { els.summary.textContent = "Map failed to load"; els.routeList.innerHTML = `<p>${escapeHtml(error.message)}</p>`; });
