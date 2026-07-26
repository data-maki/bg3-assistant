# Independent build/RID correction re-review

Reviewed correction: `0674d4a734b9d88ae7da371a993b4dae267008f8`

## Q/A before experiments

### Hypothesis

The correction may close the original static gaps while still admitting one of
four false-green classes:

1. recursive PE inspection may reject valid neutral IL or accept malformed,
   native x86, opposite-architecture, or RID-contaminated payloads;
2. MSBuild property pairs or Platform-only solution entrypoints may still form a
   self-consistent but noncanonical architecture;
3. workflow syntax may appear architecture-aware without proving the selected
   SDK, .NET host, every testhost ISA, and a positive test count;
4. the packaging interface probe may correctly fail in this isolated branch,
   leaving the matrix non-executable until the packaging lane is integrated.

### Existing evidence

- Review `a1fab44` invalidated recursive PE coverage, caller-controlled helper
  invariants, .NET/testhost ISA proof, zero-test handling, the packaging
  interface, Platform-only solution selection, and SDK installation pinning.
- Correction `0674d4a` replaces helper-property comparisons with canonical
  literals, projects Platform into architecture, recursively classifies PE/CLI
  images, injects a shared testhost architecture assertion, parses TRX counters,
  pins SDK installation to `windows/global.json`, and adds a packaging-interface
  preflight.
- This checkout contains no prior build artifacts. The packaging script currently
  exposes no `-Architecture` parameter, which is an expected cross-lane
  integration dependency that the new preflight must reject.

### Unknowns

- Whether both locked graphs restore unchanged from this isolated checkout.
- Whether `Platform=arm64|x64` alone produces all canonical values and whether
  mixed Platform/BG3Architecture/RID inputs fail.
- Whether the exact GitHub Actions YAML and PowerShell syntax is valid without a
  hosted run.
- Whether a native ARM64 .NET SDK/testhost is available locally. Local evidence
  must distinguish native-ISA ARM64 PowerShell from x64-emulated .NET.
- Whether the recursive classifier accepts real neutral IL yet rejects arbitrary
  opposite-architecture and malformed files regardless of filename.

### Acceptance tests

1. Enumerate arbitrary nested opposite-architecture and malformed PE files,
   native x86, valid neutral IL, and target-native PE; accept only the latter two.
2. Override both legacy helper-property pairs and prove canonical literal
   validation cannot be bypassed.
3. Validate `Platform=arm64` and `Platform=x64` without BG3Architecture, plus
   contradictory Platform/BG3Architecture/RID/PlatformTarget inputs.
4. Restore the complete locked solution independently for arm64 and x64.
5. Parse the exact workflow and inspect setup-dotnet/global-json, runner ISA,
   PowerShell ISA, .NET host ISA, per-project testhost ISA, TRX, and packaging
   preflight syntax.
6. Prove every discovered test project explicitly sets `IsTestProject=true` and
   receives the shared architecture test.
7. Feed the TRX gate zero and nonzero executed counters and require zero to fail.
8. Inspect the actual packaging command metadata; absent or incompatible
   architecture/version parameters must fail closed.
9. Check architecture-specific path/name isolation and reject artifact collisions.

## Results

### Verdict

**Accepted as the build/RID correction, but not accepted as an integrated green
matrix.** The completed adversarial cases close BUILD-RV-001, BUILD-RV-002,
BUILD-RV-006, and the locked-graph/artifact-isolation portions of the review.
The actual packaging script in this isolated branch still lacks mandatory
`-Architecture`; the new CI preflight correctly rejects it. Therefore BUILD-RV-005
remains an explicit integration blocker rather than a false green.

Hosted CI was not run. Physical Windows 11 ARM64 and native-x64 hardware validation
remain release gates.

### Evidence classification

- Environment: Windows 11 Pro `10.0.26200`, Parallels ARM Virtual Machine on
  Apple Silicon, `HypervisorPresent=True`.
- OS and PowerShell process: ARM64. This is native-ISA ARM64 VM evidence, not
  physical ARM64 hardware evidence.
- Selected SDK: exactly `10.0.302`; .NET host/RID: x64 / `win-x64`. Local
  restore, build, and testhost-capability evidence is x64 under ARM64 emulation.
- ARM64 publish: cross-built by the x64 SDK and inspected by native-ISA ARM64
  PowerShell. No local ARM64 .NET testhost was executed.
- No native-x64 hardware was available or claimed.

### Completed decisive cases

