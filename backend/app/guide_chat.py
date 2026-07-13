"""Deterministic guide-grounded chat.

Keyword-routes the player's question to the relevant reviewed guide facts for
the current checkpoint. Deliberately not an LLM: answers must never invent
route facts, and every line is traceable to the guide data.
"""

from .models import ChatRequest, ChatResponse, ReadinessRequest, RouteCheckpoint
from .route_data import assess_readiness


def answer(checkpoint: RouteCheckpoint, request: ChatRequest) -> ChatResponse:
    message = request.message.lower()
    guide_facts: list[str] = []
    suggestions: list[str] = []
    unknowns: list[str] = []

    if any(word in message for word in ("dialogue", "dialog", "decision", "choice", "choose", "talk")):
        guide_facts.extend(item.text for item in checkpoint.honor_decisions if item.kind == "guide_fact")
        suggestions.extend(item.text for item in checkpoint.honor_decisions if item.kind != "guide_fact")
        if not checkpoint.honor_decisions:
            unknowns.append("The reviewed guide does not record a checkpoint-specific dialogue decision here.")
    elif any(word in message for word in ("ready", "level", "prepare")):
        assessment = assess_readiness(
            ReadinessRequest(
                checkpoint_id=checkpoint.id,
                party=request.party,
                completed_checkpoint_ids=request.completed_checkpoint_ids,
            )
        )
        guide_facts.append(f"Guide minimum: level {checkpoint.minimum_level}.")
        guide_facts.extend(checkpoint.preparation[:5])
        suggestions.extend(assessment.blockers + assessment.warnings[:3] + assessment.next_actions[:6])
    elif any(word in message for word in ("die", "danger", "end my run", "legendary")):
        guide_facts.extend(checkpoint.failure_conditions)
        if checkpoint.legendary_action:
            guide_facts.insert(0, "Legendary action: " + checkpoint.legendary_action)
        suggestions.append(checkpoint.advice)
    elif any(word in message for word in ("where", "next", "go")):
        guide_facts.append(f"Next destination: {checkpoint.area} in {checkpoint.region}.")
        guide_facts.append(f"Guide coordinates: X {checkpoint.x}, Y {checkpoint.y}.")
        suggestions.append(checkpoint.advice)
    elif any(word in message for word in ("long rest", "rest")):
        guide_facts.extend(checkpoint.irreversible_warnings)
        if not checkpoint.irreversible_warnings:
            unknowns.append("The guide does not mark a checkpoint-specific long-rest failure here.")
        suggestions.append("Confirm any active timed quest in the journal before resting.")
    else:
        guide_facts.extend([checkpoint.advice, *checkpoint.preparation[:3]])
        unknowns.append("Ask about readiness, danger, destination, preparation, or long rests for a narrower answer.")

    if request.screenshot_context:
        evidence = request.screenshot_context.strip()[:500]
        if evidence:
            suggestions.append("Latest optional screenshot evidence (not a guide fact): " + evidence)

    answer_parts = []
    if guide_facts:
        answer_parts.append("Guide says: " + " ".join(guide_facts))
    if suggestions:
        answer_parts.append("Assistant suggestion: " + " ".join(suggestions))
    if unknowns:
        answer_parts.append("Unknown: " + " ".join(unknowns))
    return ChatResponse(
        answer="\n\n".join(answer_parts),
        guide_facts=guide_facts,
        assistant_suggestions=suggestions,
        unknowns=unknowns,
    )
