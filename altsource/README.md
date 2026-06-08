# DukeX AltSource

This directory contains the canonical AltStore/SideStore source metadata for
DukeX distribution.

The source file is:

```text
altsource/source.json
```

When the repository is public, clients can use the raw source URL:

```text
https://raw.githubusercontent.com/MaftyManicEMU/DukeX/master/altsource/source.json
```

The AltSource references the signed or unsigned IPA attached to the matching
GitHub Release. Release artifacts are not committed to the repository.

Notes for maintainers:

- Keep image assets under `altsource/assets/`.
- Keep the app `downloadURL`, `version`, `buildVersion`, `size`, and release
  notes in sync with the latest GitHub Release.
- Landscape marketing images are used for the source header and news cards.
  Portrait marketing images are used for SideStore's screenshot carousel.
