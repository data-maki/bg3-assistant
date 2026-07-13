const state = {
  data: null,
  selectedId: null,
  done: new Set(JSON.parse(localStorage.getItem("bg3-act1-done") || "[]")),
  equipped: new Set(JSON.parse(localStorage.getItem("bg3-act1-equipped") || "[]")),
  equippedByMember: JSON.parse(localStorage.getItem("bg3-act1-equipped-by-member") || "{}"),
  activeBuilds: JSON.parse(localStorage.getItem("bg3-act1-builds") || "[]"),
  party: JSON.parse(localStorage.getItem("bg3-act1-party") || "[]"),
  ackTimed: new Set(JSON.parse(localStorage.getItem("bg3-act1-timed-ack") || "[]")),
  missingOnly: false,
  tab: "route",
  showLabels: false,
  lastRegion: null,
  map: null,
  markerLayer: null,
  leafletMarkers: new Map(),
  player: null,
  playerMarker: null,
  follow: false,
  loadoutSyncTimer: null,
  markerExport: null,
};

// Approximate BG3 world metres per MapGenie degree, from the surface affine fit.
const METERS_PER_LNG_DEGREE = 2551;
const METERS_PER_LAT_DEGREE = 2277;

const els = {
  region: document.querySelector("#regionFilter"),
  level: document.querySelector("#levelFilter"),
  levelValue: document.querySelector("#levelValue"),
  build: document.querySelector("#buildFilter"),
  search: document.querySelector("#searchFilter"),
  major: document.querySelector("#majorFilter"),
  minor: document.querySelector("#minorFilter"),
  item: document.querySelector("#itemFilter"),
  hideDone: document.querySelector("#hideDoneFilter"),
  labels: document.querySelector("#labelsFilter"),
  summary: document.querySelector("#summaryCount"),
  routeTitle: document.querySelector("#routeTitle"),
  routeList: document.querySelector("#routeList"),
  partyPanel: document.querySelector("#partyPanel"),
  equipmentPanel: document.querySelector("#equipmentPanel"),
  warningsPanel: document.querySelector("#warningsPanel"),
  equipmentBadge: document.querySelector("#equipmentBadge"),
  equipmentActLabel: document.querySelector("#equipmentActLabel"),
  warningsBadge: document.querySelector("#warningsBadge"),
  missingOnlyBtn: document.querySelector("#missingOnlyBtn"),
  tabs: {
    route: document.querySelector("#tabRoute"),
    party: document.querySelector("#tabParty"),
    equipment: document.querySelector("#tabEquipment"),
    warnings: document.querySelector("#tabWarnings"),
  },
  pages: {
    route: document.querySelector("#panelRoute"),
    party: document.querySelector("#panelParty"),
    equipment: document.querySelector("#panelEquipment"),
    warnings: document.querySelector("#panelWarnings"),
  },
  mapEl: document.querySelector("#leafletMap"),
  emptyMap: document.querySelector("#emptyMap"),
  detail: document.querySelector("#detailCard"),
  mapgenie: document.querySelector("#mapgenieLink"),
  liveStatus: document.querySelector("#liveStatus"),
  followBtn: document.querySelector("#followBtn"),
  locateBtn: document.querySelector("#locateBtn"),
  exportMarkersBtn: document.querySelector("#exportMarkersBtn"),
  markerExportDialog: document.querySelector("#markerExportDialog"),
  markerExportSummary: document.querySelector("#markerExportSummary"),
  markerExportWarnings: document.querySelector("#markerExportWarnings"),
  markerExportList: document.querySelector("#markerExportList"),
  markerExportFingerprint: document.querySelector("#markerExportFingerprint"),
  downloadMarkersBtn: document.querySelector("#downloadMarkersBtn"),
  confirmMarkersBtn: document.querySelector("#confirmMarkersBtn"),
};

const escapeHtml = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#039;", '"': "&quot;",
}[char]));

