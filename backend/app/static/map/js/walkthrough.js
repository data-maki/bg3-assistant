// Comprehensive Act 1 walkthrough. This is deliberately separate from map
// markers: dialogue, exploration, and decisions are progress, not fights.
// Mutators return true when they changed state so app.js knows to re-render;
// nothing here calls render() or binds listeners.

import { state, els, escapeHtml, syncRunState } from "./state.js";

const WALK_KIND = {
  exploration: { glyph: "◇", label: "Explore", cls: "neutral" },
  pickup: { glyph: "◆", label: "Pickup", cls: "neutral" },
  gate: { glyph: "⬢", label: "Gate", cls: "neutral" },
};

// What the player actually does at a step: fight, talk, or be ready for both.
// A conversation with a run-ender protocol can turn hostile; a fight with a
// reviewed decision starts as a conversation.
function stepEncounter(step) {
  const isFight = ["major_fight", "mini_fight"].includes(step.kind);
  const hasTalk = ["dialogue", "decision"].includes(step.kind) || (isFight && Boolean(step.decision));
  const canTurnHostile = Boolean(step.incident);
  if (isFight && hasTalk) return { glyph: "◈⚔", label: "Talk · Fight", cls: "both", hint: "Starts as a conversation — can turn into a fight" };
  if (isFight) return { glyph: "⚔", label: "Fight", cls: "fight" };
  if (hasTalk && canTurnHostile) return { glyph: "◈⚔", label: "Talk · Fight", cls: "both", hint: "Starts as a conversation — can turn into a fight" };
  if (hasTalk) return { glyph: "◈", label: "Talk", cls: "talk" };
  return WALK_KIND[step.kind] || { glyph: "•", label: step.kind, cls: "neutral" };
}

function walkthroughStatus(step) {
  const explicit = state.walkthroughStatuses[step.id];
  if (explicit) return explicit;
  return step.checkpointId && state.done.has(step.checkpointId) ? "done" : "pending";
}

function walkthroughResolved(step) {
  return ["done", "skipped"].includes(walkthroughStatus(step));
}

function dependencySatisfied(dependency) {
  const status = walkthroughStatus({ id: dependency.stepId });
  if (dependency.kind === "warning_only") return true;
  if (dependency.kind === "completion_required") return status === "done";
  if (dependency.kind === "outcome_required") {
    return status === "done" && state.walkthroughOutcomes[dependency.stepId] === dependency.requiredOutcome;
  }
  return ["done", "skipped"].includes(status);
}

export function walkthroughBlockers(step) {
  const steps = state.data.walkthrough || [];
  return (step.dependencies || []).filter((dependency) => !dependencySatisfied(dependency)).map((dependency) => {
    const prerequisite = steps.find((entry) => entry.id === dependency.stepId);
    if (walkthroughStatus({ id: dependency.stepId }) === "skipped"
      && ["completion_required", "outcome_required"].includes(dependency.kind)) {
      return `Revisit ${prerequisite?.title || dependency.stepId} — ${dependency.reason}`;
    }
    return dependency.reason;
  });
}

function recommendedWalkthroughStep() {
  const steps = state.data.walkthrough || [];
  const pending = steps.filter((step) => !walkthroughResolved(step));
  if (!pending.length) return null;
  const phaseOrder = Math.min(...pending.map((step) => step.phaseOrder));
  const phase = pending.filter((step) => step.phaseOrder === phaseOrder);
  const candidates = phase.filter((step) => walkthroughBlockers(step).length === 0);
  if (!candidates.length) return null;
  const level = Number(els.level.value);
  return candidates.find((step) => walkthroughStatus(step) === "revisit" && step.minimumLevel <= level)
    || candidates.find((step) => step.minimumLevel <= level)
    || candidates[0];
}

function focusedWalkthroughStep() {
  const step = (state.data.walkthrough || []).find((entry) => entry.id === state.focusedWalkthroughStepId);
  if (!step || walkthroughResolved(step)) {
    state.focusedWalkthroughStepId = null;
    return null;
  }
  return step;
}

function currentWalkthroughStep() {
  return focusedWalkthroughStep() || recommendedWalkthroughStep();
}

export function focusWalkthroughStep(stepId) {
  const step = (state.data.walkthrough || []).find((entry) => entry.id === stepId);
  if (!step || walkthroughResolved(step)) return false;
  state.focusedWalkthroughStepId = step.id;
  if (state.data.regions.includes(step.region)) {
    els.region.value = step.region;
    state.lastRegion = step.region;
  }
  syncRunState();
  return true;
}

