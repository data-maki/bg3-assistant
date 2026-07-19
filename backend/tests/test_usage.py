import threading
import uuid

import pytest

from app.usage import (
    IdempotencyConflictError,
    QuotaExhaustedError,
    UsageStore,
)


def test_lifetime_quota_admits_thirty_unique_import_attempts(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3", lifetime_limit=30)

    for index in range(30):
        key = str(uuid.uuid4())
        reservation = store.reserve("subject", key, f"hash-{index}")
        assert reservation.state == "new"
        store.complete_failure("subject", key, reservation.execution_id, 422, "invalid build")

    assert store.quota("subject").used == 30
    with pytest.raises(QuotaExhaustedError, match="30"):
        store.reserve("subject", str(uuid.uuid4()), "hash-31")


def test_idempotency_replays_response_without_another_charge(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3", lifetime_limit=30)
    key = str(uuid.uuid4())
    reservation = store.reserve("subject", key, "same-hash")
    store.complete_success("subject", key, reservation.execution_id, '{"id":"cached"}')

    replay = store.reserve("subject", key, "same-hash")

    assert replay.state == "succeeded"
    assert replay.response_json == '{"id":"cached"}'
    assert store.quota("subject").used == 1
    with pytest.raises(IdempotencyConflictError):
        store.reserve("subject", key, "different-hash")


def test_concurrent_requests_compete_atomically_for_final_slot(tmp_path):
    store = UsageStore(tmp_path / "usage.sqlite3", lifetime_limit=30)
    for index in range(29):
        key = str(uuid.uuid4())
        reservation = store.reserve("subject", key, f"hash-{index}")
        store.complete_success("subject", key, reservation.execution_id, "{}")

    barrier = threading.Barrier(2)
    outcomes = []

    def reserve_final_slot(index: int):
        barrier.wait()
        try:
            store.reserve("subject", str(uuid.uuid4()), f"contender-{index}")
            outcomes.append("admitted")
        except QuotaExhaustedError:
            outcomes.append("rejected")

    threads = [threading.Thread(target=reserve_final_slot, args=(index,)) for index in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert sorted(outcomes) == ["admitted", "rejected"]
    assert store.quota("subject").used == 30


def test_expired_processing_lease_retries_without_another_charge(tmp_path, monkeypatch):
    store = UsageStore(tmp_path / "usage.sqlite3", lifetime_limit=30, processing_lease_seconds=10)
    key = str(uuid.uuid4())
    monkeypatch.setattr("app.usage.time.time", lambda: 100)
    first = store.reserve("subject", key, "same-hash")
    monkeypatch.setattr("app.usage.time.time", lambda: 111)

    retry = store.reserve("subject", key, "same-hash")
    store.complete_success("subject", key, first.execution_id, '{"id":"late"}')
    store.complete_success("subject", key, retry.execution_id, '{"id":"current"}')
    replay = store.reserve("subject", key, "same-hash")

    assert first.execution_id != retry.execution_id
    assert replay.response_json == '{"id":"current"}'
    assert store.quota("subject").used == 1
