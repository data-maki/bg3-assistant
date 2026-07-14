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
  markerExport: null,
};

const DEFAULT_ROSTER = [
  { id: "tav", name: "Tav", className: null, isCustom: true, status: "active" },
  { id: "shadowheart", name: "Shadowheart", className: "Cleric", isCustom: false, status: "active" },
  { id: "laezel", name: "Lae'zel", className: "Fighter", isCustom: false, status: "active" },
  { id: "astarion", name: "Astarion", className: "Rogue", isCustom: false, status: "active" },
  { id: "gale", name: "Gale", className: "Wizard", isCustom: false, status: "camp" },
  { id: "wyll", name: "Wyll", className: "Warlock", isCustom: false, status: "camp" },
  { id: "karlach", name: "Karlach", className: "Barbarian", isCustom: false, status: "camp" },
];

export function normalizeRoster(roster = state.roster, legacyParty = state.party) {
  const source = roster.length ? roster : legacyParty.map((member, index) => ({
    ...member, status: "active", isCustom: member.isCustom ?? index === 0,
  }));
  if (!source.length) return [];
  const members = source.map((member, index) => ({
    ...member,
    level: Math.min(12, Math.max(1, Number(member.level) || 1)),
    status: member.status || "active",
    isCustom: member.isCustom ?? index === 0,
  }));
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
  if (state.party.length) state.activeBuilds = [...new Set(state.party.map((member) => member.buildId).filter(Boolean))];
}

export function plannedRosterMembers() {
  const statuses = state.includeCampPlans ? new Set(["active", "camp"]) : new Set(["active"]);
  return state.roster.filter((member) => statuses.has(member.status));
}

export function updateRosterMember(memberId, changes) {
  const index = state.roster.findIndex((member) => member.id === memberId);
  if (index < 0) return false;
  const currentStatus = state.roster[index].status;
  const nextStatus = changes.status || state.roster[index].status;
  if (nextStatus === "active" && !["active", "camp"].includes(currentStatus)) return false;
  if (nextStatus === "active" && state.roster[index].status !== "active" && state.party.length >= 4) return false;
  state.roster[index] = { ...state.roster[index], ...changes };
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

// One-time migration from the retired flat "bg3-act1-equipped" set: attribute
// every legacy item to the first party member ("tav" when no party is saved).
// This attribution is an approximation — the flat set never recorded who
// actually wears each item. The legacy key is no longer written.
const legacyEquipped = JSON.parse(localStorage.getItem("bg3-act1-equipped") || "[]");
if (!Object.keys(state.equippedByMember).length && legacyEquipped.length) {
  state.equippedByMember[state.party[0]?.id || "tav"] = legacyEquipped;
  localStorage.setItem("bg3-act1-equipped-by-member", JSON.stringify(state.equippedByMember));
}
localStorage.removeItem("bg3-act1-equipped");

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
  exportMarkersBtn: document.querySelector("#exportMarkersBtn"),
  markerExportDialog: document.querySelector("#markerExportDialog"),
  markerExportSummary: document.querySelector("#markerExportSummary"),
  markerExportWarnings: document.querySelector("#markerExportWarnings"),
  markerExportList: document.querySelector("#markerExportList"),
  markerExportFingerprint: document.querySelector("#markerExportFingerprint"),
  downloadMarkersBtn: document.querySelector("#downloadMarkersBtn"),
  confirmMarkersBtn: document.querySelector("#confirmMarkersBtn"),
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
  localStorage.removeItem("bg3-act1-walk-recovery"); // migrate the retired routine-recovery gate
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
    } else if (equippedItems.size || state.activeBuilds.length || state.done.size || Object.keys(state.walkthroughStatuses).length || state.focusedWalkthroughStepId) {
      syncRunState(); // seed the backend from this browser's saved state
    }
  } catch { /* backend offline: localStorage still applies */ }
}
