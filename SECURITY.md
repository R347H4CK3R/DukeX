# Security Policy

## Supported Versions

DukeX is alpha software. Security fixes are handled for the latest published
alpha build and the current `master` branch.

| Version | Supported |
| --- | --- |
| Latest alpha release | Yes |
| Current `master` branch | Yes |
| Older alpha builds | No |

If you are testing an older build, please reproduce the issue on the latest
release or current source before reporting when possible.

## Reporting A Vulnerability

Please do not open a public issue for a suspected security vulnerability.

Use GitHub's private security advisory flow when available:

https://github.com/MaftyManicEMU/DukeX/security/advisories/new

If that is unavailable, contact the maintainer privately through GitHub and
include enough detail to coordinate a private report.

Useful report details:

- Affected DukeX version or commit.
- Device model and iOS version.
- Install method and JIT method.
- Steps to reproduce.
- Expected and observed behavior.
- Crash logs, sanitizer output, or proof-of-concept files when safe to share.
- Whether the issue appears DukeX-specific or inherited from xemu/QEMU.

Do not attach Xbox system files, game images, saves containing personal data,
signing certificates, provisioning profiles, or other private material.

## Disclosure Process

Security reports will be acknowledged as soon as practical. After triage, the
maintainer will coordinate a fix, release timing, and public disclosure notes if
the issue is confirmed.

Please allow time for investigation before publishing details publicly. Reports
that affect upstream xemu or QEMU may also need to be coordinated with those
projects.

## Scope

This policy covers DukeX-specific code, including the iOS app shell, build
scripts, launch/JIT handoff, bundled runtime integration, renderer presentation
path, and release packaging.

For vulnerabilities that are clearly in upstream xemu or QEMU with no
DukeX-specific behavior, please also follow the upstream project's security
process.
