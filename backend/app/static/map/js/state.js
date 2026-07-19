// Shared state, DOM lookups, persistence, and run-state sync. Every other
// module imports from here; this module imports nothing.

export const state = {
  data: null,
  selectedId: null,
  done: new Set(JSON.parse(localStorage.getItem("bg3-act1-done") || "[]")),
  equippedByMember: JSON.parse(localStorage.getItem("bg3-act1-equipped-by-member") || "{}"),
  activeBuilds: JSON.parse(localStorage.getItem("bg3-act1-builds") || "[]"),
  party: JSON.parse(localStorage.getItem("bg3-act1-party") || "[]"),
  roster: JSON.parse(localStorage.getItem("bg3-act1-roster") || "[]"),
  storyOutcomes: JSON.parse(localStorage.getItem("bg3-act1-story-outcomes") || "[]"),
  includeCampPlans: localStorage.getItem("bg3-act1-include-camp") === "true",
  walkthroughStatuses: JSON.parse(localStorage.getItem("bg3-act1-walkthrough") || "{}"),
  walkthroughOutcomes: JSON.parse(localStorage.getItem("bg3-act1-walk-outcomes") || "{}"),
  focusedWalkthroughStepId: localStorage.getItem("bg3-act1-walk-focus") || null,
  selectedWalkthroughStepId: null,
  partyView: "guidance",
  selectedPartyMemberId: null,
  partyMemberReturnView: "guidance",
  ackTimed: new Set(JSON.parse(localStorage.getItem("bg3-act1-timed-ack") || "[]")),
  missingOnly: false,
  tab: "walkthrough",
  showLabels: false,
  lastRegion: null,
  map: null,
  markerLayer: null,
  leafletMarkers: new Map(),
  player: null,
  playerMarker: null,
  follow: false,
  loadoutSyncTimer: null,
};

const DEFAULT_ROSTER = [
  { id: "tav", name: "Tav", className: null, isCustom: true, status: "active" },
  { id: "shadowheart", name: "Shadowheart", className: "Cleric", isCustom: false, status: "active" },
  { id: "laezel", name: "Lae'zel", className: "Fighter", isCustom: false, status: "active" },
  { id: "astarion", name: "Astarion", className: "Rogue", isCustom: false, status: "active" },
  { id: "gale", name: "Gale", className: "Wizard", isCustom: false, status: "camp" },
  { id: "wyll", name: "Wyll", className: "Warlock", isCustom: false, status: "camp" },
  { id: "karlach", name: "Karlach", className: "Barbarian", isCustom: false, status: "camp" },
  { id: "dark-urge", name: "Dark Urge", className: "Sorcerer", isCustom: false, status: "camp" },
  { id: "halsin", name: "Halsin", className: "Druid", isCustom: false, status: "unrecruited" },
  { id: "minthara", name: "Minthara", className: "Paladin", isCustom: false, status: "unrecruited" },
  { id: "jaheira", name: "Jaheira", className: "Druid", isCustom: false, status: "unrecruited" },
  { id: "minsc", name: "Minsc", className: "Ranger", isCustom: false, status: "unrecruited" },
];

export const WITHERS_HIRELINGS = [
  { id: "hireling-eldra-luthrinn", name: "Eldra Luthrinn", race: "Gold Dwarf", className: "Barbarian" },
  { id: "hireling-brinna-brightsong", name: "Brinna Brightsong", race: "Lightfoot Halfling", className: "Bard" },
  { id: "hireling-zenith-feur-sel", name: "Zenith Feur'sel", race: "High Elf", className: "Cleric" },
  { id: "hireling-danton", name: "Danton", race: "Mephistopheles Tiefling", className: "Druid" },
  { id: "hireling-varanna-sunblossom", name: "Varanna Sunblossom", race: "Wood Half-Elf", className: "Fighter" },
  { id: "hireling-sina-zith", name: "Sina'zith", race: "Githyanki", className: "Monk" },
  { id: "hireling-kerz", name: "Kerz", race: "Half-Orc", className: "Paladin" },
  { id: "hireling-ver-yll-wenkiir", name: "Ver'yll Wenkiir", race: "Seldarine Drow", className: "Ranger" },
  { id: "hireling-maddala-deadeye", name: "Maddala Deadeye", race: "Human", className: "Rogue" },
  { id: "hireling-jacelyn", name: "Jacelyn", race: "High Half-Elf", className: "Sorcerer" },
  { id: "hireling-kree-derryck", name: "Kree Derryck", race: "Duergar", className: "Warlock" },
  { id: "hireling-sir-fuzzalump", name: "Sir Fuzzalump", race: "Rock Gnome", className: "Wizard" },
];