function decisionOption(option, recommended = false) {
  return `<section class="tradeoff-option ${recommended ? "recommended" : ""}">
    <h5>${recommended ? "Recommended · " : "Alternative · "}${escapeHtml(option.label)}</h5>
    ${(option.benefits || []).length ? `<p class="tradeoff-gain"><strong>Preserves / gains</strong> ${escapeHtml(option.benefits.join(" · "))}</p>` : ""}
    ${(option.costs || []).length ? `<p class="tradeoff-cost"><strong>Costs / risks</strong> ${escapeHtml(option.costs.join(" · "))}</p>` : ""}
  </section>`;
}

// Decision steps resolve by recording WHICH option actually happened — a
// binary Done makes no sense once the run diverged (Rolan may have left).
function outcomeButtons(step, status) {
  if (status === "done") return "";
  const recommended = step.decision.recommended;
  const alternatives = step.decision.alternatives || [];
  const primary = `<button class="walk-action action-outcome recommended"
    data-walk-outcome="${escapeHtml(recommended.label)}" data-step-id="${escapeHtml(step.id)}"
    title="Record recommended outcome: ${escapeHtml(recommended.label)}">✓ ${escapeHtml(recommended.label.length > 34 ? recommended.label.slice(0, 32) + "…" : recommended.label)}</button>`;
  if (!alternatives.length) return primary;
  return `${primary}<details class="outcome-more"><summary>Other outcome</summary>
    ${alternatives.map((option) => `<button class="walk-action action-outcome"
      data-walk-outcome="${escapeHtml(option.label)}" data-step-id="${escapeHtml(step.id)}"
      title="Record outcome: ${escapeHtml(option.label)}">${escapeHtml(option.label)}</button>`).join("")}
  </details>`;
}

function outcomeLine(step) {
  const outcome = state.walkthroughOutcomes[step.id];
  if (!outcome || walkthroughStatus(step) !== "done") return "";
  const divergent = step.decision && outcome !== step.decision.recommended.label;
  return `<p class="walk-outcome ${divergent ? "divergent" : ""}"><strong>OUTCOME</strong> ${escapeHtml(outcome)}${divergent ? " (differs from the guide's pick — later steps may not apply)" : ""}</p>`;
}

function decisionBlock(step) {
  if (!step.decision) return "";
  const authority = step.decision.authority === "guide_fact" ? "GUIDE FACT" : "ASSISTANT SUGGESTION";
  return `<section class="tradeoff">
    <h5>DECISION · ${authority}${step.decision.reversible ? " · reversible" : " · irreversible"}</h5>
    <p class="tradeoff-prompt">${escapeHtml(step.decision.prompt)}</p>
    ${decisionOption(step.decision.recommended, true)}
    ${(step.decision.alternatives || []).map((option) => decisionOption(option)).join("")}
  </section>`;
}

function incidentForStep(step) {
  if (step.incident) return step.incident;
  if (!step.checkpointId) return null;
  const fight = state.data.markers.find((marker) => marker.id === step.checkpointId);
  if (!fight) return null;
  return {
    trigger: fight.failureConditions?.[0] || "The encounter stops following the prepared plan.",
    safeActions: (fight.preparation || []).slice(0, 3),
    never: step.avoid || fight.advice,
    escape: "Preserve one character with mobility or invisibility and use the prepared exit if the encounter allows fleeing.",
    honorDelta: fight.legendaryAction || "No additional Honor-only mechanic is recorded for this encounter.",
    authority: "guide_fact",
    sourceUrl: fight.wiki || fight.source,
  };
}

function incidentBlock(step) {
  const incident = incidentForStep(step);
  if (!incident) return "";
  return `<section class="incident-protocol">
    <h5>PANIC PLAN · ${incident.authority === "guide_fact" ? "GUIDE FACT" : "REVIEWED INCIDENT"}</h5>
    <p><strong>TRIGGER</strong> ${escapeHtml(incident.trigger)}</p>
    ${(incident.safeActions || []).map((action) => `<p class="incident-do"><strong>DO</strong> ${escapeHtml(action)}</p>`).join("")}
    <p class="incident-never"><strong>NEVER</strong> ${escapeHtml(incident.never)}</p>
    <p class="incident-escape"><strong>IF IT GOES WRONG</strong> ${escapeHtml(incident.escape)}</p>
    ${incident.honorDelta ? `<p class="incident-delta"><strong>HONOR DELTA</strong> ${escapeHtml(incident.honorDelta)}</p>` : ""}
    ${incident.sourceUrl ? `<a href="${escapeHtml(incident.sourceUrl)}" target="_blank" rel="noreferrer">Protocol source ↗</a>` : ""}
  </section>`;
}

