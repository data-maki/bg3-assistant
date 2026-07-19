import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models import PartyMember, ReadinessRequest
from app.route_data import assess_readiness, checkpoint_by_id


client = TestClient(app)


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
    # App-ready means a populated guide with unique ids, not any exact count;
    # content edits must not break this test.
    assert payload["checkpoints"] and payload["walkthrough"] and payload["timedEvents"]
    assert len({item["id"] for item in payload["checkpoints"]}) == len(payload["checkpoints"])
    assert len({item["id"] for item in payload["walkthrough"]}) == len(payload["walkthrough"])
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