// Saved rosters created before hirelings carried ids identify them only by
// name, so id match comes first with a name fallback for legacy members.
export function hirelingProfile(member) {
  return WITHERS_HIRELINGS.find((entry) => entry.id === member.hirelingId)
    || WITHERS_HIRELINGS.find((entry) => entry.name === member.name)
    || null;
}

// The reviewed build step that applies at a level: the exact row when one
// exists, otherwise the latest earlier row, otherwise the plan's first row.
export function currentBuildStep(build, level) {
  const plan = build?.levels || [];
  return plan.find((row) => row.level === level)
    || [...plan].reverse().find((row) => row.level <= level)
    || plan[0];
}

function buildFor(buildId) {
  return buildId ? state.data?.builds?.find((entry) => entry.id === buildId) : null;
}

export function normalizeRoster(roster = state.roster, legacyParty = state.party) {
  const source = roster.length ? roster : legacyParty.length ? legacyParty.map((member, index) => ({
    ...member, status: "active", isCustom: member.isCustom ?? index === 0,
  })) : DEFAULT_ROSTER.map((member) => ({ ...member, level: 1, buildId: null, preparedTags: [] }));
  const members = source.map((member, index) => {
    const normalized = {
      ...member,
      level: Math.min(12, Math.max(1, Number(member.level) || 1)),
      status: member.status || "active",
      isCustom: member.isCustom ?? index === 0,
    };
    // className is derived state: whenever a build resolves it follows the
    // reviewed step at the member's level.
    const step = currentBuildStep(buildFor(normalized.buildId), normalized.level);
    if (step) normalized.className = step.take;
    return normalized;
  });
  const names = new Set(members.map((member) => member.name.toLowerCase()));
  const level = Math.max(1, ...members.map((member) => member.level));
  DEFAULT_ROSTER.forEach((candidate) => {
    if (!names.has(candidate.name.toLowerCase())) members.push({ ...candidate, level, buildId: null, preparedTags: [] });
  });
  let activeCount = 0;
  members.forEach((member) => {
    if (member.status !== "active") return;
    activeCount += 1;
    if (activeCount > 4) member.status = "camp";
  });
  return members;
}

export function syncPartyProjection() {
  state.roster = normalizeRoster();
  state.party = state.roster.filter((member) => member.status === "active").slice(0, 4);
  state.activeBuilds = [...new Set(state.party.map((member) => member.buildId).filter(Boolean))];
}

export function plannedRosterMembers() {
  const statuses = state.includeCampPlans ? new Set(["active", "camp"]) : new Set(["active"]);
  return state.roster.filter((member) => statuses.has(member.status));
}

export function canActivateRosterStatus(status) {
  return ["active", "camp", "unrecruited"].includes(status);
}

export function updateRosterMember(memberId, changes) {
  const index = state.roster.findIndex((member) => member.id === memberId);
  if (index < 0) return false;
  const currentStatus = state.roster[index].status;
  const nextStatus = changes.status || state.roster[index].status;
  if (nextStatus === "active" && !canActivateRosterStatus(currentStatus)) return false;
  if (nextStatus === "active" && state.roster[index].status !== "active" && state.party.length >= 4) return false;
  const merged = { ...state.roster[index], ...changes };
  // className is derived: recompute it from the build step whenever a build
  // resolves so level and build changes never leave it stale.
  const step = currentBuildStep(buildFor(merged.buildId), Number(merged.level) || 1);
  if (step) merged.className = step.take;
  state.roster[index] = merged;
  syncPartyProjection();
  syncRunState();
  return true;
}

// ---------------------------------------------------------------------------
// Party mutators. Each one owns its domain mutation plus the
// syncPartyProjection/syncRunState pair; app.js only prompts and renders.
// ---------------------------------------------------------------------------

export function activateMember(memberId) {
  return updateRosterMember(memberId, { status: "active" });
}

export function recordRecruited(memberId) {
  return updateRosterMember(memberId, { status: "camp" });
}

export function returnToCamp(memberId) {
  return updateRosterMember(memberId, { status: "camp" });
}