const shortName = (marker) => (marker.name.length > 26 ? `${marker.name.slice(0, 24)}…` : marker.name);

function markerClass(marker) {
  return marker.type === "item" ? "item" : marker.importance;
}

function isItemEquipped(marker) {
  return marker.type === "item" && state.equipped.has(marker.itemKey);
}

function isResolved(marker) {
  return marker.type === "item" ? isItemEquipped(marker) : state.done.has(marker.id);
}

function iconUrl(marker) {
  return marker.icon || null;
}

// ---------------------------------------------------------------------------
// Persistence: run state (done fights + equipped gear + active builds) syncs
// to the backend so it survives browser changes; localStorage covers offline.
// ---------------------------------------------------------------------------

function persistLocal() {
  localStorage.setItem("bg3-act1-done", JSON.stringify([...state.done]));
  localStorage.setItem("bg3-act1-equipped", JSON.stringify([...state.equipped]));
  localStorage.setItem("bg3-act1-equipped-by-member", JSON.stringify(state.equippedByMember));
  localStorage.setItem("bg3-act1-builds", JSON.stringify(state.activeBuilds));
  localStorage.setItem("bg3-act1-party", JSON.stringify(state.party));
  localStorage.setItem("bg3-act1-timed-ack", JSON.stringify([...state.ackTimed]));
}

function syncRunState() {
  persistLocal();
  clearTimeout(state.loadoutSyncTimer);
  state.loadoutSyncTimer = setTimeout(() => {
    fetch("/api/run-state", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        equipped: [...state.equipped],
        equippedByMember: state.equippedByMember,
        builds: state.activeBuilds,
        done: [...state.done],
        party: state.party,
      }),
    }).catch(() => {});
  }, 350);
}

async function restoreRunState() {
  try {
    const payload = await (await fetch("/api/run-state")).json();
    const hasServerState = payload.equipped?.length || payload.builds?.length || payload.done?.length || payload.party?.length;
    if (hasServerState) {
      (payload.equipped || []).forEach((key) => state.equipped.add(key));
      (payload.done || []).forEach((id) => state.done.add(id));
      state.equippedByMember = payload.equippedByMember || state.equippedByMember;
      Object.values(state.equippedByMember).flat().forEach((key) => state.equipped.add(key));
      if (payload.party?.length) state.party = payload.party;
      state.activeBuilds = [...new Set([...(payload.builds || []), ...state.activeBuilds])];
      persistLocal();
    } else if (state.equipped.size || state.activeBuilds.length || state.done.size) {
      syncRunState(); // seed the backend from this browser's saved state
    }
  } catch { /* backend offline: localStorage still applies */ }
}

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
      state.activeBuilds = [...new Set(state.party.map((member) => member.buildId).filter((id) => state.data.builds.some((entry) => entry.id === id)))];
    } catch { state.party = []; }
  }
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
  if (["route", "party", "equipment", "warnings"].includes(tab)) setTab(tab);
  if (params.has("party") || params.has("builds") || params.has("done")) syncRunState();
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
  if (tab === "party") renderParty();
  if (tab === "equipment") renderEquipment();
  if (tab === "warnings") renderWarnings();
}

// ---------------------------------------------------------------------------
// Deterministic one-shot BG3 marker export
// ---------------------------------------------------------------------------

async function previewMarkerExport() {
  const selectedBuild = els.build.value !== "all" ? [els.build.value] : [];
  const buildIds = state.activeBuilds.length ? state.activeBuilds : selectedBuild;
  const response = await fetch("/api/marker-sync/preview", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      act: state.data.act,
      partyLevel: Number(els.level.value),
      buildIds,
      completedCheckpointIds: [...state.done],
      equippedItemKeys: [...state.equipped],
    }),
  });
  if (!response.ok) throw new Error(`Marker preview failed: HTTP ${response.status}`);
  state.markerExport = await response.json();
  renderMarkerExport();
  els.markerExportDialog.showModal();
}

