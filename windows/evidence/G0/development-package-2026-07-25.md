# Development package evidence — 2026-07-25

## Environment

- Oracle commit: `591e2331d45cd60505430610c24fe63b36c7293d`
- Windows: Windows 11 Pro 10.0.26200, build 26200
- Host architecture: ARM64
- Target architecture: x64 (`win-x64`)
- .NET SDK: 10.0.302
- MakeAppx: 10.0.28000.2270

## Result

`windows/tools/build-development-msix.ps1` published the WPF app self-contained and
MakeAppx successfully packed 1,252 files. The archive contains 1,254 ZIP entries after
the generated package block map and content-types metadata are included.

- Artifact: `windows/artifacts/BG3HonorAssistant_0.1.0.0_x64_unsigned.msix`
- Size: 98,143,294 bytes
- SHA-256: `FAE927157782F7649907CBE5BE382788F1E588DF2009F6993D66E4958DD61C97`
- Signature status: `NotSigned`
- Debug/runtime diagnostics: no PDB files and no `createdump.exe`
- Embedded executable manifest: `asInvoker`, `uiAccess=false`, per-monitor-v2 DPI;
  no sparse/external package identity metadata
- Shared payload: 11 companion portraits, 51 item icons, 697 build-option icons, one
  guide bundle, and the shared pet image
- Manifest: accepted by MakeAppx; x64, Windows.Desktop, minimum build 26100,
  `packagedClassicApp`, `mediumIL`, startup disabled, with only the `runFullTrust`
  capability
- MVP exclusion scan: zero capture/speech/microphone product entries and zero forbidden
  capture/speech API or service names in the application and Windows adapter assemblies

## Evidence boundary

This is construction evidence, not installation or runtime evidence. The named artifact
is unsigned and must not be distributed as a release. Development signing/install work is
recorded separately in `packaged-permissions-2026-07-25.md`; it is not production-signing
evidence. No BG3, native-x64 hardware, update, Defender, or clean-VM claim is made here.