export function addHireling(hirelingId) {
  const selected = state.roster.filter((member) => member.isHireling);
  const hireling = WITHERS_HIRELINGS.find((entry) => entry.id === hirelingId);
  if (!hireling || selected.length >= 3) return false;
  const level = Math.max(3, ...state.party.map((member) => Number(member.level) || 1));
  state.roster.push({
    id: hireling.id, hirelingId: hireling.id, name: hireling.name, level, buildId: null,
    preparedTags: [], className: hireling.className, status: "camp", isCustom: false,
    isHireling: true, abilityModifiers: [], usesBuildAbilityScores: false,
  });
  syncPartyProjection();
  syncRunState();
  return true;
}

export function swapActiveMember(outgoingId, incomingId) {
  const outgoingIndex = state.roster.findIndex((entry) => entry.id === outgoingId);
  const incomingIndex = state.roster.findIndex((entry) => entry.id === incomingId);
  const outgoing = state.roster[outgoingIndex];
  const incoming = state.roster[incomingIndex];
  if (outgoing?.status !== "active" || incoming?.status === "active" || !canActivateRosterStatus(incoming?.status)) return false;
  outgoing.status = "camp";
  incoming.status = "active";
  state.roster[outgoingIndex] = incoming;
  state.roster[incomingIndex] = outgoing;
  syncPartyProjection();
  syncRunState();
  return true;
}

export function dismissMember(memberId) {
  state.roster = state.roster.filter((entry) => entry.id !== memberId);
  delete state.equippedByMember[memberId];
  recomputeEquipped();
  syncPartyProjection();
  syncRunState();
}

export function renameMember(memberId, name) {
  const member = state.roster.find((entry) => entry.id === memberId);
  if (!member?.isCustom) return false;
  member.name = name;
  syncPartyProjection();
  syncRunState();
  return true;
}

// Core build assignment; the replace-build confirmation lives in app.js.
// Permanent rewards stay with the character; transient state is cleared.
export function assignBuild(memberId, buildId) {
  const member = state.roster.find((entry) => entry.id === memberId);
  if (!member) return false;
  const permanent = (member.abilityModifiers || []).filter((modifier) => modifier.kind === "permanent");
  if (!buildId) return updateRosterMember(member.id, {
    buildId: null, abilityModifiers: permanent,
    usesBuildAbilityScores: false, appliedAbilitySetupId: null,
  });
  if (!buildFor(buildId)) return false;
  return updateRosterMember(member.id, {
    buildId, abilityModifiers: permanent, usesBuildAbilityScores: true,
    appliedAbilitySetupId: null,
  });
}

export function applyAbilitySetup(memberId, setupId) {
  const member = state.roster.find((entry) => entry.id === memberId);
  const setup = buildFor(member?.buildId)?.abilitySetups?.find((entry) => entry.id === setupId);
  if (!member || !setup) return false;
  return updateRosterMember(member.id, {
    abilityScores: setup.finalScores, usesBuildAbilityScores: true, appliedAbilitySetupId: setup.id,
  });
}

export function resetMemberPlan(memberId) {
  if (!state.roster.some((member) => member.id === memberId)) return false;
  delete state.equippedByMember[memberId];
  recomputeEquipped();
  return updateRosterMember(memberId, {
    buildId: null, abilityModifiers: [], usesBuildAbilityScores: false, appliedAbilitySetupId: null,
  });
}

export function setIncludeCampPlans(enabled) {
  state.includeCampPlans = enabled;
  syncRunState();
}

// ---------------------------------------------------------------------------
// Ability-source predicates: a recorded modifier is tied to its plan source by
// planSourceId, with a label fallback for modifiers saved before ids existed.
// ---------------------------------------------------------------------------

export function modifierMatchesSource(modifier, source) {
  return modifier.planSourceId === source.id || (!modifier.planSourceId && modifier.source === source.label);
}

export function sourceRecorded(member, source) {
  return (member.abilityModifiers || []).some((modifier) => modifierMatchesSource(modifier, source));
}

export function sourceEquipped(member, source) {
  return source.kind === "equipment" && Boolean(source.itemKey) && memberEquipment(member.id).has(source.itemKey);
}

// Who currently holds a unique-across-party source. Labels (not plan-source
// ids) identify uniques across members because ids are build-scoped.
export function sourceOwner(source) {
  return state.roster.find((candidate) => source.kind === "equipment"
    ? Boolean(source.itemKey) && memberEquipment(candidate.id).has(source.itemKey)
    : (candidate.abilityModifiers || []).some((modifier) => modifier.source === source.label)) || null;
}

