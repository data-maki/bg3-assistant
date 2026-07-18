"""Chat grounding must read builds from the catalog, imports included."""

from app import catalog
from app.chat_context import resolve_chat_context
from app.loadout_import import _normalize
from app.models import ChatContextSnapshot, ChatRequest, PartyMember
from app.route_data import load_route
from app.walkthrough_data import walkthrough_by_id
from conftest import sample_draft


def test_member_with_imported_build_gets_chat_grounding(db_path, monkeypatch):
    monkeypatch.setattr(catalog, "_enrich", lambda name: {})
    imported = _normalize(sample_draft(), "https://example.com/build")
    catalog.save_imported_build(imported)
    assert imported.build.id.startswith("import-")

    checkpoint = load_route()[0]
    member = PartyMember(id="tav", name="Tav", level=4, build_id=imported.build.id, status="active")
    request = ChatRequest(message="what should I do next?", checkpoint_id=checkpoint.id, party=[member])
    context = resolve_chat_context(checkpoint, request)

    assert "Swords Bard" in context.build_actions[member.id]
    assert [gear.item for gear in context.relevant_gear[member.id]] == ["Titanstring Bow"]
    lines = context.grounding_lines(checkpoint)
    assert any(line.startswith("[Reviewed build] Tav:") for line in lines)


def test_act_three_chat_context_uses_only_act_three_steps():
    checkpoint = load_route(3)[0]
    request = ChatRequest(
        message="what should I do next?",
        checkpoint_id=checkpoint.id,
        context=ChatContextSnapshot(selected_act=3),
    )

    context = resolve_chat_context(checkpoint, request)

    assert context.selected_act == 3
    assert context.recommended is not None
    assert context.recommended.id.startswith("walk-act3-")


def test_requested_step_wins_over_stale_completed_focus():
    checkpoint = load_route(3)[0]
    request = ChatRequest(
        message="what should I do next?",
        checkpoint_id=checkpoint.id,
        walkthrough_step_id="walk-act3-coronation",
        context=ChatContextSnapshot(
            selected_act=3,
            focused_step_id="walk-act3-minsc",
            walkthrough_statuses={"walk-act3-minsc": "completed"},
        ),
    )

    context = resolve_chat_context(checkpoint, request, requested_step=walkthrough_by_id("walk-act3-coronation", 3))

    assert context.focused is None
    assert context.current is not None
    assert context.current.id == "walk-act3-coronation"
