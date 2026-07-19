from __future__ import annotations

import base64
import hashlib
import hmac
import threading
import time
import uuid
from dataclasses import dataclass
from functools import lru_cache

import jwt
from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.signed_data_verifier import (
    SignedDataVerifier,
    VerificationException,
    VerificationStatus,
)

from .config import Settings, get_settings
from .models import BuildImportQuota, CompanionAuthResponse, HostedAuthResponse
from .usage import UsageStore


class InvalidAppTransactionError(Exception):
    pass


class AppTransactionTemporarilyUnavailableError(Exception):
    pass


class HostedAuthenticationError(Exception):
    pass


class AppleAppTransactionVerifier:
    def __init__(self, settings: Settings):
        roots = [path.read_bytes() for path in sorted(settings.apple_root_ca_dir.glob("*.cer"))]
        if not roots:
            raise ValueError(f"No Apple root certificates found in {settings.apple_root_ca_dir}.")
        environment = (
            Environment.SANDBOX
            if settings.appstore_environment == "Sandbox"
            else Environment.PRODUCTION
        )
        if environment == Environment.PRODUCTION and settings.appstore_apple_id is None:
            raise ValueError("BG3_APPSTORE_APPLE_ID is required for Production verification.")
        self.environment_name = settings.appstore_environment
        self.verifier = SignedDataVerifier(
            roots,
            settings.apple_online_checks,
            environment,
            settings.appstore_bundle_id,
            settings.appstore_apple_id if environment == Environment.PRODUCTION else None,
        )

    def verify(self, signed_app_transaction: str) -> str:
        try:
            payload = self.verifier.verify_and_decode_app_transaction(signed_app_transaction)
        except VerificationException as exc:
            if exc.status == VerificationStatus.RETRYABLE_VERIFICATION_FAILURE:
                raise AppTransactionTemporarilyUnavailableError(
                    "Apple transaction verification is temporarily unavailable."
                ) from exc
            raise InvalidAppTransactionError("Apple rejected the app transaction.") from exc
        if not payload.appTransactionId:
            raise InvalidAppTransactionError("The verified app transaction has no user identifier.")
        return payload.appTransactionId


