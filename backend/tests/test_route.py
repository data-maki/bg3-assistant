from fastapi.testclient import TestClient

from app.main import app
from app.route_data import next_checkpoint


client = TestClient(app)


def test_manual_completion_advances_to_next_route_checkpoint() -> None:
    assert next_checkpoint(set()).id == "fight-nautiloid-zhalk"
    assert next_checkpoint({"fight-nautiloid-zhalk"}).id == "fight-grove-entrance"


def test_level_aware_route_stays_on_surface_before_underdark() -> None:
    completed = {"fight-nautiloid-zhalk", "fight-grove-entrance", "fight-blighted-village"}
    assert next_checkpoint(completed, party_level=5).id == "fight-gnolls"
    surface_except_patrol = {
        *completed,
        "fight-harpies",
        "fight-owlbear",
        "fight-spider-matriarch",
        "fight-redcaps",
        "fight-wood-woads",
        "fight-auntie-ethel",
        "fight-gnolls",
        "fight-goblin-leaders",
    }
    assert next_checkpoint(surface_except_patrol, party_level=6).id == "fight-gith-patrol"


def test_skipped_prerequisite_is_resolved_for_route_selection() -> None:
    assert next_checkpoint(
        {"fight-nautiloid-zhalk"}, skipped={"fight-grove-entrance"}, party_level=4
    ).region != "Underdark"


def test_route_contains_all_reviewed_act_one_checkpoints() -> None:
    response = client.get("/api/act1/route")
    assert response.status_code == 200
    payload = response.json()
    checkpoints = payload["checkpoints"]
    assert len(checkpoints) == 19
    assert [item["route_order"] for item in checkpoints] == list(range(1, 20))
    assert all(item["preparation"] for item in checkpoints)
    assert all(item["failure_conditions"] for item in checkpoints)
    assert all(item["completion_checks"] for item in checkpoints)
    assert all(isinstance(item["minimum_level"], int) and item["minimum_level"] >= 1 for item in checkpoints)
    assert all(isinstance(item["x"], int) and isinstance(item["y"], int) and item["region"] for item in checkpoints)
    assert sum(bool(item["honor_decisions"]) for item in checkpoints) >= 10
    assert {build["id"] for build in payload["builds"]} >= {"PA-FL", "WI-BS"}
    assert all(len(build["levels"]) >= 6 for build in payload["builds"])
    assert all(build["gear"] for build in payload["builds"])
    assert all(build["source"].startswith("http") and build["play_pattern"] for build in payload["builds"])
    flamadin = next(build for build in payload["builds"] if build["id"] == "PA-FL")
    assert flamadin["levels"][0]["take"]
    assert {item["act"] for item in flamadin["gear"]} == {1, 2}
    assert all(item["acquisition"] for item in flamadin["gear"])


