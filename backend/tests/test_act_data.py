import pytest
from fastapi.testclient import TestClient

from app.guide_chat import guide_facts
from app.main import app
from app.models import PartyMember, ReadinessRequest
from app.route_data import assess_readiness, checkpoint_by_id, item_key, load_gear
from app.walkthrough_data import walkthrough_by_id


client = TestClient(app)


def test_act_catalog_uses_separate_equipment_databases():
    response = client.get("/api/acts/1/guide")
    assert response.status_code == 200
    acts = response.json()["acts"]
    assert [entry["equipment_file"] for entry in acts] == [
        "gear/act1.tsv",
        "gear/act2.tsv",
        "gear/act3.tsv",
    ]
    # Counts are distinct catalog items per act (the same item listed for
    # several builds is one row), not raw TSV rows.
    expected = [
        len({item_key(item.item) for item in load_gear(act)})
        for act in (1, 2, 3)
    ]
    assert [entry["equipment_count"] for entry in acts] == expected
    assert acts[0]["route_available"] is True
    assert acts[1]["route_available"] is False


def test_act_two_equipment_is_isolated_and_coordinate_backed():
    act_two = load_gear(2)
    assert act_two
    assert {item.act for item in act_two} == {2}
    assert all(item.game_x is not None and item.game_y is not None for item in act_two if item.map_objective)
    helmet = next(item for item in act_two if item.item == "Helmet of Arcane Acuity")
    assert (helmet.game_x, helmet.game_y) == (107, -758)


def test_unknown_act_is_not_exposed():
    assert client.get("/api/acts/4/guide").status_code == 404


def test_act_guides_are_isolated_and_act_three_is_app_ready():
    act_one = client.get("/api/acts/1/guide")
    act_two = client.get("/api/acts/2/guide")
    act_three = client.get("/api/acts/3/guide")

    assert act_one.status_code == 200
    assert act_two.status_code == 200
    assert act_two.json()["act"] == 2
    assert act_two.json()["routeAvailable"] is False
    assert act_two.json()["checkpoints"] == []
    assert act_two.json()["walkthrough"] == []

    payload = act_three.json()
    assert act_three.status_code == 200
    assert payload["act"] == 3
    assert payload["routeAvailable"] is True
    assert len(payload["checkpoints"]) == 13
    assert len(payload["walkthrough"]) == 19
    assert len(payload["timedEvents"]) == 9
    assert payload["checkpoints"][0]["x"] is None
    assert payload["checkpoints"][0]["y"] is None
    assert payload["checkpoints"][0]["source"]["row"] is None

    act_one_ids = {item["id"] for item in act_one.json()["checkpoints"]}
    act_three_ids = {item["id"] for item in payload["checkpoints"]}
    assert act_one_ids.isdisjoint(act_three_ids)
    act_one_steps = {item["id"] for item in act_one.json()["walkthrough"]}
    act_three_steps = {item["id"] for item in payload["walkthrough"]}
    assert act_one_steps.isdisjoint(act_three_steps)


def test_act_three_readiness_is_scoped_to_act_three():
    request = ReadinessRequest(checkpoint_id="act3-coronation", party=[])

    assessment = assess_readiness(request, 3)
    assert assessment.minimum_level == 10
    assert any("No active party" in blocker for blocker in assessment.blockers)
    assert not any("Lowest party member" in blocker for blocker in assessment.blockers)
    with pytest.raises(KeyError):
        assess_readiness(request, 1)


def test_readiness_uses_active_party_walkthrough_state_and_checked_preparation():
    checkpoint = checkpoint_by_id("act3-coronation", 3)
    statuses = {
        "walk-act3-rivington": "completed",
        "walk-act3-open-hand": "completed",
    }
    request = ReadinessRequest(
        checkpoint_id=checkpoint.id,
        party=[
            PartyMember(id="tav", name="Tav", level=10, status="active"),
            PartyMember(id="gale", name="Gale", level=1, status="camp"),
        ],
        checked_preparation=checkpoint.preparation,
        walkthrough_statuses=statuses,
    )

    assessment = assess_readiness(request, 3)

    assert assessment.party_level == 10
    assert not any("Lowest party member" in blocker for blocker in assessment.blockers)
    assert not any("Preparation not confirmed" in warning for warning in assessment.warnings)


def test_readiness_blocks_skipped_required_route_prerequisite():
    request = ReadinessRequest(
        checkpoint_id="act3-orin",
        party=[PartyMember(id="tav", name="Tav", level=12, status="active")],
        skipped_checkpoint_ids=["act3-sarevok"],
        walkthrough_statuses={"walk-act3-sarevok": "skipped"},
    )

    assessment = assess_readiness(request, 3)

    assert any("Unresolved reviewed route sequence" in blocker for blocker in assessment.blockers)
    assert any("Revisit" in blocker for blocker in assessment.blockers)


def test_chat_accepts_reviewed_walkthrough_step_without_checkpoint():
    response = client.post("/api/chat", json={
        "message": "Where should I go next?",
        "walkthrough_step_id": "walk-act3-rivington",
        "context": {"selected_act": 3},
    })

    assert response.status_code == 200
    assert "Stabilize Rivington" in response.json()["answer"]


def test_chat_rejects_mismatched_step_and_checkpoint():
    response = client.post("/api/chat", json={
        "message": "What next?",
        "checkpoint_id": "act3-coronation",
        "walkthrough_step_id": "walk-act3-minsc",
        "context": {"selected_act": 3},
    })

    assert response.status_code == 422


def test_checkpointless_incident_is_in_chat_grounding():
    facts = guide_facts(None, walkthrough_by_id("walk-act3-urgent-city", 3))

    assert any(fact.startswith("Trigger:") for fact in facts)
    assert any(fact.startswith("Safe actions:") for fact in facts)
    assert any(fact.startswith("Escape:") for fact in facts)