export function toggleAbilitySource(memberId, sourceId, applied) {
  const member = state.roster.find((entry) => entry.id === memberId);
  const source = buildFor(member?.buildId)?.abilitySources?.find((entry) => entry.id === sourceId);
  if (!member || !source) return false;
  if (!applied && source.uniqueAcrossParty) {
    state.roster.forEach((candidate) => {
      candidate.abilityModifiers = (candidate.abilityModifiers || []).filter((modifier) => modifier.source !== source.label);
    });
  }
  let modifiers = (member.abilityModifiers || []).filter((modifier) => !modifierMatchesSource(modifier, source));
  if (!applied && source.kind === "consumable") modifiers = modifiers.filter((modifier) => modifier.kind !== "temporary");
  if (!applied) modifiers.push({
    id: crypto.randomUUID(), ability: source.ability,
    kind: source.kind === "permanent" ? "permanent" : "temporary",
    mode: source.mode, value: source.value, source: source.label, planSourceId: source.id,
  });
  member.abilityModifiers = modifiers;
  syncPartyProjection();
  syncRunState();
  return true;
}

export function toggleStoryOutcome(outcome) {
  const outcomes = new Set(state.storyOutcomes);
  if (outcomes.has(outcome)) outcomes.delete(outcome); else outcomes.add(outcome);
  state.storyOutcomes = [...outcomes];
  syncRunState();
}

syncPartyProjection();

export const els = {
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
  walkthroughList: document.querySelector("#walkthroughList"),
  walkthroughProgress: document.querySelector("#walkthroughProgress"),
  partyPanel: document.querySelector("#partyPanel"),
  equipmentPanel: document.querySelector("#equipmentPanel"),
  warningsPanel: document.querySelector("#warningsPanel"),
  equipmentBadge: document.querySelector("#equipmentBadge"),
  equipmentActLabel: document.querySelector("#equipmentActLabel"),
  warningsBadge: document.querySelector("#warningsBadge"),
  missingOnlyBtn: document.querySelector("#missingOnlyBtn"),
  tabs: {
    walkthrough: document.querySelector("#tabWalkthrough"),
    route: document.querySelector("#tabRoute"),
    party: document.querySelector("#tabParty"),
    equipment: document.querySelector("#tabEquipment"),
    warnings: document.querySelector("#tabWarnings"),
  },
  pages: {
    walkthrough: document.querySelector("#panelWalkthrough"),
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
};

export const escapeHtml = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#039;", '"': "&quot;",
}[char]));

export function markerClass(marker) {
  return marker.type === "item" ? "item" : marker.importance;
}

// Derived flat set of every equipped item key, recomputed at each mutation of
// state.equippedByMember so isItemEquipped stays O(1) per render pass.
let equippedItems = new Set(Object.values(state.equippedByMember).flat());

export function recomputeEquipped() {
  equippedItems = new Set(Object.values(state.equippedByMember).flat());
}

export function equippedSet() {
  return equippedItems;
}

export function memberEquipment(memberId) {
  return new Set(state.equippedByMember[memberId] || []);
}

export function equipmentOwner(itemKey) {
  const memberId = Object.keys(state.equippedByMember).find((id) => memberEquipment(id).has(itemKey));
  return state.roster.find((member) => member.id === memberId) || null;
}

// Equip toggle from contexts without a member (map pins, route list, detail
// card): equipping assigns the item to the first party member ("tav" when no
// party is saved); unequipping removes it from every member.
export function toggleEquipped(itemKey) {
  if (equippedItems.has(itemKey)) {
    Object.keys(state.equippedByMember).forEach((memberId) => {
      state.equippedByMember[memberId] = state.equippedByMember[memberId].filter((key) => key !== itemKey);
    });
  } else {
    const memberId = state.party[0]?.id || "tav";
    state.equippedByMember[memberId] = [...(state.equippedByMember[memberId] || []), itemKey];
  }
  recomputeEquipped();
  syncRunState();
}

export function toggleMemberEquipment(memberId, itemKey) {
  const assigned = memberEquipment(memberId);
  if (assigned.has(itemKey)) assigned.delete(itemKey);
  else {
    Object.keys(state.equippedByMember).forEach((id) => {
      state.equippedByMember[id] = [...memberEquipment(id)].filter((key) => key !== itemKey);
    });
    assigned.add(itemKey);
  }
  state.equippedByMember[memberId] = [...assigned];
  recomputeEquipped();
  syncRunState();
}