def test_readiness_blocks_an_underleveled_party() -> None:
    response = client.post(
        "/api/act1/readiness",
        json={
            "checkpoint_id": "fight-grym",
            "party": [{"id": "tav", "name": "Tav", "level": 5, "prepared_tags": []}],
            "completed_checkpoint_ids": ["fight-nere"],
            "checked_preparation": [],
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "blocked"
    assert payload["minimum_level"] == 6
    assert "level 5" in payload["blockers"][0]


def test_build_assignment_adds_level_specific_guidance() -> None:
    response = client.post(
        "/api/act1/readiness",
        json={
            "checkpoint_id": "fight-blighted-village",
            "party": [{"id": "tav", "name": "Tav", "level": 3, "build_id": "PA-FL", "prepared_tags": []}],
            "completed_checkpoint_ids": ["fight-nautiloid-zhalk", "fight-grove-entrance", "fight-harpies"],
            "checked_preparation": [],
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert any("Flamadin" in action and "Tav L3" in action for action in payload["next_actions"])


def test_build_assignment_counts_reviewed_setup_as_capabilities() -> None:
    response = client.post(
        "/api/act1/readiness",
        json={
            "checkpoint_id": "fight-spider-matriarch",
            "party": [{"id": "tav", "name": "Tav", "level": 5, "build_id": "PA-FL", "prepared_tags": []}],
            "completed_checkpoint_ids": ["fight-nautiloid-zhalk", "fight-grove-entrance", "fight-blighted-village"],
            "checked_preparation": [],
        },
    )
    assert not any("fire" in warning.lower() and "capability" in warning.lower() for warning in response.json()["warnings"])


def test_recorded_party_capability_affects_readiness_warning() -> None:
    base = {
        "checkpoint_id": "fight-harpies",
        "completed_checkpoint_ids": ["fight-nautiloid-zhalk", "fight-grove-entrance"],
        "checked_preparation": [],
    }
    missing = client.post(
        "/api/act1/readiness",
        json={**base, "party": [{"id": "tav", "name": "Tav", "level": 3, "prepared_tags": []}]},
    ).json()
    prepared = client.post(
        "/api/act1/readiness",
        json={**base, "party": [{"id": "tav", "name": "Tav", "level": 3, "prepared_tags": ["Silence", "Sanctuary"]}]},
    ).json()
    assert any("silence" in warning for warning in missing["warnings"])
    assert not any("silence" in warning for warning in prepared["warnings"])


def test_irreversible_checkpoint_uses_danger_state() -> None:
    response = client.post(
        "/api/act1/readiness",
        json={
            "checkpoint_id": "fight-nere",
            "party": [{"id": "tav", "name": "Tav", "level": 6, "prepared_tags": []}],
            "completed_checkpoint_ids": ["fight-underdark-minotaurs", "fight-spectator", "fight-arcane-tower", "fight-sussur-hook-horrors"],
            "checked_preparation": [],
        },
    )
    assert response.json()["status"] == "danger"


def test_chat_separates_guide_facts_and_suggestions() -> None:
    response = client.post(
        "/api/chat",
        json={
            "message": "What can end my run here?",
            "checkpoint_id": "fight-nere",
            "party": [],
            "completed_checkpoint_ids": [],
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["guide_facts"]
    assert payload["assistant_suggestions"]
    assert "Guide says:" in payload["answer"]


def test_chat_labels_optional_screenshot_as_suggestion() -> None:
    response = client.post(
        "/api/chat",
        json={
            "message": "What is next?",
            "checkpoint_id": "fight-grove-entrance",
            "party": [],
            "completed_checkpoint_ids": ["fight-nautiloid-zhalk"],
            "screenshot_context": "Dialogue visible with three goblins.",
        },
    )
    payload = response.json()
    assert any("not a guide fact" in item for item in payload["assistant_suggestions"])
    assert all("Dialogue visible" not in item for item in payload["guide_facts"])


def test_chat_answers_current_build_level_choice() -> None:
    response = client.post(
        "/api/chat",
        json={
            "message": "What do I take at this level?",
            "checkpoint_id": "fight-blighted-village",
            "party": [{"id": "tav", "name": "Tav", "level": 3, "build_id": "PA-FL", "prepared_tags": []}],
            "completed_checkpoint_ids": ["fight-nautiloid-zhalk", "fight-grove-entrance", "fight-harpies"],
        },
    )
    assert any("Tav L3" in item and "Flamadin" in item for item in response.json()["assistant_suggestions"])


def test_chat_answers_key_honor_dialogue_decisions() -> None:
    response = client.post(
        "/api/chat",
        json={
            "message": "Which dialogue choices should I make?",
            "checkpoint_id": "fight-blighted-village",
            "party": [],
            "completed_checkpoint_ids": ["fight-nautiloid-zhalk", "fight-grove-entrance"],
        },
    )
    facts = response.json()["guide_facts"]
    assert any("BRAKE lever" in item for item in facts)
    assert any("Disguise Self: Drow" in item for item in facts)