function renderMarkerExport() {
  const payload = state.markerExport;
  if (!payload) return;
  const fights = payload.markers.filter((marker) => marker.type === "fight").length;
  const items = payload.markers.length - fights;
  els.markerExportSummary.textContent = `${payload.phase} · party L${payload.partyLevel} · ${fights} fights · ${items} equipment locations. Only this reviewed queue will be offered to the BG3 marker sync.`;
  els.markerExportWarnings.innerHTML = payload.warnings.map((warning) => `<p>⚠ ${escapeHtml(warning)}</p>`).join("");
  els.markerExportList.innerHTML = payload.markers.length ? payload.markers.map((marker) => `
    <article class="marker-export-row">
      <span class="marker-export-kind">${escapeHtml(marker.type)}</span>
      <div><strong>${escapeHtml(marker.label)}</strong><small>${escapeHtml(marker.region)} · ${escapeHtml(marker.area)} · ${escapeHtml(marker.precision)} pin</small></div>
      <span class="marker-export-level" title="${marker.levelSource === "guide_fact" ? "Guide minimum" : "Selected-level suggestion"}">L${marker.recommendedLevel}</span>
    </article>`).join("") : `<p class="empty-note">Nothing to export for this level and regional phase.</p>`;
  els.markerExportFingerprint.textContent = `sync ${payload.fingerprint}`;
  els.downloadMarkersBtn.disabled = payload.markers.length === 0;
  els.confirmMarkersBtn.disabled = payload.markers.length === 0 || payload.alreadySynced;
  els.confirmMarkersBtn.textContent = payload.alreadySynced ? "Already placed ✓" : "Placed in BG3";
}