class HostedAuthService:
    issuer = "bg3-assistant"
    audience = "bg3-hosted-api"

    def __init__(
        self,
        settings: Settings,
        usage_store: UsageStore,
        app_transaction_verifier: AppleAppTransactionVerifier | None = None,
    ):
        if settings.backend_mode != "hosted":
            raise ValueError("AppTransaction verification requires BG3_BACKEND_MODE=hosted.")
        if settings.upstream_backend_url:
            raise ValueError("A hosted backend cannot configure BG3_UPSTREAM_BACKEND_URL.")
        if not settings.openrouter_api_key:
            raise ValueError("OPENROUTER_API_KEY is required by the hosted backend.")
        if len(settings.auth_token_secret.encode()) < 32:
            raise ValueError("BG3_AUTH_TOKEN_SECRET must contain at least 32 bytes.")
        if len(settings.subject_hmac_secret.encode()) < 32:
            raise ValueError("BG3_SUBJECT_HMAC_SECRET must contain at least 32 bytes.")
        if settings.auth_token_ttl_seconds < 300:
            raise ValueError("BG3_AUTH_TOKEN_TTL_SECONDS must be at least 300.")
        self.settings = settings
        self.usage_store = usage_store
        self.app_transaction_verifier = app_transaction_verifier or AppleAppTransactionVerifier(settings)

    def exchange(self, signed_app_transaction: str) -> HostedAuthResponse:
        app_transaction_id = self.app_transaction_verifier.verify(signed_app_transaction)
        subject_id = self._subject_id(app_transaction_id)
        now = int(time.time())
        expires_at = now + self.settings.auth_token_ttl_seconds
        access_token = jwt.encode(
            {
                "iss": self.issuer,
                "aud": self.audience,
                "sub": subject_id,
                "scope": ["chat", "build-import"],
                "env": self.settings.appstore_environment,
                "bid": self.settings.appstore_bundle_id,
                "iat": now,
                "exp": expires_at,
                "jti": str(uuid.uuid4()),
            },
            self.settings.auth_token_secret,
            algorithm="HS256",
        )
        return HostedAuthResponse(
            access_token=access_token,
            expires_in=self.settings.auth_token_ttl_seconds,
            build_imports=self.usage_store.quota(subject_id),
        )

    def authenticate(self, authorization: str | None, required_scope: str) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise HostedAuthenticationError("A bearer token is required.")
        token = authorization.removeprefix("Bearer ").strip()
        try:
            payload = jwt.decode(
                token,
                self.settings.auth_token_secret,
                algorithms=["HS256"],
                audience=self.audience,
                issuer=self.issuer,
                options={
                    "require": ["iss", "aud", "sub", "scope", "env", "bid", "iat", "exp", "jti"]
                },
            )
        except jwt.PyJWTError as exc:
            raise HostedAuthenticationError("The bearer token is invalid or expired.") from exc
        scopes = payload.get("scope")
        if not isinstance(scopes, list) or required_scope not in scopes:
            raise HostedAuthenticationError("The bearer token does not allow this operation.")
        if (
            payload.get("env") != self.settings.appstore_environment
            or payload.get("bid") != self.settings.appstore_bundle_id
        ):
            raise HostedAuthenticationError("The bearer token belongs to another app environment.")
        subject_id = payload.get("sub")
        if not isinstance(subject_id, str) or not subject_id:
            raise HostedAuthenticationError("The bearer token has no subject.")
        return subject_id

    def _subject_id(self, app_transaction_id: str) -> str:
        identity = (
            f"{self.settings.appstore_environment}:{self.settings.appstore_bundle_id}:"
            f"{app_transaction_id}"
        ).encode()
        digest = hmac.new(self.settings.subject_hmac_secret.encode(), identity, hashlib.sha256).digest()
        return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


@dataclass(frozen=True)
class CompanionSessionStatus:
    authenticated: bool
    expires_at: int
    build_imports: BuildImportQuota | None


class CompanionSession:
    def __init__(self):
        self._lock = threading.Lock()
        self._access_token: str | None = None
        self._expires_at = 0
        self._build_imports: BuildImportQuota | None = None

    def set(self, response: HostedAuthResponse) -> CompanionAuthResponse:
        expires_at = int(time.time()) + response.expires_in
        with self._lock:
            self._access_token = response.access_token
            self._expires_at = expires_at
            self._build_imports = response.build_imports
        return CompanionAuthResponse(
            authenticated=True,
            expires_at=expires_at,
            build_imports=response.build_imports,
        )

    def access_token(self) -> str | None:
        with self._lock:
            if not self._access_token or self._expires_at <= int(time.time()) + 30:
                self._clear_locked()
                return None
            return self._access_token

    def update_quota(self, access_token: str, quota: BuildImportQuota | None) -> None:
        if quota is None:
            return
        with self._lock:
            if hmac.compare_digest(self._access_token or "", access_token):
                self._build_imports = quota

    def status(self) -> CompanionSessionStatus:
        with self._lock:
            authenticated = bool(
                self._access_token and self._expires_at > int(time.time()) + 30
            )
            if not authenticated:
                self._clear_locked()
            return CompanionSessionStatus(
                authenticated=authenticated,
                expires_at=self._expires_at if authenticated else 0,
                build_imports=self._build_imports,
            )

    def clear(self) -> None:
        with self._lock:
            self._clear_locked()

    def _clear_locked(self) -> None:
        self._access_token = None
        self._expires_at = 0
        self._build_imports = None


companion_session = CompanionSession()


@lru_cache
def get_usage_store() -> UsageStore:
    settings = get_settings()
    return UsageStore(
        settings.usage_database_path,
        settings.build_import_lifetime_limit,
        settings.import_processing_lease_seconds,
    )


@lru_cache
def get_hosted_auth_service() -> HostedAuthService:
    settings = get_settings()
    return HostedAuthService(settings, get_usage_store())
