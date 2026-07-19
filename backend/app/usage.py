from __future__ import annotations

import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

from .models import BuildImportQuota


class QuotaExhaustedError(Exception):
    pass


class IdempotencyConflictError(Exception):
    pass


class ImportAlreadyProcessingError(Exception):
    pass


@dataclass(frozen=True)
class ImportReservation:
    state: str
    execution_id: str | None = None
    response_json: str | None = None
    error_status: int | None = None
    error_detail: str | None = None


class UsageStore:
    def __init__(self, path: Path, lifetime_limit: int = 30, processing_lease_seconds: int = 600):
        if lifetime_limit < 1:
            raise ValueError("Build import lifetime limit must be positive.")
        if processing_lease_seconds < 1:
            raise ValueError("Build import processing lease must be positive.")
        self.path = path
        self.lifetime_limit = lifetime_limit
        self.processing_lease_seconds = processing_lease_seconds
        self._initialize_lock = threading.Lock()
        self._initialized = False

    def quota(self, subject_id: str) -> BuildImportQuota:
        with self._connect() as connection:
            used = connection.execute(
                "SELECT COUNT(*) FROM build_import_jobs WHERE subject_id = ? AND charged = 1",
                (subject_id,),
            ).fetchone()[0]
        return self._quota(used)

    def reserve(self, subject_id: str, idempotency_key: str, request_hash: str) -> ImportReservation:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                """
                SELECT request_hash, state, response_json, error_status, error_detail, updated_at
                FROM build_import_jobs
                WHERE subject_id = ? AND idempotency_key = ?
                """,
                (subject_id, idempotency_key),
            ).fetchone()
            if existing:
                if existing[0] != request_hash:
                    connection.rollback()
                    raise IdempotencyConflictError("The idempotency key was already used for another build URL.")
                if existing[1] == "processing":
                    now = int(time.time())
                    if now - existing[5] < self.processing_lease_seconds:
                        connection.rollback()
                        raise ImportAlreadyProcessingError("This build import is still processing.")
                    execution_id = str(uuid.uuid4())
                    connection.execute(
                        """
                        UPDATE build_import_jobs
                        SET execution_id = ?, updated_at = ?
                        WHERE subject_id = ? AND idempotency_key = ? AND state = 'processing'
                        """,
                        (execution_id, now, subject_id, idempotency_key),
                    )
                    connection.commit()
                    return ImportReservation(state="new", execution_id=execution_id)
                connection.commit()
                return ImportReservation(
                    state=existing[1],
                    response_json=existing[2],
                    error_status=existing[3],
                    error_detail=existing[4],
                )

            used = connection.execute(
                "SELECT COUNT(*) FROM build_import_jobs WHERE subject_id = ? AND charged = 1",
                (subject_id,),
            ).fetchone()[0]
            if used >= self.lifetime_limit:
                connection.rollback()
                raise QuotaExhaustedError(
                    f"The lifetime limit of {self.lifetime_limit} build-import attempts has been reached."
                )

            now = int(time.time())
            execution_id = str(uuid.uuid4())
            connection.execute(
                """
                INSERT INTO build_import_jobs (
                    subject_id, idempotency_key, request_hash, state, charged, execution_id,
                    created_at, updated_at
                ) VALUES (?, ?, ?, 'processing', 1, ?, ?, ?)
                """,
                (subject_id, idempotency_key, request_hash, execution_id, now, now),
            )
            connection.commit()
            return ImportReservation(state="new", execution_id=execution_id)

    def complete_success(
        self, subject_id: str, idempotency_key: str, execution_id: str, response_json: str
    ) -> None:
        self._complete(
            subject_id, idempotency_key, execution_id, "succeeded", response_json, None, None
        )

    def complete_failure(
        self, subject_id: str, idempotency_key: str, execution_id: str, status: int, detail: str
    ) -> None:
        self._complete(subject_id, idempotency_key, execution_id, "failed", None, status, detail)

    def _complete(
        self,
        subject_id: str,
        idempotency_key: str,
        execution_id: str,
        state: str,
        response_json: str | None,
        error_status: int | None,
        error_detail: str | None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE build_import_jobs
                SET state = ?, response_json = ?, error_status = ?, error_detail = ?, updated_at = ?
                WHERE subject_id = ? AND idempotency_key = ?
                  AND execution_id = ? AND state = 'processing'
                """,
                (
                    state,
                    response_json,
                    error_status,
                    error_detail,
                    int(time.time()),
                    subject_id,
                    idempotency_key,
                    execution_id,
                ),
            )

    def _connect(self) -> sqlite3.Connection:
        self._initialize()
        connection = sqlite3.connect(self.path, timeout=30)
        connection.execute("PRAGMA busy_timeout = 30000")
        return connection

    def _initialize(self) -> None:
        if self._initialized:
            return
        with self._initialize_lock:
            if self._initialized:
                return
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with sqlite3.connect(self.path) as connection:
                connection.execute("PRAGMA journal_mode = WAL")
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS build_import_jobs (
                        subject_id TEXT NOT NULL,
                        idempotency_key TEXT NOT NULL,
                        request_hash TEXT NOT NULL,
                        state TEXT NOT NULL CHECK (state IN ('processing', 'succeeded', 'failed')),
                        charged INTEGER NOT NULL CHECK (charged IN (0, 1)),
                        execution_id TEXT NOT NULL,
                        response_json TEXT,
                        error_status INTEGER,
                        error_detail TEXT,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        PRIMARY KEY (subject_id, idempotency_key)
                    )
                    """
                )
                connection.execute(
                    "CREATE INDEX IF NOT EXISTS build_import_usage ON build_import_jobs(subject_id, charged)"
                )
            self._initialized = True

    def _quota(self, used: int) -> BuildImportQuota:
        return BuildImportQuota(
            limit=self.lifetime_limit,
            used=used,
            remaining=max(0, self.lifetime_limit - used),
        )
