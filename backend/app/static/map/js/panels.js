// Side panels: route list, party/loadout, equipment sheets, warnings, and the
// marker detail card. Pure render/template
// functions over shared state — no render() calls, no listener binding
// (panel innerHTML is rebuilt constantly; app.js delegates events instead).

import {
  state, els, escapeHtml, markerClass, isItemEquipped, isResolved, iconUrl,
  effectSnippet, equippedSet, memberEquipment, equipmentOwner, plannedRosterMembers,
  currentBuildStep, WITHERS_HIRELINGS, hirelingProfile,
  sourceRecorded, sourceEquipped, sourceOwner, canActivateRosterStatus,
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

// The party panel is rebuilt wholesale, so the focused control (identified by
// its data-* attributes) is captured before the innerHTML swap and re-focused
// after — every mutation can then funnel through the full render() safely.
function partyFocusSelector() {
  const active = document.activeElement;
  if (!active || !els.partyPanel.contains(active)) return null;
  const attributes = active.getAttributeNames?.().filter((name) => name.startsWith("data-")) || [];
  if (!attributes.length) return null;
  return attributes.map((name) => `[${name}="${CSS.escape(active.getAttribute(name))}"]`).join("");
}

function partyViewHtml() {
  if (!state.roster.length) {
    return `<p class="panel-note">Open this map from the companion to configure the full roster.</p>`;
  }
  if (state.partyView === "setup") return partySetupView();
  if (state.partyView === "member") {
    const member = state.roster.find((entry) => entry.id === state.selectedPartyMemberId);
    if (member) return partyMemberView(member);
    state.partyView = "guidance";
    state.selectedPartyMemberId = null;
  }
  return partyGuidanceView();
}

export function renderParty() {
  const focusSelector = partyFocusSelector();
  els.partyPanel.innerHTML = partyViewHtml();
  if (focusSelector) els.partyPanel.querySelector(focusSelector)?.focus();
}

const ABILITIES = [
  ["strength", "STR"], ["dexterity", "DEX"], ["constitution", "CON"],
  ["intelligence", "INT"], ["wisdom", "WIS"], ["charisma", "CHA"],
];

function statusLabel(status) {
  return ({ active: "Active", camp: "Camp", unrecruited: "Not recruited", unavailable: "Unavailable", dead: "Dead", departed: "Departed" })[status] || status;
}

function activeAbilitySetup(build, level) {
  return [...(build?.abilitySetups || [])].filter((setup) => setup.level <= level).sort((a, b) => b.level - a.level)[0];
}

function plannedAbilityScore(member, build, ability) {
  const level = Number(member.level) || 1;
  const setup = activeAbilitySetup(build, level);
  let score = Number(setup?.finalScores?.[ability] ?? member.abilityScores?.[ability] ?? build?.startingAbilityScores?.[ability] ?? 10);
  (build?.abilitySources || []).filter((source) => source.ability === ability && source.minimumLevel <= level && (!source.maximumLevel || source.maximumLevel >= level)).forEach((source) => {
    if (!["asi", "feat"].includes(source.kind) && !sourceRecorded(member, source) && !sourceEquipped(member, source)) return;
    score = source.mode === "minimum" ? Math.max(score, source.value) : score + source.value;
  });
  return score;
}

function partyGuidanceView() {
  const active = state.roster.filter((member) => member.status === "active").slice(0, 4);
  const rows = active.map((member) => {
    const build = state.data.builds.find((entry) => entry.id === member.buildId);
    const step = currentBuildStep(build, Number(member.level) || 1);
    const exact = step?.level === Number(member.level);
    const setup = activeAbilitySetup(build, Number(member.level) || 1);
    const setupApplied = setup && member.appliedAbilitySetupId === setup.id;
    const next = build?.levels?.find((entry) => entry.level > Number(member.level));
    return `<button class="party-guidance-card ${exact ? "is-now" : ""} ${build ? "" : "needs-build"}" type="button" data-action="open-member" data-id="${escapeHtml(member.id)}">
      <span class="party-guidance-card__head"><strong>${escapeHtml(member.name)}</strong><span>L${member.level} · ${escapeHtml(build?.name || member.className || "No build")}</span><b>›</b></span>
      ${step ? `<span class="party-guidance-card__step"><em>${exact ? `NOW L${step.level}` : `LATEST L${step.level}`}</em><strong>${escapeHtml(step.take)}</strong></span>
        ${step.choices && step.choices !== "-" ? `<span class="party-guidance-card__fact"><b>TAKE</b>${escapeHtml(step.choices)}</span>` : ""}
        ${step.tactics && step.tactics !== "-" ? `<span class="party-guidance-card__fact do"><b>DO</b>${escapeHtml(step.tactics)}</span>` : ""}`
        : `<span class="party-guidance-card__missing">Choose a reviewed build</span>`}
      <span class="party-guidance-card__foot"><span>${next ? `Next L${next.level}: ${escapeHtml(next.take)}` : build ? "Final reviewed step reached" : "Build required"}</span>${setup ? `<strong class="${setupApplied ? "party-status-ok" : "party-status-warn"}">${setupApplied ? "Stats recorded" : "Stats setup due"}</strong>` : ""}</span>
    </button>`;
  }).join("");
  return `<div class="party-page-title" tabindex="-1"><div><strong>Party guidance</strong><span>What your active party needs at this level</span></div><b>${active.length}/4 active</b></div>
    <div class="party-guidance-list">${rows || `<p class="panel-note">No active party members. A solo run is valid; add someone only when you want Party guidance.</p>`}</div>
    <button class="party-primary-action" type="button" data-action="show-setup">Manage roster, builds, and abilities <b>›</b></button>`;
}

function setupMemberRow(member, active, available) {
  const build = state.data.builds.find((entry) => entry.id === member.buildId);
  const swap = active && available.length ? `<select data-action="swap-member" data-id="${escapeHtml(member.id)}" aria-label="Replace ${escapeHtml(member.name)}"><option value="">Swap...</option>${available.map((candidate) => `<option value="${escapeHtml(candidate.id)}">${escapeHtml(candidate.name)}</option>`).join("")}</select>` : "";
  const camp = active ? `<button type="button" data-action="return-camp" data-id="${escapeHtml(member.id)}">Camp</button>` : "";
  const add = !active && canActivateRosterStatus(member.status) ? `<button type="button" data-action="activate-member" data-id="${escapeHtml(member.id)}">Add</button>` : "";
  const record = member.status === "unrecruited" ? `<button type="button" data-action="record-recruited" data-id="${escapeHtml(member.id)}">Record recruited</button>` : "";
  return `<div class="party-setup-row"><button type="button" data-action="open-member" data-id="${escapeHtml(member.id)}"><strong>${escapeHtml(member.name)}</strong><span>L${member.level} · ${escapeHtml(build?.name || member.className || "No build")}</span></button>${swap}${camp}${add}${record}</div>`;
}

function partySetupView() {
  const active = state.roster.filter((member) => member.status === "active").slice(0, 4);
  const camp = state.roster.filter((member) => member.status === "camp");
  const recruitable = state.roster.filter((member) => member.status === "unrecruited");
  const available = [...camp, ...recruitable];
  const outside = state.roster.filter((member) => ["unavailable", "dead", "departed"].includes(member.status));
  const selectedHirelings = state.roster.filter((member) => member.isHireling);
  const selectedNames = new Set(selectedHirelings.map((member) => member.name));
  const hirelings = WITHERS_HIRELINGS.filter((hireling) => !selectedNames.has(hireling.name));
  const karlach = state.roster.find((member) => member.name === "Karlach");
  const outcomeRows = karlach?.status === "dead" ? `<div class="story-outcomes"><strong>Karlach outcome</strong>
    <label><input type="checkbox" data-action="toggle-story-outcome" data-id="karlach_killed_for_robe" ${state.storyOutcomes.includes("karlach_killed_for_robe") ? "checked" : ""}> Killed for Mizora/Wyll path</label>
    <label><input type="checkbox" data-action="toggle-story-outcome" data-id="infernal_robe_obtained" ${state.storyOutcomes.includes("infernal_robe_obtained") ? "checked" : ""}> Infernal Robe obtained</label></div>` : "";
  return `<button class="party-back" type="button" data-action="show-guidance">‹ Party</button>
    <div class="party-page-title" tabindex="-1"><div><strong>Party setup</strong><span>Four is the maximum, not a requirement</span></div><b>${active.length}/4 active</b></div>
    <section class="party-setup-section"><h3>Active slots</h3>${active.map((member) => setupMemberRow(member, true, available)).join("") || `<p class="panel-note">No active characters.</p>`}</section>
    <details class="party-setup-section" open><summary>Camp <b>${camp.length}</b></summary>${camp.map((member) => setupMemberRow(member, false, available)).join("") || `<p class="panel-note">No characters at Camp.</p>`}</details>
    <details class="party-setup-section"><summary>Not recorded as recruited <b>${recruitable.length}</b></summary>${recruitable.map((member) => setupMemberRow(member, false, available)).join("")}</details>
    <details class="party-setup-section"><summary>Withers hirelings <b>${selectedHirelings.length}/3</b></summary>${hirelings.map((hireling) => `<div class="party-setup-row"><span><strong>${escapeHtml(hireling.name)}</strong><small>${escapeHtml(hireling.race)} · ${escapeHtml(hireling.className)}</small></span><button type="button" data-action="add-hireling" data-id="${escapeHtml(hireling.id)}" ${selectedHirelings.length >= 3 ? "disabled" : ""}>Record recruited</button></div>`).join("")}</details>
    ${outside.length ? `<details class="party-setup-section"><summary>Dead, departed, or unavailable <b>${outside.length}</b></summary>${outside.map((member) => `<div class="party-setup-row"><button type="button" data-action="open-member" data-id="${escapeHtml(member.id)}"><strong>${escapeHtml(member.name)}</strong><span>${escapeHtml(statusLabel(member.status))}</span></button><button type="button" data-action="return-camp" data-id="${escapeHtml(member.id)}">Return to Camp</button></div>`).join("")}</details>` : ""}
    ${outcomeRows}
    <label class="include-camp"><input type="checkbox" data-action="toggle-include-camp" ${state.includeCampPlans ? "checked" : ""}> Include Camp builds in Equipment</label>`;
}

function abilityRecipe(setup) {
  const bonus = (ability) => ability === setup.bonusTwo ? "+2" : ability === setup.bonusOne ? "+1" : "-";
  return `<table class="ability-recipe"><thead><tr><th></th>${ABILITIES.map(([, short]) => `<th>${short}</th>`).join("")}</tr></thead><tbody>
    <tr><th>1 Point buy</th>${ABILITIES.map(([ability]) => `<td>${setup.pointBuyScores[ability]}</td>`).join("")}</tr>
    <tr><th>2 Bonus</th>${ABILITIES.map(([ability]) => `<td>${bonus(ability)}</td>`).join("")}</tr>
    <tr class="ability-recipe__final"><th>3 Enter</th>${ABILITIES.map(([ability]) => `<td>${setup.finalScores[ability]}</td>`).join("")}</tr>
  </tbody></table>`;
}

function abilitySourceRow(source, member) {
  const recorded = sourceRecorded(member, source);
  const equipped = sourceEquipped(member, source);
  const owner = source.uniqueAcrossParty ? sourceOwner(source) : null;
  const effect = source.mode === "minimum" ? `→ ${source.value}` : `+${source.value}`;
  let action = `<span class="source-state">L${source.minimumLevel}</span>`;
  if (source.kind === "equipment") action = equipped ? `<span class="source-state ok">Equipped</span>` : owner ? `<span class="source-state warn">Used by ${escapeHtml(owner.name)}</span>` : `<button type="button" data-action="open-loadout">Loadout</button>`;
  if (["permanent", "consumable"].includes(source.kind)) action = `<button type="button" data-action="toggle-ability-source" data-id="${escapeHtml(source.id)}" data-source-applied="${recorded}">${recorded ? "Recorded" : owner ? "Move" : "Record"}</button>`;
  return `<div class="ability-source"><b>${escapeHtml(source.ability.slice(0, 3).toUpperCase())}</b><span><strong>${escapeHtml(source.label)} <em>${escapeHtml(effect)}</em></strong><small>${escapeHtml(source.kind)} · ${escapeHtml(source.minimumLevel > 1 ? `from L${source.minimumLevel}` : source.note || "build plan")}</small>${source.minimumLevel > 1 && source.note ? `<small>${escapeHtml(source.note)}</small>` : ""}</span>${action}</div>`;
}

function partyMemberView(member) {
  const build = state.data.builds.find((entry) => entry.id === member.buildId);
  const level = Number(member.level) || 1;
  const step = currentBuildStep(build, level);
  const exact = step?.level === level;
  const setup = activeAbilitySetup(build, level);
  const setupApplied = setup && member.appliedAbilitySetupId === setup.id;
  const statuses = ["active", "camp", "unrecruited", "unavailable", "dead", "departed"];
  const levelOptions = Array.from({ length: 12 }, (_, index) => index + 1).map((value) => `<option value="${value}" ${value === level ? "selected" : ""}>Level ${value}</option>`).join("");
  const buildOptions = `<option value="">No reviewed build</option>${state.data.builds.map((entry) => `<option value="${escapeHtml(entry.id)}" ${entry.id === member.buildId ? "selected" : ""}>${escapeHtml(entry.name)}</option>`).join("")}`;
  const scores = build ? `<div class="ability-score-grid">${ABILITIES.map(([ability, short]) => { const score = plannedAbilityScore(member, build, ability); const target = build.targetAbilityScores?.[ability] ?? score; const modifier = Math.floor((score - 10) / 2); return `<div><b>${short}</b><strong>${score}</strong><span>${modifier >= 0 ? "+" : ""}${modifier} / ${target}</span></div>`; }).join("")}</div>` : "";
  const hireling = hirelingProfile(member);
  return `<button class="party-back" type="button" data-action="${state.partyMemberReturnView === "setup" ? "show-setup" : "show-guidance"}">‹ ${state.partyMemberReturnView === "setup" ? "Party setup" : "Party guidance"}</button>
    <div class="party-page-title" tabindex="-1"><div>${member.isCustom ? `<label class="party-name-field">Character name<input data-action="rename-member" data-id="${escapeHtml(member.id)}" value="${escapeHtml(member.name)}"></label>` : `<strong>${escapeHtml(member.name)}</strong>${hireling ? `<span>${escapeHtml(hireling.race)} · Withers hireling</span>` : ""}`}</div><b>${escapeHtml(statusLabel(member.status))}</b></div>
    <div class="roster-controls"><select data-action="set-level" data-id="${escapeHtml(member.id)}" aria-label="${escapeHtml(member.name)} level">${levelOptions}</select><select class="roster-status" data-action="set-status" data-id="${escapeHtml(member.id)}" aria-label="${escapeHtml(member.name)} roster status">${statuses.map((status) => `<option value="${status}" ${status === member.status ? "selected" : ""}>${escapeHtml(statusLabel(status))}</option>`).join("")}</select></div>
    ${step ? `<div class="level-now"><div class="level-now__badge">${exact ? "NOW" : "LATEST"}<small>L${step.level}</small></div><div class="level-now__body"><strong>${escapeHtml(step.take)}</strong>${step.subclassChoice && step.subclassChoice !== "-" ? ` · ${escapeHtml(step.subclassChoice)}` : ""}${step.choices && step.choices !== "-" ? `<p class="level-now__pick"><span>Take</span>${escapeHtml(step.choices)}</p>` : ""}${step.tactics && step.tactics !== "-" ? `<p class="level-now__do"><span>Do now</span>${escapeHtml(step.tactics)}</p>` : ""}</div></div>` : `<p class="panel-note">Assign a reviewed build to see current guidance.</p>`}
    <section class="party-member-section"><h3>Ability Points ${setup ? `<span class="${setupApplied ? "party-status-ok" : "party-status-warn"}">${setupApplied ? "Recorded" : "Setup due"}</span>` : ""}</h3>${setup ? abilityRecipe(setup) : `<p class="panel-note">No validated point-buy recipe is available for this build.</p>`}${setup ? `<p><strong>First class:</strong> ${escapeHtml(setup.firstClass)}<br><span>${escapeHtml(setup.classOrder)}</span></p><p>${escapeHtml(setup.reason)}</p>${setupApplied ? "" : `<button class="party-primary-action" type="button" data-action="apply-setup" data-id="${escapeHtml(setup.id)}">Mark these values applied in BG3</button>`}` : ""}${scores}</section>
    <section class="party-member-section"><h3>Where every boost comes from</h3>${(build?.abilitySources || []).map((source) => abilitySourceRow(source, member)).join("") || `<p class="panel-note">No additional ability sources are required.</p>`}${build?.targetAbilityNote ? `<p class="panel-note">${escapeHtml(build.targetAbilityNote)}</p>` : ""}</section>
    <section class="party-member-section"><h3>Build</h3><select data-action="set-build" data-id="${escapeHtml(member.id)}" aria-label="Reviewed build for ${escapeHtml(member.name)}">${buildOptions}</select>${build ? `<p><strong>${escapeHtml(build.role)}</strong><br>${escapeHtml(build.finalSplit)} · ${escapeHtml(build.honorStatus)}</p><p class="build-caveat">${escapeHtml(build.caveat)}</p>` : ""}<div class="build-import"><input type="url" data-build-import-url aria-label="Public build URL" placeholder="Public build URL"><button type="button" data-action="import-build" data-id="${escapeHtml(member.id)}">Import and assign</button></div></section>
    <section class="party-member-section danger-zone"><h3>Dangerous actions</h3><button type="button" data-action="reset-member" data-id="${escapeHtml(member.id)}">Reset character plan...</button>${member.isHireling ? `<button type="button" data-action="dismiss-hireling" data-id="${escapeHtml(member.id)}" ${member.status === "active" ? "disabled" : ""}>Dismiss hireling...</button>` : ""}</section>`;
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
