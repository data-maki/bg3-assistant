import httpx
from dataclasses import dataclass

from .models import (
    BuildImportQuota,
    ChatRequest,
    ChatResponse,
    HostedAuthResponse,
    ImportedBuild,
    LoadoutImportRequest,
)


class UpstreamBackendError(Exception):
    def __init__(
        self,
        status_code: int,
        detail: str,
        quota: BuildImportQuota | None = None,
    ):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail
        self.quota = quota


@dataclass(frozen=True)
class UpstreamImportResult:
    imported: ImportedBuild
    quota: BuildImportQuota | None


def authenticate(base_url: str, signed_app_transaction: str) -> HostedAuthResponse:
    response = _post(
        base_url,
        "/v1/auth/app-transaction",
        {"signedAppTransaction": signed_app_transaction},
        timeout=30,
    )
    try:
        return HostedAuthResponse.model_validate(response.json())
    except ValueError as exc:
        raise UpstreamBackendError(502, "The hosted backend returned an invalid authentication response.") from exc


def chat(base_url: str, request: ChatRequest, access_token: str) -> ChatResponse:
    payload = request.model_dump(mode="json")
    response = _post(
        base_url,
        "/v1/chat",
        payload,
        timeout=90,
        headers={"Authorization": f"Bearer {access_token}"},
    )
    try:
        return ChatResponse.model_validate(response.json())
    except ValueError as exc:
        raise UpstreamBackendError(502, "The hosted AI backend returned an invalid response.") from exc


def import_build(
    base_url: str,
    request: LoadoutImportRequest,
    access_token: str,
    idempotency_key: str,
) -> UpstreamImportResult:
    payload = request.model_dump(mode="json")
    payload["persist"] = False
    response = _post(
        base_url,
        "/v1/builds/import",
        payload,
        timeout=180,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Idempotency-Key": idempotency_key,
        },
    )
    try:
        imported = ImportedBuild.model_validate(response.json())
    except ValueError as exc:
        raise UpstreamBackendError(502, "The hosted AI backend returned an invalid response.") from exc
    return UpstreamImportResult(imported=imported, quota=_quota_from_headers(response))


def _post(
    base_url: str,
    path: str,
    payload: dict,
    timeout: float,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    try:
        response = httpx.post(
            f"{base_url.rstrip('/')}{path}",
            json=payload,
            headers=headers,
            timeout=timeout,
            follow_redirects=False,
        )
    except httpx.HTTPError as exc:
        raise UpstreamBackendError(502, "The hosted AI backend is unavailable.") from exc
    if response.is_success:
        return response
    try:
        detail = response.json().get("detail", "The hosted AI backend rejected the request.")
    except (AttributeError, ValueError):
        detail = "The hosted AI backend rejected the request."
    status = response.status_code if 400 <= response.status_code < 500 else 502
    raise UpstreamBackendError(status, str(detail), quota=_quota_from_headers(response))


def _quota_from_headers(response: httpx.Response) -> BuildImportQuota | None:
    try:
        return BuildImportQuota(
            limit=int(response.headers["X-Quota-Limit"]),
            used=int(response.headers["X-Quota-Used"]),
            remaining=int(response.headers["X-Quota-Remaining"]),
        )
    except (KeyError, ValueError):
        return None
