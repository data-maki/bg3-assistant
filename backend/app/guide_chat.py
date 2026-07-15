"""Deterministic guide-grounded chat.

Keyword-routes the player's question to the relevant reviewed guide facts for
the current checkpoint. Deliberately not an LLM: answers must never invent
route facts, and every line is traceable to the guide data.
"""

from .chat_context import resolve_chat_context
from .models import ChatRequest, ChatResponse, DecisionOption, ReadinessRequest, RouteCheckpoint, WalkthroughStep
from .route_data import assess_readiness


def _alternative(option: DecisionOption) -> str:
    return f"Alternative: {option.label} — risks: {'; '.join(option.costs)}"


def guide_facts(checkpoint: RouteCheckpoint, step: WalkthroughStep | None) -> list[str]:
    """The complete reviewed fact set for a checkpoint (and current step), one line each."""
    lines = [
        f"Checkpoint: {checkpoint.name} ({checkpoint.area}, {checkpoint.region}).",
        f"Minimum recommended level: {checkpoint.minimum_level}. Danger: {checkpoint.danger}.",
        f"Advice: {checkpoint.advice}",
    ]
    if checkpoint.enemies:
        lines.append(f"Enemies: {checkpoint.enemies}")
    if checkpoint.legendary_action:
        lines.append("Legendary action: " + checkpoint.legendary_action)
    if checkpoint.failure_conditions:
        lines.append("Failure conditions: " + "; ".join(checkpoint.failure_conditions))
    if checkpoint.preparation:
        lines.append("Preparation: " + "; ".join(checkpoint.preparation))
    if checkpoint.irreversible_warnings:
        lines.append("Time-sensitive/irreversible: " + "; ".join(checkpoint.irreversible_warnings))
    if step:
        lines.append(f"Walkthrough step: {step.title} — {step.summary}")
        if step.rewards:
            lines.append("Power rewards: " + "; ".join(step.rewards))
        if step.avoid:
            lines.append("Avoid: " + step.avoid)
        if step.decision:
            lines.append(
                f"Reviewed decision: recommended '{step.decision.recommended.label}' "
                f"(benefits: {'; '.join(step.decision.recommended.benefits)})."
            )
            lines.extend(_alternative(option) for option in step.decision.alternatives)
            if step.incident:
                lines.append("Never: " + step.incident.never)
    return lines


def grounding_facts(checkpoint: RouteCheckpoint, request: ChatRequest, step: WalkthroughStep | None) -> list[str]:
    """Trusted guide facts plus a server-resolved, authority-labelled run snapshot."""
    context = resolve_chat_context(checkpoint, request, step)
    return [*guide_facts(checkpoint, context.current or step), *context.grounding_lines(checkpoint)]