function riskRewardBlock(step) {
  const value = step.riskReward;
  if (!value) return "";
  return `<section class="risk-reward">
    <h5>WHY DO THIS?</h5>
    <p class="tradeoff-gain"><strong>REWARD</strong> ${escapeHtml(value.reward)}</p>
    <p class="tradeoff-cost"><strong>RISK</strong> ${escapeHtml(value.risk)}</p>
    <p><strong>SKIP</strong> ${escapeHtml(value.skipCost)}</p>
    <p><strong>RETURN</strong> ${escapeHtml(value.returnBy)}</p>
  </section>`;
}

function stepContextBlock(step, authority) {
  const hasContext = step.decision || incidentForStep(step) || step.riskReward || (step.rewards || []).length || step.sourceUrl;
  if (!hasContext) return "";
  return `<details class="step-context">
    <summary>More context</summary>
    <div class="step-context__body">
      ${step.decision ? `<p class="context-do"><strong>DO</strong> ${escapeHtml(step.summary)}</p>` : ""}
      ${powerRewardLine(step)}
      ${decisionBlock(step)}
      ${incidentBlock(step)}
      ${riskRewardBlock(step)}
      ${step.sourceUrl ? `<a class="context-source" href="${escapeHtml(step.sourceUrl)}" target="_blank" rel="noreferrer" title="${escapeHtml(step.sourceLabel)}">${escapeHtml(authority)} ↗</a>` : ""}
    </div>
  </details>`;
}

function powerRewardLine(step) {
  const rewards = step.rewards || [];
  if (!rewards.length) return "";
  const visible = rewards.slice(0, 3);
  const remainder = rewards.length - visible.length;
  return `<p class="walk-step__rewards"><strong>POWER</strong> ${escapeHtml(visible.join(" · "))}${remainder ? ` <span>+${remainder}</span>` : ""}</p>`;
}

function walkthroughStepDetail(step, recommended, focused = false) {
  const status = walkthroughStatus(step);
  const meta = stepEncounter(step);
  const under = Number(els.level.value) < step.minimumLevel;
  const authority = step.authority === "guide_fact" ? "Guide fact" : "Assistant route";
  const instructionLabel = step.decision ? "SAY" : "DO";
  const instruction = step.decision?.recommended?.label || step.summary;
  return `<article class="walk-shared-detail status-${status} ${recommended ? "is-next" : ""} ${focused ? "is-focused" : ""}" data-step-id="${escapeHtml(step.id)}">
    <button class="walk-detail-close" data-walk-detail-close aria-label="Close route detail">×</button>
    <header class="walk-step__header">
      <span class="walk-step__glyph encounter-${meta.cls}" title="${escapeHtml(meta.hint || meta.label)}">${meta.glyph}</span>
      <div class="walk-step__title">
        <h4>${escapeHtml(step.title)}</h4>
        <p><span class="encounter-label encounter-${meta.cls}">${escapeHtml(meta.label)}</span> · L${step.minimumLevel}+ · ${escapeHtml(step.area)}</p>
        ${meta.hint ? `<p class="encounter-hint">${escapeHtml(meta.hint)}</p>` : ""}
      </div>
      ${under ? `<span class="badge under">Wait</span>` : `<span class="badge ready">Ready</span>`}
    </header>
    <p class="walk-step__do"><strong>${instructionLabel}</strong> ${escapeHtml(instruction)}</p>
    ${step.avoid ? `<p class="walk-step__avoid"><strong>AVOID</strong> ${escapeHtml(step.avoid)}</p>` : ""}
    ${outcomeLine(step)}
    <footer class="walk-step__footer">
      <div class="walk-actions" role="group" aria-label="Progress for ${escapeHtml(step.title)}">
        ${!walkthroughResolved(step) ? `<button class="walk-action action-focus ${focused ? "active" : ""}" data-walk-focus="${escapeHtml(step.id)}">${focused ? "◆ Focused" : "Focus"}</button>` : ""}
        ${step.decision ? outcomeButtons(step, status) : `<button class="walk-action action-done ${status === "done" ? "active" : ""}" data-walk-status="done" data-step-id="${escapeHtml(step.id)}">✓ Done</button>`}
        <button class="walk-action action-skip ${status === "skipped" ? "active" : ""}" data-walk-status="skipped" data-step-id="${escapeHtml(step.id)}">Skip</button>
        <button class="walk-action action-revisit ${status === "revisit" ? "active" : ""}" data-walk-status="revisit" data-step-id="${escapeHtml(step.id)}">Revisit</button>
      </div>
      <div class="walk-links">
        ${step.markerId ? `<button class="walk-map" data-walk-map="${escapeHtml(step.markerId)}">Map</button>` : ""}
      </div>
    </footer>
    ${stepContextBlock(step, authority)}
  </article>`;
}

