# Packaged startup lifecycle evidence - 2026-07-25

## Environment

- Windows 11 Pro 10.0.26200, build 26200
- Host architecture: ARM64; package target: x64
- Application process integrity: medium
- Package version: `0.1.0.0`

## Signed-development lifecycle observation

A temporary self-signed development certificate was used only to test the Windows
deployment path. SignTool verified the signed MSIX, then `Add-AppxPackage` installed:

`BG3HonorAssistant.Dev_0.1.0.0_x64__cq56nxss0c5dp`

`Get-AppxPackage` reported architecture `X64` and status `Ok`. The app launched from
`C:\Program Files\WindowsApps` and showed the same package full name through its runtime
identity adapter.

UI Automation observed startup disabled on first launch:

`Start at login is off.`

Invoking the explicit Enable button changed the packaged status to:

`Start at login is on.`

Invoking Disable restored:

`Start at login is off.`

The app was then closed and the package removed. A subsequent package query reported it
absent. No live BG3, screenshot, microphone, or speech action was performed.

## Scope and cleanup boundary

The tested package predates the owner-approved screenshot and microphone/speech
exclusions and is superseded. Its startup/install observations are useful G0 evidence but
do not prove the final MVP artifact.

The non-exportable private signing key and the exact public development certificate were
removed. Follow-up checks reported the certificate absent from
`CurrentUser\My` and `LocalMachine\TrustedPeople`, the package absent, and no app process
running. The rebuilt no-capture/no-microphone MVP package must repeat install, launch,
startup off/on/off, uninstall, and exact-certificate cleanup.

This is development-signing evidence only. Production users must receive a Store- or
CA-signed MSIX and must never import a certificate or elevate.
