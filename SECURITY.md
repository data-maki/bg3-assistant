# Security

Please report vulnerabilities privately through GitHub Security Advisories instead of opening a public issue.

The application stores the optional OpenRouter key in macOS Keychain. Run state and imported build JSON stay in the user's Application Support directory. The packaged backend binds only to `127.0.0.1`.

Loadout import accepts public HTTP(S) pages and sends their extracted text to OpenRouter. The importer rejects private or reserved network destinations, embedded URL credentials, nonstandard ports, redirect chains to blocked destinations, oversized responses, and unsupported content types. Report any URL-validation or redirect behavior that could reach a local service or cloud metadata endpoint.

Do not include API keys, save files, screenshots, logs, or personal run data in reports. Include the app version, macOS version, and minimal reproduction steps.
