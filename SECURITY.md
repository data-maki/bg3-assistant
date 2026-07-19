# Security

Please report vulnerabilities privately through GitHub Security Advisories instead of opening a public issue.

Release packages contain a non-secret hosted backend URL and a keyless local companion service. OpenRouter and Exa credentials stay in the hosted backend's environment; they are never copied into the app bundle, user settings, the run database, or macOS Keychain. Run state and imported build JSON stay in the user's Application Support directory. The packaged companion binds only to `127.0.0.1` and proxies AI requests to the configured HTTPS backend.

TestFlight authentication uses Apple's signed AppTransaction. The hosted backend verifies the Apple certificate chain and app identity, derives a pseudonymous HMAC subject, and issues a one-hour scoped bearer token. The Apple transaction and bearer are never returned to browser JavaScript or stored in the local database. A dedicated hosted ledger atomically limits each verified Apple subject to 30 lifetime build-import attempts and prevents retries with the same idempotency key from consuming another slot.

The hosted service still requires TLS, ingress-level request-size controls, IP throttling for the public authentication endpoint, log redaction, a durable quota volume, and network egress rules blocking private and cloud-metadata destinations. Sandbox/TestFlight and production deployments must use separate origins, secrets, and quota databases.

Loadout import accepts public HTTP(S) pages and sends their extracted text to OpenRouter. The importer rejects private or reserved network destinations, embedded URL credentials, nonstandard ports, redirect chains to blocked destinations, oversized responses, and unsupported content types. Report any URL-validation or redirect behavior that could reach a local service or cloud metadata endpoint.

Do not include API keys, save files, screenshots, logs, or personal run data in reports. Include the app version, macOS version, and minimal reproduction steps.