def answer(checkpoint: RouteCheckpoint, request: ChatRequest, step: WalkthroughStep | None = None) -> ChatResponse:
    message = request.message.lower()
    context = resolve_chat_context(checkpoint, request, step)
    step = context.current or step
    facts: list[str] = []
    suggestions: list[str] = []
    unknowns: list[str] = []

    if context.blockers:
        facts.extend(context.blockers)
        if context.recommended:
            action = f"Do {context.recommended.title} first; {step.title if step else 'your focus'} is blocked."
        else:
            action = f"Resolve the named prerequisite before attempting {step.title if step else checkpoint.name}."
    elif step:
        action = f"Do {step.title} in {step.area}."
    else:
        action = f"Go to {checkpoint.area} for {checkpoint.name}."

    risk = (
        (step.incident.never if step and step.incident else None)
        or (step.avoid if step else None)
        or (checkpoint.failure_conditions[0] if checkpoint.failure_conditions else None)
        or checkpoint.advice
    )

    if any(word in message for word in ("dialogue", "dialog", "decision", "choice", "choose", "talk")):
        if step and step.decision:
            decision_facts = facts if step.decision.authority == "guide_fact" else suggestions
            decision_facts.append(f"Recommended: {step.decision.recommended.label}.")
            decision_facts.extend(step.decision.recommended.benefits)
            suggestions.extend(_alternative(option) for option in step.decision.alternatives)
            if step.incident:
                incident_facts = facts if step.incident.authority == "guide_fact" else suggestions
                incident_facts.append("Never: " + step.incident.never)
        else:
            facts.extend(item.text for item in checkpoint.honor_decisions if item.kind == "guide_fact")
            suggestions.extend(item.text for item in checkpoint.honor_decisions if item.kind != "guide_fact")
        if not facts and not suggestions:
            unknowns.append("The reviewed guide does not record a checkpoint-specific dialogue decision here.")
    elif any(word in message for word in ("ready", "level", "prepare")):
        assessment = assess_readiness(
            ReadinessRequest(
                checkpoint_id=checkpoint.id,
                party=context.active,
                completed_checkpoint_ids=request.completed_checkpoint_ids,
            )
        )
        facts.append(f"Guide minimum: level {checkpoint.minimum_level}.")
        facts.extend(checkpoint.preparation[:3])
        suggestions.extend(assessment.blockers + assessment.warnings[:3] + assessment.next_actions[:6])
        suggestions.extend(f"{member.name} {context.build_actions[member.id]}" for member in context.active if member.id in context.build_actions)
    elif any(word in message for word in ("die", "danger", "end my run", "legendary")):
        if step and step.incident:
            incident_facts = facts if step.incident.authority == "guide_fact" else suggestions
            incident_facts.extend(["Trigger: " + step.incident.trigger, "Never: " + step.incident.never])
            if step.incident.honor_delta:
                incident_facts.append("Honor delta: " + step.incident.honor_delta)
            suggestions.extend(step.incident.safe_actions)
            suggestions.append("If it goes wrong: " + step.incident.escape)
        else:
            facts.extend(checkpoint.failure_conditions[:3])
            if checkpoint.legendary_action:
                facts.insert(0, "Legendary action: " + checkpoint.legendary_action)
            suggestions.append(checkpoint.advice)
    elif any(word in message for word in ("where", "next", "go")):
        if step:
            facts.append(f"Next step: {step.title} in {step.area}, {step.region}.")
            suggestions.append(step.summary)
        else:
            facts.append(f"Next destination: {checkpoint.area} in {checkpoint.region}.")
            facts.append(f"Guide coordinates: X {checkpoint.x}, Y {checkpoint.y}.")
            suggestions.append(checkpoint.advice)
    elif any(word in message for word in ("long rest", "rest")):
        facts.extend(checkpoint.irreversible_warnings)
        if not checkpoint.irreversible_warnings:
            unknowns.append("The guide does not mark a checkpoint-specific long-rest failure here.")
        suggestions.append("Confirm any active timed quest in the journal before resting.")
    elif any(word in message for word in ("reward", "equipment", "item", "loot", "gear", "power")):
        if step and step.rewards:
            step_facts = facts if step.authority == "guide_fact" else suggestions
            step_facts.append("Power reward: " + "; ".join(step.rewards) + ".")
            step_facts.append(f"Location: {step.area}, {step.region}.")
            suggestions.append(step.summary)
        for member in context.active:
            if missing := context.missing_gear(member.id):
                pick = next((item for item in missing if item.map_objective), missing[0])
                suggestions.append(f"{member.name}: pursue {pick.item} — {pick.acquisition}")
        unknowns.extend(context.equipment_conflicts)
        if not context.equipment_known:
            unknowns.append("Equipment ownership has not been confirmed; loadout suggestions may already be owned.")
        if not facts and not suggestions:
            unknowns.append("The current walkthrough step does not record a specific power reward.")
    else:
        if step:
            step_facts = facts if step.authority == "guide_fact" else suggestions
            step_facts.extend([step.summary, "Avoid: " + step.avoid])
        else:
            facts.extend([checkpoint.advice, *checkpoint.preparation[:3]])
        unknowns.append("Ask about readiness, danger, destination, preparation, or long rests for a narrower answer.")

    if context.scope == "party" or any(word in message for word in ("party", "camp", "dead", "karlach", "wyll", "lae'zel")):
        if context.inactive:
            suggestions.append("Inactive roster: " + ", ".join(f"{member.name} ({member.status or 'camp'})" for member in context.inactive))
        if context.story_outcomes:
            suggestions.append("Player-confirmed outcomes: " + "; ".join(context.story_outcomes))

    answer_parts = ["Action: " + action, "DON'T DIE: " + risk]
    if facts:
        answer_parts.append("Guide says: " + " ".join(dict.fromkeys(facts)))
    if suggestions:
        answer_parts.append("Assistant suggestion: " + " ".join(suggestions))
    if unknowns:
        answer_parts.append("Unknown: " + " ".join(unknowns))
    return ChatResponse(
        answer="\n\n".join(answer_parts),
        guide_facts=facts,
        assistant_suggestions=suggestions,
        unknowns=unknowns,
    )
