# Independent MSIX packaging follow-up review

Reviewed follow-up: `369b2d0`

## Q/A before experiments

- Q: What is the main hypothesis?
  - A: The follow-up may close the previously demonstrated x86-managed and multi-application gaps for its unit fixtures while still misclassifying real CLR variants, accepting malformed PE metadata, rejecting legitimate neutral IL, missing manifest namespace/executable variations, or diverging between pre-pack and post-unpack validation.
- Q: What evidence exists before this review?
  - A: The follow-up extracts package architecture validation into `validate-package-architecture.ps1`, adds behavioral package tests, updates manifest assertions, and reduces duplicate validator code in the build script. The original review reproduced x86-only managed payload acceptance, multiple packaged applications, and a structurally invalid main host.
- Q: What remains unknown?
  - A: Whether real `CustomMarshalers.dll`, malformed CLR directory values, forged metadata, 32-bit-required/preferred flags, mixed/native-entry CLR, ReadyToRun managed-native headers, and valid AnyCPU IL are classified correctly; whether ARM64EC, ARM64X, unknown, opposing SQLite, invalid main hosts, extra/mismatched applications, namespaces, PE bounds, temporary paths, cleanup, and native ARM64 MakeAppx pre/post equivalence are all handled safely.
- Q: What evidence label applies?
  - A: This environment is a Parallels ARM virtual machine on Apple Silicon. Native Windows PowerShell and ARM64 MakeAppx results are **native-ISA ARM64 VM packaging-only** evidence, not physical Windows ARM64 product, install, or runtime proof. No native-x64 physical hardware evidence can be claimed.

## Adversarial acceptance tests

1. Real x86-only `CustomMarshalers.dll` is rejected in both ARM64 and x64 layouts before and after packaging.
2. Malformed CLR RVA/size, forged metadata, 32BITREQUIRED, 32BITPREFERRED, native-entry/mixed-mode, and ReadyToRun managed-native content never receive the neutral-IL exemption.
3. A legitimate AnyCPU IL-only managed assembly is accepted in both target layouts without weakening native checks.
4. ARM64EC, ARM64X, x86 native, unknown, opposite ARM64/AMD64, and cross-architecture `e_sqlite3.dll` payloads are rejected.
5. The root main executable must be structurally valid, native, matching, unique, and exactly the executable declared by one packaged `Application`.
6. Extra applications, mismatched executables, namespace variations, missing identities/applications, and duplicate or shadow hosts fail closed.
7. Truncated/extreme PE offsets, short optional/section/CLR headers, invalid directory mappings, and integer-boundary cases fail closed without unsafe reads.
8. The source manifest uses one exact architecture placeholder, substitution preserves namespaces, and the unpacked identity equals the requested architecture.
9. Native ARM64 MakeAppx pack/unpack preserves all source payloads; the same validator passes clean layouts and rejects contaminated layouts before and after unpack.
10. Temporary roots remain under the OS temp directory, are unique, and are removed after success and failure.
11. Behavioral tests execute a nonzero count and directly cover the validator rather than only searching source strings.

## Results

The follow-up **closes the two critical original validation paths** for x86-only
managed payloads and multiple/mismatched manifest applications. It also closes the
exact zero-section main-host case. The follow-up is not fully accepted because
static re-review found three remaining validation gaps: main-host structural
proof is still incomplete, `Application` namespace validation is too permissive,
and valid native PE files with fewer optional-header directories are rejected.

The coordinator ended the experiment phase before the disposable independent
matrix was executed. The closure labels below therefore distinguish code/test
review from the packaging worker's recorded native-ISA ARM64 VM results. No new
physical or runtime claim is made.

## Prior invalidation closure

| Prior issue | Follow-up result | Closure |
|---|---|---|
| Real x86 `CustomMarshalers.dll` accepted as neutral IL | Rejected by the new CLR flag and metadata checks; directly covered by the new behavioral test | **Closed** |
| Malformed CLR RVA/size accepted | Rejected by bounded directory mapping; directly covered by the new behavioral test | **Closed** |
| 32BITREQUIRED/PREFERRED accepted | Rejected by explicit CLR portability checks | **Closed** |
| Mixed/native-entry x86 accepted | Rejected by explicit CLR checks | **Closed** |
| ReadyToRun/managed-native x86 accepted | Rejected when a managed-native header is present | **Closed** |
| Invalid CLR metadata accepted | Rejected when metadata signature or mapping is invalid | **Closed for covered case** |
| Extra packaged `Application` accepted | Exactly one application is now required | **Closed** |
| Mismatched manifest executable accepted | All executable references must now equal `BG3HonorAssistant.exe` | **Closed** |
| Zero-section synthetic main host accepted | A nonempty, in-bounds section table is now required | **Closed for exact prior case** |

## Requested QA disposition

