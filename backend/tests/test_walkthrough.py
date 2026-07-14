from fastapi.testclient import TestClient

from app.main import app
from app.route_data import load_route
from app.walkthrough_data import load_walkthrough, recommend_walkthrough_step, validate_walkthrough, walkthrough_blockers


client = TestClient(app)


def test_walkthrough_is_complete_and_ordered() -> None:
    steps = load_walkthrough()
    assert len(steps) == 59
    assert [step.order for step in steps] == list(range(1, 60))
    assert len({step.id for step in steps}) == len(steps)
    assert len({step.phase for step in steps}) >= 8
    assert all(step.completion_checks for step in steps)
    assert all(step.source_label and step.source_url.startswith("https://") for step in steps)
    validate_walkthrough(steps)
    assert all(len(step.dependencies) == len(step.prerequisites) for step in steps)
    assert all(dependency.reason for step in steps for dependency in step.dependencies)


def test_kagha_requires_confirmed_swamp_evidence() -> None:
    steps = load_walkthrough()
    by_id = {step.id: step for step in steps}
    expose = by_id["walk-expose-kagha"]
    dependency = expose.dependencies[0]
    assert dependency.step_id == "walk-wood-woads"
    assert dependency.kind == "completion_required"

    preceding = {step.id: "done" for step in steps if step.order < expose.order and step.id != "walk-wood-woads"}
    assert walkthrough_blockers(expose, steps, preceding) == [dependency.reason]
    assert recommend_walkthrough_step(steps, preceding, party_level=4) != expose

    skipped = {**preceding, "walk-wood-woads": "skipped"}
    blockers = walkthrough_blockers(expose, steps, skipped)
    assert blockers == [f"Revisit Get Kagha's evidence from the sanctuary — {dependency.reason}"]
    assert recommend_walkthrough_step(steps, skipped, party_level=4) != expose

    completed = {**preceding, "walk-wood-woads": "done"}
    assert walkthrough_blockers(expose, steps, completed) == []
    assert recommend_walkthrough_step(steps, completed, party_level=4) == expose


def test_focus_does_not_change_automatic_route_eligibility() -> None:
    steps = load_walkthrough()
    expose = next(step for step in steps if step.id == "walk-expose-kagha")
    statuses = {step.id: "done" for step in steps if step.order < expose.order and step.id != "walk-wood-woads"}
    recommendation = recommend_walkthrough_step(steps, statuses, party_level=4)
    assert recommendation is None or recommendation.id != expose.id
    assert walkthrough_blockers(expose, steps, statuses)


def test_every_fight_checkpoint_is_linked_from_the_walkthrough() -> None:
    linked = {step.checkpoint_id for step in load_walkthrough() if step.checkpoint_id}
    assert linked == {checkpoint.id for checkpoint in load_route()}


def test_decisions_expose_real_tradeoffs() -> None:
    decisions = [step.decision for step in load_walkthrough() if step.decision]
    assert len(decisions) >= 15
    assert all(decision.recommended.benefits for decision in decisions)
    assert all(decision.alternatives for decision in decisions)
    assert all(
        option.costs
        for decision in decisions
        for option in [decision.recommended, *decision.alternatives]
        if option.label != "BRAKE"
    )


def test_dialogues_and_incident_protocols_are_first_class_steps() -> None:
    steps = load_walkthrough()
    dialogues = [step for step in steps if step.kind in {"dialogue", "decision"}]
    incidents = [step.incident for step in steps if step.incident]
    assert len(dialogues) >= 13
    assert {step.id for step in dialogues}.issuperset({"walk-philomeen", "walk-zaithisk", "walk-vlaakith-audience"})
    assert len(incidents) >= 13
    assert all(item.safe_actions and item.never and item.escape and item.source_url for item in incidents)
    vlaakith = next(step for step in dialogues if step.id == "walk-vlaakith-audience")
    assert "instant" in vlaakith.incident.honor_delta.lower()
    assert vlaakith.decision.reversible is False


def test_optional_bosses_explain_risk_and_reward() -> None:
    optional = [step for step in load_walkthrough() if step.importance == "optional" and step.risk_reward]
    assert {step.id for step in optional}.issuperset({"walk-owlbear", "walk-wargaz"})
    assert all(step.risk_reward.reward and step.risk_reward.risk and step.risk_reward.skip_cost for step in optional)


def test_act_one_power_rewards_are_separate_confirmable_steps() -> None:
    by_id = {step.id: step for step in load_walkthrough()}
    expected = {
        "walk-shovel-quasit": "Find Familiar: Cheeky Quasit once per Short Rest",
        "walk-necromancy-thay": "Forbidden Knowledge: +1 Wisdom saves and checks",
        "walk-mourning-frost": "Mourning Frost",
        "walk-sussur-weapon": "Sussur Dagger",
        "walk-blood-of-lathander": "The Blood of Lathander",
    }
    assert expected.keys() <= by_id.keys()
    for step_id, reward in expected.items():
        assert reward in by_id[step_id].rewards
        assert by_id[step_id].completion_checks
        assert by_id[step_id].marker_id

    assert by_id["walk-necromancy-thay"].prerequisites == [
        "walk-apothecary-cellar",
        "walk-spider-matriarch",
    ]
    assert by_id["walk-mourning-frost"].prerequisites == [
        "walk-spectator",
        "walk-hook-horrors",
        "walk-duergar-glut",
    ]
    assert by_id["walk-sussur-weapon"].prerequisites == ["walk-hook-horrors"]


def test_map_payload_includes_camel_case_walkthrough() -> None:
    response = client.get("/api/act1/markers")
    assert response.status_code == 200
    payload = response.json()
    assert len(payload["walkthrough"]) == 59
    first = payload["walkthrough"][0]
    assert first["phaseOrder"] == 0
    assert first["checkpointId"] == "fight-nautiloid-zhalk"
    assert first["decision"]["recommended"]["benefits"]


def test_run_state_normalizes_walkthrough_statuses() -> None:
    response = client.post(
        "/api/run-state",
        json={
            "walkthroughStatuses": {
                "walk-harpies": "done",
                "walk-owlbear": "skipped",
                "walk-ethel": "revisit",
                "walk-invalid": "auto-complete",
            }
        },
    )
    assert response.status_code == 200
    assert response.json()["walkthroughStatuses"] == {
        "walk-harpies": "done",
        "walk-owlbear": "skipped",
        "walk-ethel": "revisit",
    }