| Case | Result | Evidence |
|---|---|---|
| Platform-only arm64 | Pass | `BG3Architecture=arm64`, `Platform=arm64`, `PlatformTarget=arm64`, `RuntimeIdentifier=win-arm64`, exact two-RID list, and `BG3_TESTHOST_ARM64`. |
| Platform-only x64 | Pass | Symmetric x64 values and `BG3_TESTHOST_X64`. |
| Platform/BG3 conflict | Pass | Validation returned nonzero. |
| ARM RID conflict | Pass | Validation returned nonzero. |
| ARM PlatformTarget conflict | Pass | Validation returned nonzero. |
| Expected-RID helper paired override | Pass | Overriding helper and RID to x64 while targeting ARM64 returned nonzero. |
| Supported-RID helper paired override | Pass | Overriding helper and `RuntimeIdentifiers` to ARM64-only returned nonzero. |
| Locked ARM64 solution restore | Pass | All 11 projects restored in locked mode. |
| Locked x64 solution restore | Pass | All projects up-to-date in locked mode. |
| ARM64 self-contained publish | Pass | Isolated under `artifacts/publish/win-arm64`. |
| x64 self-contained publish | Pass | Isolated under `artifacts/publish/win-x64`. |
| Clean ARM64 recursive inspection | Pass | 487 PE images: 167 target ARM64, 320 verifiable neutral managed IL. |
| Clean x64 recursive inspection | Pass | 488 PE images: 168 target x64, 320 verifiable neutral managed IL. |
| Arbitrary neutral IL plus target-native PE | Pass | Copied under nested arbitrary `.blob` names; inspection remained green. |
| Arbitrary opposite-architecture native PE | Pass | ARM64 `kernel32.dll` copied under an arbitrary `.payload` name into x64 output; rejected as `0xAA64`. |
| Non-PE `.dll` | Pass | Rejected as invalid executable/library payload. |
| Truncated MZ with arbitrary extension | Pass | Rejected as truncated PE. |
| Native x86 arbitrary extension | Pass | `SysWOW64\kernel32.dll` (`0x014C`) rejected as forbidden native x86. |
| Opposite RID path containing neutral IL | Pass | Neutral assembly under `runtimes/win-arm64` in x64 output was rejected by path contamination check. |
| Artifact collision challenge | Pass for default matrix contract | Publish roots were distinct; ARM64/x64 app hosts and SQLite binaries had different SHA-256 hashes. |

These cases show that the classifier does not hide native payloads behind neutral
IL, does not false-reject real neutral IL, and does not depend on `.exe`/`.dll`
extensions to find MZ payloads.

### Static CI/testhost review

- `actions/setup-dotnet@v4` requests exactly `10.0.302` and points at
  `windows/global.json`.
- The workflow separately asserts OS ISA, PowerShell ISA, exact SDK version, and
  parsed .NET host ISA before restore.
- All five `*.Tests.csproj` files explicitly set `IsTestProject=true`.
- `Directory.Build.targets` links the shared
  `tests/TestHostArchitectureTests.cs` into every test project identified by
  `IsTestProject`; that test asserts the compile-time ARM64/x64 contract against
  the executing testhost `ProcessArchitecture` and requires 8-byte pointers.
- The CI loop fails on an empty project set, requires one exact TRX per project,
  parses `Counters.executed`, and rejects nonpositive values.
- The zero/nonzero TRX snippets and hosted testhosts were not executed in this
  bounded re-review after the coordinator requested an immediate result. Their
  static gates are present, but matching-architecture CI remains the execution
  proof.

### Remaining blocker: packaging interface

The actual `windows/tools/build-development-msix.ps1` in this isolated checkout
has `Version` and `Publisher` parameters only. It has no `Architecture` parameter,
still selects x64 MakeAppx, and emits an x64-named package.

The corrected workflow now inspects command metadata before invoking packaging and
requires:

- a mandatory `-Architecture`;
- a ValidateSet containing exactly `arm64,x64`; and
- the expected `-Version`.

That preflight will fail this isolated branch deterministically, which prevents
the prior false green but also means the end-to-end workflow cannot pass until the
reviewed packaging lane is integrated. This is an honest cross-lane gate, not a
reason to duplicate package implementation in the build lane.

### Final disposition and gates

- BUILD-RV-001 recursive PE/deps coverage: accepted by adversarial rerun.
- BUILD-RV-002 canonical invariants: accepted by paired-override rerun.
- BUILD-RV-003 OS/.NET/testhost ISA: static correction accepted; hosted
  matching-ISA execution still required.
- BUILD-RV-004 positive test count: static correction accepted; hosted zero/nonzero
  execution remains part of CI.
- BUILD-RV-005 packaging contract: blocked until packaging integration; current
  preflight fails closed as intended.
- BUILD-RV-006 Platform-only architecture selection: accepted for arm64 and x64,
  with contradictions rejected.
- BUILD-RV-007 SDK pin: exact install/selection syntax present and local selected
  SDK matched `10.0.302`; hosted action execution remains pending.

Still required: integrate packaging, run both Windows CI jobs through locked
restore/build/all-testhost execution/publish/package/inspection, perform packaged
native ARM64 QA on physical Windows 11 ARM64, and retain native-x64 physical
validation as a separate release gate.