| Case | Result | Evidence classification |
|---|---|---|
| Valid AnyCPU IL-only assembly | **Pass** | New behavioral test accepts real neutral managed IL |
| Real x86-only managed assembly | **Pass: rejected** | New behavioral test; worker reports 14/14 |
| Malformed/forged CLR cases | **Pass: rejected** | Behavioral fixtures in the follow-up |
| 32-bit-required/preferred | **Pass: rejected** | Static and behavioral coverage |
| Mixed/native-entry | **Pass: rejected** | Static and behavioral coverage |
| ReadyToRun/managed-native | **Pass: rejected** | Static and behavioral coverage |
| ARM64EC | **Pass: rejected** | Explicit validator branch |
| ARM64X, unknown, opposite ARM64/AMD64 | **Pass: rejected** | Generic machine mismatch branch |
| Opposite-architecture `e_sqlite3.dll` | **Pass: rejected** | Recursive filename-independent PE validation |
| Extra application | **Pass: rejected** | Behavioral manifest test |
| Mismatched executable | **Pass: rejected** | Behavioral manifest test |
| Alternate prefix for the correct foundation namespace | **Pass by design** | Namespace-aware identity selection |
| Application in a non-foundation namespace | **Fail** | BUILD-RV-MSIX-002 |
| Invalid main host beyond the prior zero-section case | **Fail** | BUILD-RV-MSIX-001 |
| Valid native PE with fewer optional-header directories | **Fail: false rejection risk** | BUILD-RV-MSIX-003 |
| Truncated/extreme PE bounds | **Pass: fail closed** | Bounded reads and section/RVA mapping |
| Source placeholder and namespace preservation | **Pass** | Exact source placeholder plus XML mutation |
| Native ARM64 MakeAppx clean pre/post validation | **Pass in worker evidence** | Native-ISA ARM64 VM packaging only |
| Native ARM64 MakeAppx contaminated post-unpack rejection | **Pass in worker evidence** | Native-ISA ARM64 VM packaging only |
| Temporary cleanup | **Pass by code review and worker evidence** | Unique temp root and `finally` cleanup |
| Nonzero behavioral tests | **Pass in worker evidence** | 14 passed, 0 failed, 0 skipped |

## Remaining findings

### BUILD-RV-MSIX-001 — High — main-host structural proof remains incomplete

- Architecture: ARM64 and x64.
- Result: **open**.
- Evidence: the validator now requires a matching machine, native classification,
  one or more in-bounds sections, and a valid optional-header shape. It does not
  verify that the image has an executable entry point, executable image
  characteristics, or an entry point mapped into an executable section.
- Root cause: the PE parser proves architecture and some structure, but the final
  error still claims the file is a native app host.
- Reviewer result: the exact earlier zero-section fixture is closed; the broader
  invalid-main-host acceptance criterion is only partially met.
- Risk: MakeAppx packages files but does not prove that the declared executable
  can launch. Mandatory packaged launch/process-architecture QA reduces but does
  not eliminate this pre-release gate weakness.

### BUILD-RV-MSIX-002 — Medium — Application namespace is not enforced

- Architecture: ARM64 and x64 manifest validation.
- Result: **open**.
- Evidence: identity selection requires the foundation namespace, but application
  selection uses `local-name() = "Application"`. A same-named element from another
  namespace can satisfy the count and executable checks.
- Root cause: application selection is namespace-agnostic while identity
  selection is namespace-aware.
- Reviewer result: the additional and mismatched foundation-application cases are
  closed; wrong-namespace application handling remains permissive.
- Risk: native MakeAppx should reject an invalid schema before artifact copy, so
  this is defense-in-depth rather than a demonstrated final artifact escape.

### BUILD-RV-MSIX-003 — Medium — native PE parsing is stricter than the PE format requires

- Architecture: ARM64 and x64.
- Result: **open compatibility risk**.
- Evidence: every PE is required to declare a complete CLI data-directory slot
  and at least fifteen optional-header directories before it can be classified as
  native. A valid native PE may declare fewer directories because it has no CLR
  header.
- Root cause: CLR-directory availability is required before the validator checks
  whether the CLR RVA/size is absent.
- Reviewer result: bounds behavior is fail-closed, but strict neutral/native
  classification can falsely reject a legitimate architecture-matching native
  dependency.
- Risk: current published runtime payloads appear to use the expected directory
  shape. A future SDK or native dependency could be rejected despite matching the
  package architecture.

## Native ARM64 packaging evidence

The worker records native ARM64 MakeAppx pack/unpack success for clean ARM64 and
x64-target layouts, identical validation before and after unpack, rejection of the
real x86 assembly before pack and after a deliberately ungated unpack, and a
14-test green package suite. These results are **native-ISA ARM64 VM
packaging-only** evidence.

They are not physical Windows ARM64 proof, installed-product proof, or
native-x64 hardware proof. Physical ARM64 install/runtime QA and native-x64
physical validation remain release gates.

## Reviewer conclusion

The critical x86-managed and multi-application invalidations from the first review
are closed in `369b2d0`. Accept those closures for integration only with the
recorded behavioral tests and native-ISA ARM64 VM packaging qualification.
BUILD-RV-MSIX-001 through BUILD-RV-MSIX-003 require explicit disposition before
the packaging validator is described as complete. No physical hardware claim is
supported by this re-review.
