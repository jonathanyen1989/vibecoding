# FocusLens GitHub Release Checklist

This checklist is for publishing FocusLens as a free open-source macOS MVP.

## 1. Repository Basics

- Keep the project name as `FocusLens`.
- Suggested GitHub repository name: `focuslens-macos`.
- Use the tagline: `Live presentation spotlight for macOS`.
- License: MIT.

## 2. Files to Include

Required:

- `Package.swift`
- `Sources/`
- `Assets/`
- `README.md`
- `LICENSE`
- `.gitignore`
- `docs/`
- `scripts/`

Recommended docs:

- `docs/MVP_SCRIPT_TEST_NOTES.md`
- `docs/GITHUB_RELEASE_CHECKLIST.md`
- `docs/V0.3_REQUIREMENTS.md`

## 3. Files to Exclude

Do not upload:

- `.build/`
- `dist/`
- `.local-signing/`
- `.DS_Store`
- signing certificates
- private keys
- `.p12` files
- keychain files
- Apple ID credentials
- notarization credentials

The current `.gitignore` already excludes the main generated folders.

## 4. MVP Run Instructions

For the current MVP, recommend source-based testing:

```bash
swift run FocusLensMacMVP
```

Do not present the unsigned `.app` bundle as the primary install path yet. The app bundle still needs stable signing and notarization before it is friendly for non-technical users.

## 5. First GitHub Release Strategy

For the first public version, publish:

- source code only
- README instructions
- screenshots or GIF demo if available
- clear note that this is an MVP

Avoid promising a polished installer until signing and notarization are solved.

## 6. Future Release Strategy

When the MVP is stable, add:

- Developer ID signing
- notarized `.dmg`
- GitHub Release asset
- simple installation guide
- troubleshooting guide for Screen Recording permission

## 7. Suggested README Positioning

Use this positioning:

```text
FocusLens is a live presentation spotlight for macOS.
It helps presenters quickly highlight and zoom a selected screen region during demos, teaching, and screen sharing.
```

Avoid describing it as a paid product for now. Keep it free and open source until there is enough user feedback to justify a commercial version.
