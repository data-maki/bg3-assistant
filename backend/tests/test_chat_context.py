from app import guide_chat
from app.chat_context import resolve_chat_context
from app.models import ChatContextSnapshot, ChatRequest, PartyMember
from app.route_data import checkpoint_by_id
from app.walkthrough_data import load_walkthrough, walkthrough_by_id


def _statuses_before(step_id: str) -> dict[str, str]:
    target = walkthrough_by_id(step_id)
    return {step.id: "done" for step in load_walkthrough() if step.order < target.order}


def _member(member_id: str, name: str, level: int, status: str, build_id: str | None = None) -> PartyMember:
    return PartyMember(id=member_id, name=name, level=level, status=status, build_id=build_id)


def _request(message: str, context: ChatContextSnapshot) -> ChatRequest:
    return ChatRequest(
        message=message,
        checkpoint_id="fight-grove-entrance",
        walkthrough_step_id=context.focused_step_id,
        context=context,
    )


def test_focused_kagha_chat_names_swamp_evidence_and_safe_recommendation() -> None:
    statuses = _statuses_before("walk-wood-woads")
    context = ChatContextSnapshot(
        focused_step_id="walk-expose-kagha",
        recommended_step_id="walk-expose-kagha",  # ignored: the backend recomputes it
        walkthrough_statuses=statuses,
        roster=[_member("tav", "Tav", 4, "active")],
    )

    answer = guide_chat.answer(
        checkpoint_by_id("fight-grove-entrance"),
        _request("Can I expose Kagha now?", context),
        walkthrough_by_id("walk-expose-kagha"),
    )

    assert answer.answer.startswith("Action: Do Get Kagha's evidence from the sanctuary first")
    assert "mud mephit and wood woad" in answer.answer
    assert "Expose Kagha" in answer.answer


def test_active_build_actions_exclude_camp_and_dead_roster() -> None:
    context = ChatContextSnapshot(
        scope="party",
        walkthrough_statuses={},
        roster=[
            _member("tav", "Tav", 4, "active", "PA-FL"),
            _member("laezel", "Lae'zel", 4, "active", "MO-OH"),
            _member("wyll", "Wyll", 4, "active", "FI-WEK"),
            _member("shadowheart", "Shadowheart", 4, "active", "CL-LI"),
            _member("gale", "Gale", 6, "camp", "WI-BS"),
            _member("karlach", "Karlach", 6, "dead", "MO-OH"),
        ],
        story_outcomes=["Karlach killed for Mizora/Wyll path"],
    )

    answer = guide_chat.answer(
        checkpoint_by_id("fight-grove-entrance"),
        _request("What should Lae'zel take at this level and does camp affect readiness?", context),
    )

    assert any("Lae'zel" in item and "Open Hand Monk" in item for item in answer.assistant_suggestions)
    assert any("Wyll" in item and "Warlock–Eldritch Knight" in item for item in answer.assistant_suggestions)
    assert not any("Gale L6" in item or "Karlach L6" in item for item in answer.assistant_suggestions)
    assert "Gale (camp)" in answer.answer and "Karlach (dead)" in answer.answer
    assert "Karlach killed for Mizora/Wyll path" in answer.answer


def test_conflicting_unique_equipment_is_unknown_until_one_owner_is_confirmed() -> None:
    context = ChatContextSnapshot(
        scope="loadout",
        roster=[
            _member("tav", "Tav", 4, "active", "PA-FL"),
            _member("laezel", "Lae'zel", 4, "active", "MO-OH"),
        ],
        equipment_ownership_known=True,
        equipped_by_member={"tav": ["ring-of-protection"], "laezel": ["ring-of-protection"]},
    )
    answer = guide_chat.answer(checkpoint_by_id("fight-grove-entrance"), _request("What gear should we get?", context))
    assert any("Conflicting unique equipment 'ring-of-protection'" in item for item in answer.unknowns)


def test_missing_equipment_ownership_and_screenshot_remain_unknown_not_guide_fact() -> None:
    context = ChatContextSnapshot(
        roster=[_member("laezel", "Lae'zel", 4, "active", "MO-OH")],
        equipment_ownership_known=False,
    )
    request = _request("What equipment do I still need?", context)
    answer = guide_chat.answer(checkpoint_by_id("fight-grove-entrance"), request)
    assert any("ownership has not been confirmed" in item for item in answer.unknowns)
    assert all("ownership" not in item.lower() for item in answer.guide_facts)
    assert "Action:" in answer.answer and "DON'T DIE:" in answer.answer and "Unknown:" in answer.answer


def test_screenshot_note_is_timestamped_non_authoritative_evidence() -> None:
    context = ChatContextSnapshot(roster=[_member("tav", "Tav", 3, "active")])
    request = _request("What's next?", context).model_copy(
        update={"screenshot_context": "Dialogue visible.", "screenshot_timestamp": 1234.0}
    )
    answer = guide_chat.answer(checkpoint_by_id("fight-grove-entrance"), request)
    assert any("1234" in item and "not a guide fact" in item for item in answer.assistant_suggestions)
    assert all("Dialogue visible" not in item for item in answer.guide_facts)


def test_visual_memory_is_grounded_as_unconfirmed_assistant_evidence() -> None:
    context = ChatContextSnapshot(
        roster=[_member("tav", "Tav", 4, "active")],
        visual_memory_summary="Quest completion banner after the harpy fight.",
        visual_memory_timestamp=1234.0,
        visual_memory_completion_step_ids=["walk-harpies"],
    )
    request = _request("What did I likely finish?", context)
    resolved = resolve_chat_context(checkpoint_by_id("fight-grove-entrance"), request)
    lines = resolved.grounding_lines(checkpoint_by_id("fight-grove-entrance"))

    assert any("[Vision memory]" in line and "progress unchanged" in line for line in lines)
    assert any("walk-harpies" in line and "player confirmation required" in line for line in lines)