function walkthroughStepRow(step, recommended, focused = false) {
  const meta = stepEncounter(step);
  const blockers = walkthroughBlockers(step);
  const under = Number(els.level.value) < step.minimumLevel;
  const reward = (step.rewards || [])[0];
  const stateLabel = blockers.length ? "Blocked" : under ? `Wait L${step.minimumLevel}` : `L${step.minimumLevel}+`;
  return `<article class="walk-rail-row ${recommended ? "is-next" : ""} ${focused ? "is-focused" : ""} ${blockers.length ? "is-blocked" : ""}" data-step-id="${escapeHtml(step.id)}">
    <button class="walk-row-select" data-walk-select="${escapeHtml(step.id)}" aria-label="Open ${escapeHtml(step.title)} details">
      <span class="walk-step__glyph encounter-${meta.cls}" title="${escapeHtml(meta.hint || meta.label)}">${meta.glyph}</span>
      <span class="walk-rail-copy"><strong>${escapeHtml(step.title)}</strong><small>${blockers.length ? `Needs: ${escapeHtml(blockers[0])}` : escapeHtml(reward ? `${reward} · ${step.area}` : step.area)}</small></span>
      <span class="walk-rail-tags">${recommended ? `<em class="rail-tag recommended">Recommended</em>` : ""}${focused ? `<em class="rail-tag focused">Your focus</em>` : ""}<b>${escapeHtml(stateLabel)}</b></span>
    </button>
    <button class="walk-focus-icon ${focused ? "active" : ""}" data-walk-focus="${escapeHtml(step.id)}" title="${focused ? "Current player focus" : `Focus ${escapeHtml(step.title)}`}" aria-label="${focused ? "Current focus" : "Focus"}: ${escapeHtml(step.title)}">◎</button>
  </article>`;
}

function walkthroughArchiveCard(step) {
  const status = walkthroughStatus(step);
  return `<article class="walk-archive-row status-${status}">
    <span>${status === "done" ? "✓" : "→"}</span>
    <div><strong>${escapeHtml(step.title)}</strong><small>${status === "done" ? "Done" : "Skipped"} · ${escapeHtml(step.area)}</small>${outcomeLine(step)}</div>
    <button class="walk-action action-revisit" data-walk-status="revisit" data-step-id="${escapeHtml(step.id)}">Revisit</button>
  </article>`;
}

