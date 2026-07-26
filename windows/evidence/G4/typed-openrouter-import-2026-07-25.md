# Typed OpenRouter and secure build import - 2026-07-25

## Scope

This evidence covers typed, text-only chat and public build import. Screenshot capture,
clipboard image ingestion, microphone access, speech recognition, and dictation remain
approved Windows MVP exclusions and have no product UI, service, package capability, or
release gate.

## Pinned provider contract

- The only production model constant is `google/gemini-3.6-flash`.
- OpenRouter's public model API and official model page were checked on 2026-07-25. The
  model accepts text and supports structured output. Its reasoning metadata reports
  mandatory reasoning with `minimal`, `low`, `medium`, and `high` effort.
- Production calls go directly to
  `https://openrouter.ai/api/v1/chat/completions` through the single lazy
  `AssistantHttpClient.Instance`. There is no SDK, proxy, backend, local listener, local
  model, or fallback AI prose.
- Requests use Bearer authentication, the pinned model, text-only messages, a strict JSON
  response schema, `provider.require_parameters`, and minimal reasoning excluded from the
  returned payload.
- Provider, authentication, credit, rate-limit, model, timeout, network, malformed, and
  invalid-response failures are explicit and do not include response bodies, prompts, or
  credentials.

Relevant production code:

- [`../../src/BG3HonorAssistant.Infrastructure/Networking/AssistantHttpClient.cs`](../../src/BG3HonorAssistant.Infrastructure/Networking/AssistantHttpClient.cs)
- [`../../src/BG3HonorAssistant.Infrastructure/OpenRouter/OpenRouterClient.cs`](../../src/BG3HonorAssistant.Infrastructure/OpenRouter/OpenRouterClient.cs)
- [`../../src/BG3HonorAssistant.Core/Chat/ChatPromptBuilder.cs`](../../src/BG3HonorAssistant.Core/Chat/ChatPromptBuilder.cs)
- [`../../src/BG3HonorAssistant.App/MainWindow.xaml`](../../src/BG3HonorAssistant.App/MainWindow.xaml)
- [`../../src/BG3HonorAssistant.App/MainWindow.xaml.cs`](../../src/BG3HonorAssistant.App/MainWindow.xaml.cs)

## Typed chat behavior

Automated tests prove current-step, route, and party scopes; current-step priority;
bounded lexical route selection; the most recent eight turns; strict answer JSON; source
deduplication; the exact Act 2 route-unavailable gate; text-only request construction;
structured response decoding; content-part decoding; and explicit error mappings.

A product UI Automation smoke used the saved Credential Manager entry to submit a typed
question through the built WPF Chat surface. The UI reached
`Answered by the pinned Google Gemini 3.6 Flash model.` The chat was then cleared. A
binary scan of the local SQLite database found no copy of the exact prompt. The provider
answer and credential were not written to evidence or logs.

Chat remains usable only in memory for the current process and is cleared on app close,
run change, act change, or the Clear chat command. Guide, route, party, Settings, and
diagnostics remain usable without an OpenRouter key.

## Credential behavior

The key is stored under the generic Credential Manager target
`BG3HonorAssistant/OpenRouter`. The product supports save/replace, connection test, and
remove. Automated tests cover trimmed round-trip, replacement, and deletion. Product
diagnostics expose only configured/not-configured state and the pinned model.

The user-supplied temporary development key is also present in the ignored root `.env`
for this PR workflow. It must be removed from both locations when the user requests PR
cleanup; neither value is committed or packaged.

## Secure public build import

- URLs must be public `https://` endpoints on port 443 with no user information.
- DNS is validated before every request and again at connect time. Any loopback,
  link-local, private, carrier-grade NAT, documentation, benchmark, multicast, reserved,
  or otherwise non-public answer rejects the request.
- Redirects are manual, bounded to five hops, and revalidated at every hop.
- HTML, XHTML, plain text, and PDF are accepted. Scripts, styles, templates, SVG, canvas,
  and other non-content nodes are removed from HTML.
- Content length and streamed bytes are capped at 5 MB; extracted text is capped at
  60,000 characters.
- Retrieved page instructions are delimited as untrusted data. The structured model
  result is strictly decoded and passed through the existing level, class-split,
  duplicate-level, 27-point-buy, and distinct +2/+1 validators.
- Legal imports persist globally in SQLite with the verify marker. Deletion is blocked
  while an import is assigned.

Relevant tests:

- [`../../tests/BG3HonorAssistant.Core.Tests/Chat/ChatPromptBuilderTests.cs`](../../tests/BG3HonorAssistant.Core.Tests/Chat/ChatPromptBuilderTests.cs)
- [`../../tests/BG3HonorAssistant.Infrastructure.Tests/Networking/PublicNetworkPolicyTests.cs`](../../tests/BG3HonorAssistant.Infrastructure.Tests/Networking/PublicNetworkPolicyTests.cs)
- [`../../tests/BG3HonorAssistant.Infrastructure.Tests/OpenRouter/OpenRouterClientTests.cs`](../../tests/BG3HonorAssistant.Infrastructure.Tests/OpenRouter/OpenRouterClientTests.cs)
- [`../../tests/BG3HonorAssistant.Infrastructure.Tests/BuildImport/SecureBuildSourceLoaderTests.cs`](../../tests/BG3HonorAssistant.Infrastructure.Tests/BuildImport/SecureBuildSourceLoaderTests.cs)
- [`../../tests/BG3HonorAssistant.Infrastructure.Tests/BuildImport/BuildImportCoordinatorTests.cs`](../../tests/BG3HonorAssistant.Infrastructure.Tests/BuildImport/BuildImportCoordinatorTests.cs)
- [`../../tests/BG3HonorAssistant.App.Tests/AssistantControllerTests.cs`](../../tests/BG3HonorAssistant.App.Tests/AssistantControllerTests.cs)
- [`../../tests/BG3HonorAssistant.Package.Tests/PackageManifestTests.cs`](../../tests/BG3HonorAssistant.Package.Tests/PackageManifestTests.cs)

## Verification results

- Release build: 0 warnings, 0 errors.
- Automated suite: 267 passed, 0 failed, 0 skipped. Machine-readable results are linked
  from [`../automated-baseline.md`](../automated-baseline.md).
- NuGet vulnerability audit: no vulnerable direct or transitive package reported.
- Live canary attempt 1 correctly failed as an invalid empty response. Investigation
  found the pinned model's mandatory reasoning consumed the deliberately tiny output
  budget. The request contract was corrected to minimal/excluded reasoning and a
  realistic response budget.
- Live canary attempt 2 returned the required strict `{"answer":"OK"}` response and
  passed 1/1 against the real direct provider endpoint. The canary runs only when
  `BG3_RUN_LIVE_OPENROUTER=1`; it is inert in the normal test baseline.

## Evidence boundary

This proves the implemented typed-provider, session-only chat, credential, public-fetch,
structured-import, and MVP-exclusion contracts. It does not prove production MSIX
signing, clean-VM networking, update/uninstall behavior, or the final delivered-byte
audit. Those remain G5 requirements.