export function isItemEquipped(marker) {
  return marker.type === "item" && equippedItems.has(marker.itemKey);
}

export function isResolved(marker) {
  return marker.type === "item" ? isItemEquipped(marker) : state.done.has(marker.id);
}

export function iconUrl(marker) {
  return marker.icon || null;
}

// Trim the wiki lead ("Titanstring Bow is a rare +1 Longbow that allows…")
// down to the mechanic ("Allows its wielder to add…") for compact cards.
export function effectSnippet(effect) {
  const mechanic = effect.replace(/^.+?\b(?:that|which)\s+/, "");
  const text = mechanic === effect ? effect : mechanic.charAt(0).toUpperCase() + mechanic.slice(1);
  return text.length > 110 ? `${text.slice(0, 108)}…` : text;
}

// ---------------------------------------------------------------------------
// Persistence: run state (done fights + equipped gear + active builds) syncs
// to the backend so it survives browser changes; localStorage covers offline.
// ---------------------------------------------------------------------------

export function persistLocal() {
  localStorage.setItem("bg3-act1-done", JSON.stringify([...state.done]));
  localStorage.setItem("bg3-act1-equipped-by-member", JSON.stringify(state.equippedByMember));
  localStorage.setItem("bg3-act1-builds", JSON.stringify(state.activeBuilds));
  localStorage.setItem("bg3-act1-party", JSON.stringify(state.party));
  localStorage.setItem("bg3-act1-roster", JSON.stringify(state.roster));
  localStorage.setItem("bg3-act1-story-outcomes", JSON.stringify(state.storyOutcomes));
  localStorage.setItem("bg3-act1-include-camp", String(state.includeCampPlans));
  localStorage.setItem("bg3-act1-walkthrough", JSON.stringify(state.walkthroughStatuses));
  localStorage.setItem("bg3-act1-walk-outcomes", JSON.stringify(state.walkthroughOutcomes));
  if (state.focusedWalkthroughStepId) localStorage.setItem("bg3-act1-walk-focus", state.focusedWalkthroughStepId);
  else localStorage.removeItem("bg3-act1-walk-focus");
  localStorage.setItem("bg3-act1-timed-ack", JSON.stringify([...state.ackTimed]));
}

export function syncRunState() {
  persistLocal();
  clearTimeout(state.loadoutSyncTimer);
  state.loadoutSyncTimer = setTimeout(() => {
    fetch("/api/run-state", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        equippedByMember: state.equippedByMember,
        builds: state.activeBuilds,
        done: [...state.done],
        walkthroughStatuses: state.walkthroughStatuses,
        walkthroughOutcomes: state.walkthroughOutcomes,
        focusedWalkthroughStepId: state.focusedWalkthroughStepId,
        party: state.party,
        roster: state.roster,
        storyOutcomes: state.storyOutcomes,
        includeCampPlans: state.includeCampPlans,
      }),
    }).catch(() => {});
  }, 350);
}

export async function restoreRunState() {
  try {
    const payload = await (await fetch("/api/run-state")).json();
    const hasServerState = Object.keys(payload.equippedByMember || {}).length || payload.builds?.length || payload.done?.length || payload.party?.length || payload.roster?.length
      || Object.keys(payload.walkthroughStatuses || {}).length || payload.focusedWalkthroughStepId;
    if (hasServerState) {
      state.done = new Set(payload.done || []);
      state.walkthroughStatuses = payload.walkthroughStatuses || {};
      state.walkthroughOutcomes = payload.walkthroughOutcomes || {};
      state.focusedWalkthroughStepId = payload.focusedWalkthroughStepId || null;
      state.equippedByMember = payload.equippedByMember || {};
      recomputeEquipped();
      if (payload.roster?.length) state.roster = payload.roster;
      else if (payload.party?.length) state.roster = normalizeRoster([], payload.party);
      state.storyOutcomes = payload.storyOutcomes || [];
      state.includeCampPlans = payload.includeCampPlans ?? state.includeCampPlans;
      syncPartyProjection();
      state.activeBuilds = payload.builds || [];
      persistLocal();
      return true;
    } else if (equippedItems.size || state.activeBuilds.length || state.done.size || Object.keys(state.walkthroughStatuses).length || state.focusedWalkthroughStepId) {
      syncRunState(); // seed the backend from this browser's saved state
    }
  } catch { /* backend offline: localStorage still applies */ }
  return false;
}