export function renderWalkthrough() {
  const steps = state.data?.walkthrough || [];
  if (!steps.length) {
    els.walkthroughList.innerHTML = `<p class="empty-note">Walkthrough data unavailable.</p>`;
    return;
  }
  const recommended = recommendedWalkthroughStep();
  const next = currentWalkthroughStep();
  const focused = focusedWalkthroughStep();
  const focusedBlockers = focused ? walkthroughBlockers(focused) : [];
  const resolved = steps.filter(walkthroughResolved).length;
  const done = steps.filter((step) => walkthroughStatus(step) === "done").length;
  const skipped = steps.filter((step) => walkthroughStatus(step) === "skipped").length;
  const revisits = steps.filter((step) => walkthroughStatus(step) === "revisit").length;
  els.walkthroughProgress.textContent = `${resolved}/${steps.length}`;

  const nextCard = next ? `<section class="next-step-card ${focusedBlockers.length || Number(els.level.value) < next.minimumLevel ? "blocked" : ""}">
    <p class="eyebrow">${focused ? "YOUR FOCUS" : Number(els.level.value) < next.minimumLevel ? "LEVEL GATE" : "DO NEXT"}</p>
    <h3>${escapeHtml(next.title)}</h3>
    <p>${focusedBlockers.length ? `BLOCKED · ${escapeHtml(focusedBlockers[0])}` : Number(els.level.value) < next.minimumLevel ? `Reach L${next.minimumLevel} in ${escapeHtml(next.phase)} before committing.` : escapeHtml(next.summary)}</p>
    ${powerRewardLine(next)}
    ${next.avoid ? `<p class="next-avoid"><strong>AVOID</strong> ${escapeHtml(next.avoid)}</p>` : ""}
    ${focused && recommended && focused.id !== recommended.id ? `<button class="walk-action action-recommended" data-walk-focus="${escapeHtml(recommended.id)}">Recommended instead · ${escapeHtml(recommended.title)}</button>` : ""}
  </section>` : steps.some((step) => !walkthroughResolved(step)) ? (() => {
    const pending = steps.filter((step) => !walkthroughResolved(step));
    const phaseOrder = Math.min(...pending.map((step) => step.phaseOrder));
    const blocked = pending.filter((step) => step.phaseOrder === phaseOrder).sort((a, b) => a.order - b.order)[0];
    const blocker = blocked ? walkthroughBlockers(blocked)[0] : "Resolve the current route prerequisite.";
    return `<section class="next-step-card blocked"><p class="eyebrow">ROUTE BLOCKED</p><h3>${escapeHtml(blocked?.title || "No eligible activity")}</h3><p>${escapeHtml(blocker)}</p></section>`;
  })() : `<section class="next-step-card complete"><p class="eyebrow">ACT 1 COMPLETE</p><h3>No unresolved walkthrough steps</h3><p>Run the Act 2 gate once more, then advance deliberately.</p></section>`;

  const activeSteps = steps.filter((step) => !walkthroughResolved(step));
  const archivedSteps = steps.filter(walkthroughResolved);
  const selected = steps.find((step) => step.id === state.selectedWalkthroughStepId);
  const selectedDetail = selected
    ? walkthroughStepDetail(selected, selected.id === recommended?.id, selected.id === focused?.id)
    : "";
  const phases = [...new Map(activeSteps.map((step) => [step.phaseOrder, step.phase])).entries()]
    .sort((a, b) => a[0] - b[0]);
  const currentPhase = next?.phaseOrder;
  const phaseCards = phases.map(([phaseOrder, phase]) => {
    const phaseSteps = activeSteps.filter((step) => step.phaseOrder === phaseOrder);
    const open = phaseOrder === currentPhase || phaseSteps.some((step) => walkthroughStatus(step) === "revisit");
    return `<details class="walk-phase" ${open ? "open" : ""}>
      <summary><span>${escapeHtml(phase)}</span><strong>${phaseSteps.length} active</strong></summary>
      <div class="walk-phase__steps">${phaseSteps.map((step) => walkthroughStepRow(step, step.id === recommended?.id, step.id === focused?.id)).join("")}</div>
    </details>`;
  }).join("");

  const archive = archivedSteps.length ? `<details class="walk-archive">
    <summary>Archive <strong>${archivedSteps.length}</strong></summary>
    <div class="walk-archive__steps">${archivedSteps.sort((a, b) => b.order - a.order).map(walkthroughArchiveCard).join("")}</div>
  </details>` : "";

  els.walkthroughList.innerHTML = `${nextCard}${selectedDetail}
    <div class="ledger-summary"><span>${done} done</span><span>${skipped} skipped</span><span>${revisits} revisit</span><strong>Manual only</strong></div>
    ${phaseCards}
    ${archive}`;
}

export function setWalkthroughStatus(stepId, requestedStatus) {
  const step = (state.data.walkthrough || []).find((entry) => entry.id === stepId);
  if (!step) return false;
  const current = walkthroughStatus(step);
  if (current === requestedStatus) delete state.walkthroughStatuses[stepId];
  else state.walkthroughStatuses[stepId] = requestedStatus;

  // This is an explicit player action. Keep the legacy 19-fight checklist in
  // sync for linked steps; vision never calls this function.
  if (step.checkpointId) {
    if (state.walkthroughStatuses[stepId] === "done") state.done.add(step.checkpointId);
    else state.done.delete(step.checkpointId);
  }
  if (["done", "skipped"].includes(state.walkthroughStatuses[stepId])) {
    if (state.focusedWalkthroughStepId === stepId) state.focusedWalkthroughStepId = null;
  } else if (requestedStatus === "revisit") {
    state.focusedWalkthroughStepId = stepId;
  }
  syncRunState();
  return true;
}
