// Side panels: route list, party/loadout, equipment sheets, warnings, the
// marker detail card, and the marker-export dialog. Pure render/template
// functions over shared state — no render() calls, no listener binding
// (panel innerHTML is rebuilt constantly; app.js delegates events instead).

import {
  state, els, escapeHtml, markerClass, isItemEquipped, isResolved, iconUrl,
  effectSnippet, equippedSet, memberEquipment, equipmentOwner, plannedRosterMembers,
} from "./state.js";

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

export function renderRoute(markers) {
  els.routeTitle.textContent = els.region.value === "all" ? "All Act 1 locations" : els.region.value;
  const equippedCount = itemKeys().filter((key) => equippedSet().has(key)).length;
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
  const validParty = plannedRosterMembers().filter((member) => state.data.builds.some((build) => build.id === member.buildId));
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

export function renderParty() {
  if (!state.roster.length) {
    els.partyPanel.innerHTML = `<p class="panel-note">Open this map from the companion to configure the full roster.</p>`;
    return;
  }
  const active = state.roster.filter((member) => member.status === "active");
  const inactive = state.roster.filter((member) => member.status !== "active");
  const statusOptions = ["active", "camp", "unrecruited", "unavailable", "dead", "departed"];
  const memberRow = (member) => {
    const build = state.data.builds.find((entry) => entry.id === member.buildId);
    const level = Number(member.level) || Number(els.level.value);
    const step = currentBuildStep(build, level);
    const buildOptions = `<option value="">No reviewed build</option>${state.data.builds.map((entry) => `<option value="${escapeHtml(entry.id)}" ${entry.id === member.buildId ? "selected" : ""}>${escapeHtml(entry.name)}</option>`).join("")}`;
    const levelOptions = Array.from({ length: 12 }, (_, index) => index + 1).map((value) => `<option value="${value}" ${value === level ? "selected" : ""}>L${value}</option>`).join("");
    return `<article class="build-card party-member-card roster-${escapeHtml(member.status)}" data-build="${escapeHtml(member.buildId || "")}">
      <header>
        <div class="build-title"><p class="party-member-name">${escapeHtml(member.name)}</p><h3>${escapeHtml(build?.name || member.className || "Unassigned")}</h3></div>
        <select class="roster-status" data-roster-status="${escapeHtml(member.id)}" aria-label="${escapeHtml(member.name)} roster status">${statusOptions.map((status) => `<option value="${status}" ${status === member.status ? "selected" : ""}>${status}</option>`).join("")}</select>
      </header>
      <div class="roster-controls"><select data-roster-level="${escapeHtml(member.id)}" aria-label="${escapeHtml(member.name)} level">${levelOptions}</select><select data-roster-build="${escapeHtml(member.id)}" aria-label="${escapeHtml(member.name)} build">${buildOptions}</select></div>
      <p class="build-role">${escapeHtml(build?.role || "No role assigned")}${build ? ` · ${escapeHtml(build.finalSplit)}` : ""}</p>
      ${step ? `<div class="level-now">
        <div class="level-now__badge">L${step.level}</div>
        <div class="level-now__body">
          <strong>${escapeHtml(step.take)}</strong>${step.subclassChoice && step.subclassChoice !== "-" ? ` · ${escapeHtml(step.subclassChoice)}` : ""}
          ${step.choices ? `<p class="level-now__pick"><span>Take</span> ${escapeHtml(step.choices)}</p>` : ""}
          ${step.tactics ? `<p class="level-now__do"><span>Do now</span> ${escapeHtml(step.tactics)}</p>` : ""}
        </div>
      </div>` : `<p class="panel-note">Assign a reviewed build to see this level's action.</p>`}
    </article>`;
  };
  const karlach = state.roster.find((member) => member.name === "Karlach");
  const outcomeRows = karlach?.status === "dead" ? `<div class="story-outcomes"><strong>Karlach outcome</strong>
    <label><input type="checkbox" data-story-outcome="karlach_killed_for_robe" ${state.storyOutcomes.includes("karlach_killed_for_robe") ? "checked" : ""}> Killed for Mizora/Wyll path</label>
    <label><input type="checkbox" data-story-outcome="infernal_robe_obtained" ${state.storyOutcomes.includes("infernal_robe_obtained") ? "checked" : ""}> Infernal Robe obtained</label>
  </div>` : "";
  els.partyPanel.innerHTML = `<div class="roster-heading"><strong>Active party</strong><span>${active.length}/4</span></div>
    <div class="build-list">${active.map(memberRow).join("")}</div>
    <details class="roster-inactive"><summary>Camp & unavailable <strong>${inactive.length}</strong></summary><div class="build-list">${inactive.map(memberRow).join("")}</div></details>
    ${outcomeRows}
    <label class="include-camp"><input type="checkbox" data-include-camp ${state.includeCampPlans ? "checked" : ""}> Include camp builds in Equipment</label>`;
}

function gearForMember(member) {
  const build = state.data.builds.find((entry) => entry.id === member.buildId);
  const level = Number(member.level) || Number(els.level.value);
  return (build?.gear || [])
    .filter((gear) => gear.act <= state.data.act
      && gear.minimumLevel <= level
      && (gear.maximumLevel == null || level <= gear.maximumLevel))
    .map((gear) => gearDisplay(gear, member.buildId));
}

function laterGearForMember(member) {
  const build = state.data.builds.find((entry) => entry.id === member.buildId);
  const level = Number(member.level) || Number(els.level.value);
  return (build?.gear || [])
    .filter((gear) => gear.act === state.data.act && gear.minimumLevel > level)
    .map((gear) => gearDisplay(gear, member.buildId));
}

function itemKey(name) {
  return name.toLowerCase().replace(/\s*x\d+$/, "").replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

function gearDisplay(gear, buildId) {
  const key = itemKey(gear.item);
  const marker = itemMarkers().find((entry) => entry.itemKey === key && entry.buildIds.includes(buildId));
  return {
    ...(marker || {}),
    id: marker?.id || "",
    name: gear.item,
    itemKey: key,
    type: "item",
    slot: gear.slot,
    priority: gear.priority,
    region: gear.region,
    area: marker?.area || gear.region,
    acquireDetail: gear.acquire || gear.acquisition,
    effect: gear.effect,
    why: gear.why,
    alternative: gear.alternative,
    requirement: gear.requirement,
    minimumLevel: gear.minimumLevel,
    mapObjective: gear.mapObjective,
    icon: gear.icon,
  };
}

export function renderEquipment() {
  const members = partyMembers();
  const totals = members.map((member) => {
    const gear = gearForMember(member);
    const assigned = memberEquipment(member.id);
    const trackable = gear.filter((item) => item.mapObjective);
    return {
      member,
      gear,
      later: laterGearForMember(member),
      assignedCount: trackable.filter((item) => assigned.has(item.itemKey)).length,
      trackableCount: trackable.length,
    };
  });
  const assignedCount = totals.reduce((sum, item) => sum + item.assignedCount, 0);
  const gearCount = totals.reduce((sum, item) => sum + item.trackableCount, 0);
  els.equipmentBadge.hidden = gearCount === 0;
  els.equipmentBadge.textContent = `${assignedCount}/${gearCount}`;
  els.missingOnlyBtn.classList.toggle("active", state.missingOnly);
  els.missingOnlyBtn.textContent = state.missingOnly ? "Showing missing only ✕" : "Show missing on map";
  if (!members.length) {
    els.equipmentPanel.innerHTML = `<p class="panel-note">Choose party builds first. Equipment will then be separated by character for Act 1.</p>`;
    return;
  }
  els.equipmentPanel.innerHTML = `<label class="include-camp"><input type="checkbox" data-include-camp ${state.includeCampPlans ? "checked" : ""}> Include camp builds</label>${totals.map(({ member, gear, later, assignedCount: count, trackableCount }) => `
    <section class="member-equipment">
      <header class="member-equipment__header"><div><p class="party-member-name">${escapeHtml(member.name)}</p><h3>${escapeHtml(state.data.builds.find((build) => build.id === member.buildId)?.name || member.buildId)}</h3></div><strong>${count}/${trackableCount}</strong></header>
      ${equipmentSheet(member, gear)}
      ${later.length ? `<details class="equipment-later"><summary>Later this act <strong>${later.length}</strong></summary>${later.map((item) => `<p><span>🔒 L${item.minimumLevel}</span> ${escapeHtml(item.name)}${item.requirement ? ` · ${escapeHtml(item.requirement)}` : ""}</p>`).join("")}</details>` : ""}
    </section>`).join("")}`;
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
    const trackable = items.filter((item) => item.mapObjective);
    const slotEquipped = trackable.filter((m) => assigned.has(m.itemKey)).length;
    return `<section class="equip-slot">
      <div class="equip-slot__label"><span>${escapeHtml(slot)}</span><em>${trackable.length ? `${slotEquipped}/${trackable.length}` : "set"}</em></div>
      <div class="equip-slot__items">
        ${items.map((marker) => {
          const equipped = assigned.has(marker.itemKey);
          const owner = equipmentOwner(marker.itemKey);
          const elsewhere = owner && owner.id !== member.id;
          return `<article class="equip-card ${equipped ? "equipped" : ""} ${elsewhere ? "contested" : ""}" ${marker.id ? `data-id="${escapeHtml(marker.id)}"` : ""}>
            ${iconUrl(marker) ? `<img class="item-thumb ${equipped ? "item-thumb--equipped" : ""}" src="${escapeHtml(iconUrl(marker))}" alt="" loading="lazy" />` : `<span class="item-thumb item-thumb--empty"></span>`}
            <div class="equip-card__body">
              <h3>${escapeHtml(marker.name)}</h3>
              <p>${escapeHtml(marker.effect ? effectSnippet(marker.effect) : marker.area)}</p>
              <div class="equip-card__meta">${priorityChip(marker.priority)}<span class="equip-card__where">📍 ${escapeHtml(marker.acquireDetail || marker.region)}</span></div>
              ${marker.requirement ? `<p class="equip-card__requirement">${escapeHtml(marker.requirement)}</p>` : ""}
              ${elsewhere ? `<p class="equip-card__conflict">Owned by ${escapeHtml(owner.name)} · ${escapeHtml(marker.alternative || "No equivalent reviewed; transfer deliberately")}</p>` : ""}
            </div>
            ${marker.mapObjective ? `<button class="equip-toggle ${equipped ? "on" : ""}" data-member-equip="${escapeHtml(marker.itemKey)}" data-member-id="${escapeHtml(member.id)}" title="${equipped ? `Assigned to ${escapeHtml(member.name)} — click to remove` : elsewhere ? `Transfer from ${escapeHtml(owner.name)} to ${escapeHtml(member.name)}` : `Assign to ${escapeHtml(member.name)}`}">${equipped ? "✓" : elsewhere ? "↔" : "+"}</button>` : `<span class="equip-intent">SET</span>`}
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

export function updateWarningsBadge() {
  const pending = (state.data.timedEvents || []).filter(
    (event) => !state.ackTimed.has(event.id) && (event.severity === "critical" || event.severity === "high"),
  ).length;
  els.warningsBadge.hidden = pending === 0;
  els.warningsBadge.textContent = String(pending);
}

export function renderWarnings() {
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
// Detail card
// ---------------------------------------------------------------------------

// Approximate BG3 world metres per MapGenie degree, from the surface affine fit.
const METERS_PER_LNG_DEGREE = 2551;
const METERS_PER_LAT_DEGREE = 2277;

function distanceLabel(marker) {
  if (!state.player) return "";
  const dLngMeters = (marker.lng - state.player.lng) * METERS_PER_LNG_DEGREE;
  const dLatMeters = (marker.lat - state.player.lat) * METERS_PER_LAT_DEGREE;
  const meters = Math.round(Math.hypot(dLngMeters, dLatMeters));
  return `~${meters} m from your position`;
}

export function renderDetail() {
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

  // Items lead with what they do, then exactly how to get them; the reviewed
  // route note (advice) and build rationale (why) follow.
  const itemIntel = marker.type === "item" ? `
    ${marker.effect ? `<p class="item-effect">${escapeHtml(marker.effect)}</p>` : ""}
    <p><strong>How to get:</strong> ${escapeHtml(marker.acquireDetail || marker.advice)}</p>
    ${marker.acquireDetail && marker.advice && marker.acquireDetail !== marker.advice ? `<p class="item-route-note">${escapeHtml(marker.advice)}</p>` : ""}
    ${marker.why ? `<p><strong>Why for this build:</strong> ${escapeHtml(marker.why)}</p>` : ""}` : "";

  els.detail.hidden = false;
  els.detail.innerHTML = `<div class="detail-header">${titleIcon}<h3>${escapeHtml(marker.name)}</h3>${equipButton}</div>
    ${marker.type === "item" ? itemIntel : `<p>${escapeHtml(marker.advice)}</p>`}
    ${honorIntel}
    <div class="detail-grid">
      <div><span>Region</span>${escapeHtml(marker.region)} · ${escapeHtml(marker.area)}</div>
      <div><span>Readiness</span>${marker.type === "fight" ? `Minimum recommended level ${marker.minimumLevel}` : `${escapeHtml(marker.priority)} ${escapeHtml(marker.slot || "item")}`}</div>
      <div><span>Placement</span>${escapeHtml(coordinate)}</div>
    </div>
    ${distance ? `<p class="detail-distance">${escapeHtml(distance)}</p>` : ""}
    ${buildNames ? `<p><strong>Builds:</strong> ${escapeHtml(buildNames)}</p>` : ""}
    <a href="${escapeHtml(marker.wiki || marker.source)}" target="_blank" rel="noreferrer">${marker.wiki ? "Open bg3.wiki ↗" : "Open source ↗"}</a>`;
}

// ---------------------------------------------------------------------------
// Deterministic one-shot BG3 marker export
// ---------------------------------------------------------------------------

export async function previewMarkerExport() {
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
      equippedItemKeys: [...equippedSet()],
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

export function downloadMarkerExport() {
  if (!state.markerExport?.markers.length) return;
  const artifact = { formatVersion: 1, generatedAt: new Date().toISOString(), ...state.markerExport };
  const url = URL.createObjectURL(new Blob([JSON.stringify(artifact, null, 2)], { type: "application/json" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `bg3-markers-act${artifact.act}-l${artifact.partyLevel}-${artifact.fingerprint}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

export async function confirmMarkerExport() {
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