function downloadMarkerExport() {
  if (!state.markerExport?.markers.length) return;
  const artifact = { formatVersion: 1, generatedAt: new Date().toISOString(), ...state.markerExport };
  const url = URL.createObjectURL(new Blob([JSON.stringify(artifact, null, 2)], { type: "application/json" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `bg3-markers-act${artifact.act}-l${artifact.partyLevel}-${artifact.fingerprint}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

async function confirmMarkerExport() {
  if (!state.markerExport?.fingerprint) return;
  const response = await fetch("/api/marker-sync/confirm", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fingerprint: state.markerExport.fingerprint }),
  });
  if (!response.ok) throw new Error("Marker queue changed; export it again before confirming.");
  state.markerExport.alreadySynced = true;
  renderMarkerExport();
}

// ---------------------------------------------------------------------------
// Route list (left panel)
// ---------------------------------------------------------------------------

function dangerBadge(marker) {
  if (marker.type !== "fight") return "";
  const danger = marker.danger || "moderate";
  if (danger === "extreme" || marker.legendaryAction) {
    return `<span class="badge run-ender" title="Legendary action / run-ender risk">☠ ${escapeHtml(danger)}</span>`;
  }
  if (danger === "high") return `<span class="badge danger-high">⚠ high</span>`;
  return "";
}

function renderRoute(markers) {
  els.routeTitle.textContent = els.region.value === "all" ? "All Act 1 locations" : els.region.value;
  const equippedCount = itemKeys().filter((key) => state.equipped.has(key)).length;
  els.summary.textContent = `${markers.length} visible · ${state.done.size} fights done · ${equippedCount} items equipped`;
  els.routeList.innerHTML = markers.map((marker) => {
    const type = markerClass(marker);
    const level = Number(els.level.value);
    const resolved = isResolved(marker);
    const ready = marker.type === "fight" && level >= marker.minimumLevel;
    const statusBadge = marker.type === "fight"
      ? `<span class="badge ${ready ? "ready" : "under"}">${ready ? "Ready" : `Wait for L${marker.minimumLevel}`}</span>`
      : `<span class="badge">${escapeHtml(marker.priority)}</span>`;
    const thumb = marker.type === "item"
      ? (iconUrl(marker)
        ? `<img class="item-thumb ${resolved ? "item-thumb--equipped" : ""}" src="${escapeHtml(iconUrl(marker))}" alt="" loading="lazy" />`
        : `<span class="item-thumb item-thumb--empty"></span>`)
      : `<span class="fight-glyph fight-glyph--${type}">${marker.importance === "major" ? "⚔" : "✦"}</span>`;
    const check = marker.type === "item"
      ? `<button class="equip-toggle ${resolved ? "on" : ""}" data-equip="${escapeHtml(marker.itemKey)}" title="${resolved ? "Equipped — click to unequip" : "Mark as equipped"}">${resolved ? "✓" : "+"}</button>`
      : `<input type="checkbox" aria-label="Mark ${escapeHtml(marker.name)} completed" ${resolved ? "checked" : ""} />`;
    return `<article class="route-card ${resolved ? "done" : ""} ${state.selectedId === marker.id ? "selected" : ""}" data-id="${marker.id}">
      ${check}
      ${thumb}
      <div>
        <h3>${escapeHtml(marker.name)}</h3>
        <p>${escapeHtml(marker.area)} · ${marker.precision === "exact" ? "exact" : "area pin"}</p>
        <div class="badges"><span class="badge ${type}">${marker.type === "item" ? escapeHtml(marker.slot || "Item") : marker.importance === "major" ? "Major" : "Minor"}</span>${statusBadge}${dangerBadge(marker)}</div>
      </div>
    </article>`;
  }).join("") || `<p class="subtitle empty-note">No locations match the current filters.</p>`;
}

// ---------------------------------------------------------------------------
// Loadout tab (builds + equipped-vs-missing gear)
// ---------------------------------------------------------------------------

function itemMarkers() {
  const seen = new Set();
  return state.data.markers.filter((marker) => {
    if (marker.type !== "item" || seen.has(marker.itemKey)) return false;
    seen.add(marker.itemKey);
    return true;
  });
}

function itemKeys() {
  return itemMarkers().map((marker) => marker.itemKey);
}

function toggleEquipped(itemKey) {
  if (state.equipped.has(itemKey)) state.equipped.delete(itemKey);
  else state.equipped.add(itemKey);
  syncRunState();
  render();
}

const CLASS_NAMES = ["Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk", "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"];

function classChips(progression) {
  const classes = CLASS_NAMES.filter((name) => progression.includes(name));
  return classes.map((name) => `<span class="class-chip class-chip--${name.toLowerCase()}">${escapeHtml(name)}</span>`).join("");
}

function honorBadge(status) {
  const good = /viable|strong|s-tier|recommended|yes/i.test(status);
  return `<span class="badge ${good ? "ready" : "minor"}" title="${escapeHtml(status)}">${escapeHtml(status.length > 26 ? status.slice(0, 24) + "…" : status)}</span>`;
}

function partyMembers() {
  const validParty = state.party.filter((member) => state.data.builds.some((build) => build.id === member.buildId));
  if (validParty.length) return validParty;
  return state.activeBuilds.map((buildId, index) => ({
    id: `build-slot-${index + 1}`,
    name: `Party member ${index + 1}`,
    level: Number(els.level.value),
    buildId,
  }));
}

function currentBuildStep(build, level) {
  const plan = build?.levels || [];
  return plan.find((row) => row.level === level)
    || [...plan].reverse().find((row) => row.level <= level)
    || plan[0];
}

function renderParty() {
  const members = partyMembers();
  if (!members.length) {
    const choices = state.data.builds.map((build) => `
      <article class="build-card" data-build="${escapeHtml(build.id)}">
        <header><div class="build-title"><h3>${escapeHtml(build.name)}</h3><div class="build-chips">${classChips(build.classProgression)}${honorBadge(build.honorStatus)}</div></div>
        <button class="build-pick" data-pick="${escapeHtml(build.id)}">Add</button></header>
        <p class="build-role">${escapeHtml(build.role)}</p>
      </article>`).join("");
    els.partyPanel.innerHTML = `<p class="panel-note">Open this map from the companion to use its named party, or add reviewed builds here.</p><div class="build-list">${choices}</div>`;
    return;
  }

  els.partyPanel.innerHTML = `<p class="panel-note">Only the action for each member's current level is shown. Equipment is tracked separately.</p><div class="build-list">${members.map((member) => {
    const build = state.data.builds.find((entry) => entry.id === member.buildId);
    const level = Number(member.level) || Number(els.level.value);
    const step = currentBuildStep(build, level);
    return `<article class="build-card active party-member-card" data-build="${escapeHtml(member.buildId)}">
      <header>
        <div class="build-title"><p class="party-member-name">${escapeHtml(member.name)}</p><h3>${escapeHtml(build.name)}</h3></div>
        <span class="party-level">L${level}</span>
      </header>
      <p class="build-role">${escapeHtml(build.role)} · ${escapeHtml(build.finalSplit)}</p>
      ${step ? `<div class="level-now">
        <div class="level-now__badge">L${step.level}</div>
        <div class="level-now__body">
          <strong>${escapeHtml(step.take)}</strong>${step.subclassChoice && step.subclassChoice !== "-" ? ` · ${escapeHtml(step.subclassChoice)}` : ""}
          ${step.choices ? `<p class="level-now__pick"><span>Take</span> ${escapeHtml(step.choices)}</p>` : ""}
          ${step.tactics ? `<p class="level-now__do"><span>Do now</span> ${escapeHtml(step.tactics)}</p>` : ""}
        </div>
      </div>` : `<p class="panel-note">No reviewed step for L${level}.</p>`}
    </article>`;
  }).join("")}</div>`;
}

function memberEquipment(memberId) {
  return new Set(state.equippedByMember[memberId] || []);
}

function toggleMemberEquipment(memberId, itemKey) {
  const assigned = memberEquipment(memberId);
  if (assigned.has(itemKey)) assigned.delete(itemKey);
  else {
    assigned.add(itemKey);
    state.equipped.add(itemKey);
  }
  state.equippedByMember[memberId] = [...assigned];
  syncRunState();
  render();
}

function gearForMember(member) {
  return itemMarkers().filter((marker) => marker.buildIds.includes(member.buildId));
}

function renderEquipment() {
  const members = partyMembers();
  const totals = members.map((member) => {
    const gear = gearForMember(member);
    const assigned = memberEquipment(member.id);
    return { member, gear, assignedCount: gear.filter((marker) => assigned.has(marker.itemKey)).length };
  });
  const assignedCount = totals.reduce((sum, item) => sum + item.assignedCount, 0);
  const gearCount = totals.reduce((sum, item) => sum + item.gear.length, 0);
  els.equipmentBadge.hidden = gearCount === 0;
  els.equipmentBadge.textContent = `${assignedCount}/${gearCount}`;
  els.missingOnlyBtn.classList.toggle("active", state.missingOnly);
  els.missingOnlyBtn.textContent = state.missingOnly ? "Showing missing only ✕" : "Show missing on map";
  if (!members.length) {
    els.equipmentPanel.innerHTML = `<p class="panel-note">Choose party builds first. Equipment will then be separated by character for Act 1.</p>`;
    return;
  }
  els.equipmentPanel.innerHTML = totals.map(({ member, gear, assignedCount: count }) => `
    <section class="member-equipment">
      <header class="member-equipment__header"><div><p class="party-member-name">${escapeHtml(member.name)}</p><h3>${escapeHtml(state.data.builds.find((build) => build.id === member.buildId)?.name || member.buildId)}</h3></div><strong>${count}/${gear.length}</strong></header>
      ${equipmentSheet(member, gear)}
    </section>`).join("");
}

// Canonical inventory order so the equipment sheet reads like a character sheet.
const SLOT_ORDER = [
  "Melee", "Melee / stat stick", "Summoned off-hand weapon", "Ranged",
  "Head", "Chest", "Hands", "Feet", "Amulet", "Ring", "Cloak", "Consumable",
];

function priorityChip(priority) {
  const core = /core|essential|best/i.test(priority);
  return `<span class="prio-chip ${core ? "prio-chip--core" : ""}">${escapeHtml(priority)}</span>`;
}

function equipmentSheet(member, gear) {
  const assigned = memberEquipment(member.id);
  const bySlot = new Map();
  gear.forEach((marker) => {
    const slot = marker.slot || "Other";
    (bySlot.get(slot) || bySlot.set(slot, []).get(slot)).push(marker);
  });
  const slots = [...bySlot.keys()].sort((a, b) => {
    const ia = SLOT_ORDER.indexOf(a), ib = SLOT_ORDER.indexOf(b);
    return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib) || a.localeCompare(b);
  });
  return slots.map((slot) => {
    const items = bySlot.get(slot);
    const slotEquipped = items.filter((m) => assigned.has(m.itemKey)).length;
    return `<section class="equip-slot">
      <div class="equip-slot__label"><span>${escapeHtml(slot)}</span><em>${slotEquipped}/${items.length}</em></div>
      <div class="equip-slot__items">
        ${items.map((marker) => {
          const equipped = assigned.has(marker.itemKey);
          return `<article class="equip-card ${equipped ? "equipped" : ""}" data-id="${escapeHtml(marker.id)}">
            ${iconUrl(marker) ? `<img class="item-thumb ${equipped ? "item-thumb--equipped" : ""}" src="${escapeHtml(iconUrl(marker))}" alt="" loading="lazy" />` : `<span class="item-thumb item-thumb--empty"></span>`}
            <div class="equip-card__body">
              <h3>${escapeHtml(marker.name)}</h3>
              <p>${escapeHtml(marker.area)}</p>
              <div class="equip-card__meta">${priorityChip(marker.priority)}<span class="equip-card__where">📍 ${escapeHtml(marker.region)}</span></div>
            </div>
            <button class="equip-toggle ${equipped ? "on" : ""}" data-member-equip="${escapeHtml(marker.itemKey)}" data-member-id="${escapeHtml(member.id)}" title="${equipped ? `Assigned to ${escapeHtml(member.name)} — click to remove` : `Assign to ${escapeHtml(member.name)}`}">${equipped ? "✓" : "+"}</button>
          </article>`;
        }).join("")}
      </div>
    </section>`;
  }).join("");
}

// ---------------------------------------------------------------------------
// Warnings tab (run-enders + timed/missable events)
// ---------------------------------------------------------------------------

const KIND_META = {
  point_of_no_return: { glyph: "🚪", label: "Point of no return" },
  long_rest: { glyph: "⏳", label: "Long-rest timer" },
  immediate: { glyph: "⚡", label: "Immediate" },
};

function updateWarningsBadge() {
  const pending = (state.data.timedEvents || []).filter(
    (event) => !state.ackTimed.has(event.id) && (event.severity === "critical" || event.severity === "high"),
  ).length;
  els.warningsBadge.hidden = pending === 0;
  els.warningsBadge.textContent = String(pending);
}

function renderWarnings() {
  const level = Number(els.level.value);
  const runEnders = state.data.markers
    .filter((marker) => marker.type === "fight" && (marker.legendaryAction || (marker.failureConditions || []).length))
    .sort((a, b) => (a.routeOrder || 99) - (b.routeOrder || 99));

  const fightCards = runEnders.map((marker) => {
    const under = level < marker.minimumLevel;
    return `<article class="warning-card ${state.done.has(marker.id) ? "done" : ""}" data-id="${escapeHtml(marker.id)}">
      <header>
        <h3>${escapeHtml(marker.name)}</h3>
        <span class="badge ${under ? "under" : "ready"}">${under ? `L${marker.minimumLevel} needed` : "Level OK"}</span>
      </header>
      ${marker.legendaryAction ? `<p class="legendary">☠ <strong>Legendary:</strong> ${escapeHtml(marker.legendaryAction)}</p>` : ""}
      ${(marker.failureConditions || []).slice(0, 2).map((text) => `<p class="fail-condition">✖ ${escapeHtml(text)}</p>`).join("")}
    </article>`;
  }).join("");

  const events = (state.data.timedEvents || []).slice().sort((a, b) => {
    const order = { critical: 0, high: 1, moderate: 2, low: 3 };
    return (order[a.severity] ?? 4) - (order[b.severity] ?? 4);
  });
  const eventCards = events.map((event) => {
    const meta = KIND_META[event.kind] || { glyph: "•", label: event.kind };
    const acked = state.ackTimed.has(event.id);
    return `<article class="warning-card timed ${acked ? "done" : ""} sev-${escapeHtml(event.severity)}">
      <header>
        <h3>${meta.glyph} ${escapeHtml(event.name)}</h3>
        <label class="ack"><input type="checkbox" data-ack="${escapeHtml(event.id)}" ${acked ? "checked" : ""} /> handled</label>
      </header>
      <p><strong>${escapeHtml(meta.label)}:</strong> ${escapeHtml(event.trigger)}</p>
      <p><strong>Deadline:</strong> ${escapeHtml(event.deadline)}</p>
      <p class="consequence">${escapeHtml(event.consequence)}</p>
    </article>`;
  }).join("");

  els.warningsPanel.innerHTML = `
    <h4 class="slot-heading">Run-enders on the route</h4>
    <p class="panel-note">Reviewed fights with legendary actions or known wipe conditions, in route order. Click one to see it on the map.</p>
    ${fightCards}
    <h4 class="slot-heading">Timed &amp; missable (Act 1)</h4>
    <p class="panel-note">Check off the ones you've handled. Sourced from bg3.wiki's time-sensitive list.</p>
    ${eventCards}
    <p class="panel-note"><a href="https://bg3.wiki/wiki/Time-sensitive_activities" target="_blank" rel="noreferrer">Full time-sensitive list on bg3.wiki ↗</a></p>`;

  updateWarningsBadge();
}

// ---------------------------------------------------------------------------
// Leaflet map
// ---------------------------------------------------------------------------

const TRANSPARENT_PX = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";

function initMap() {
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

  map.on("click", () => clearSelection());
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

async function pollPosition() {
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

function setFollow(enabled) {
  state.follow = enabled;
  els.followBtn.classList.toggle("active", enabled);
  if (enabled && state.player) state.map.panTo([state.player.lat, state.player.lng]);
}

function distanceLabel(marker) {
  if (!state.player) return "";
  const dLngMeters = (marker.lng - state.player.lng) * METERS_PER_LNG_DEGREE;
  const dLatMeters = (marker.lat - state.player.lat) * METERS_PER_LAT_DEGREE;
  const meters = Math.round(Math.hypot(dLngMeters, dLatMeters));
  return `~${meters} m from your position`;
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

function renderMarkers(markers, { fit = false } = {}) {
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
      selectMarker(marker, false);
    });
    leafletMarker.addTo(state.markerLayer);
    state.leafletMarkers.set(marker.id, leafletMarker);
  });

  if (fit && latlngs.length) {
    state.map.fitBounds(L.latLngBounds(latlngs).pad(0.25), { maxZoom: state.data.mapgenie.maxZoom - 2 });
  }
}

// ---------------------------------------------------------------------------
// Selection + detail card
// ---------------------------------------------------------------------------

function clearSelection() {
  if (state.selectedId === null) return;
  state.selectedId = null;
  render();
}

function renderDetail() {
  const marker = state.data.markers.find((entry) => entry.id === state.selectedId);
  if (!marker) { els.detail.hidden = true; return; }
  const coordinate = marker.precision === "exact"
    ? `Exact pin · ${escapeHtml(marker.area)}`
    : `Area-level pin · ${escapeHtml(marker.area)}`;
  const buildNames = marker.buildIds.map((id) => state.data.builds.find((build) => build.id === id)?.name || id).join(", ");
  const distance = distanceLabel(marker);
  const equipped = isItemEquipped(marker);
  const titleIcon = marker.type === "item" && iconUrl(marker)
    ? `<img class="detail-icon" src="${escapeHtml(iconUrl(marker))}" alt="" />` : "";
  const equipButton = marker.type === "item"
    ? `<button id="detailEquip" class="equip-button ${equipped ? "on" : ""}" data-equip="${escapeHtml(marker.itemKey)}">${equipped ? "Equipped ✓ (click to unequip)" : "Mark as equipped"}</button>`
    : "";
  const honorIntel = marker.type === "fight" ? `
    ${marker.legendaryAction ? `<p class="legendary">☠ <strong>Legendary action:</strong> ${escapeHtml(marker.legendaryAction)}</p>` : ""}
    ${(marker.failureConditions || []).map((text) => `<p class="fail-condition">✖ ${escapeHtml(text)}</p>`).join("")}
    ${(marker.preparation || []).length ? `<p><strong>Prepare:</strong> ${escapeHtml((marker.preparation || []).slice(0, 3).join(" · "))}</p>` : ""}
    ${(marker.irreversibleWarnings || []).map((text) => `<p class="fail-condition">⚠ ${escapeHtml(text)}</p>`).join("")}` : "";

  els.detail.hidden = false;
  els.detail.innerHTML = `<div class="detail-header">${titleIcon}<h3>${escapeHtml(marker.name)}</h3>${equipButton}</div>
    <p>${escapeHtml(marker.advice)}</p>
    ${marker.why ? `<p><strong>Why:</strong> ${escapeHtml(marker.why)}</p>` : ""}
    ${honorIntel}
    <div class="detail-grid">
      <div><span>Region</span>${escapeHtml(marker.region)} · ${escapeHtml(marker.area)}</div>
      <div><span>Readiness</span>${marker.type === "fight" ? `Minimum recommended level ${marker.minimumLevel}` : `${escapeHtml(marker.priority)} ${escapeHtml(marker.slot || "item")}`}</div>
      <div><span>Placement</span>${escapeHtml(coordinate)}</div>
    </div>
    ${distance ? `<p class="detail-distance">${escapeHtml(distance)}</p>` : ""}
    ${buildNames ? `<p><strong>Builds:</strong> ${escapeHtml(buildNames)}</p>` : ""}
    <a href="${escapeHtml(marker.source)}" target="_blank" rel="noreferrer">Open source ↗</a>`;

  const equipEl = document.querySelector("#detailEquip");
  if (equipEl) equipEl.addEventListener("click", () => toggleEquipped(equipEl.dataset.equip));
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
  renderMarkers(markers, { fit });
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
    els.hideDone.checked = false; els.labels.checked = false; state.showLabels = false;
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
  els.routeList.addEventListener("click", (event) => {
    const equip = event.target.closest("[data-equip]");
    if (equip) { toggleEquipped(equip.dataset.equip); return; }
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

  els.partyPanel.addEventListener("click", (event) => {
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

  els.equipmentPanel.addEventListener("click", (event) => {
    const assignment = event.target.closest("[data-member-equip]");
    if (assignment) {
      toggleMemberEquipment(assignment.dataset.memberId, assignment.dataset.memberEquip);
      return;
    }
    const card = event.target.closest(".equip-card");
    if (card) {
      const marker = state.data.markers.find((entry) => entry.id === card.dataset.id);
      if (marker) { setTab("route"); selectMarker(marker, true); }
    }
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
    initMap();
    bindEvents();
    const requestedMarker = applyURLIntent();
    render({ fit: true });
    if (requestedMarker) selectMarker(requestedMarker, true);
    pollPosition();
    setInterval(pollPosition, 2000);
  })
  .catch((error) => { els.summary.textContent = "Map failed to load"; els.routeList.innerHTML = `<p>${escapeHtml(error.message)}</p>`; });
