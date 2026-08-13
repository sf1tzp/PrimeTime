---
name: verify
description: Build, launch, and drive Moment Tally to verify changes against the live traggo.lofi server. Auto-invoke only on macbook-air; on any other machine (check `hostname`) run only when the user explicitly asks to verify.
---

# Verifying Moment Tally

> **Machine gate:** only invoke this skill unprompted on macbook-air. On other
> machines (e.g. macmini) the build/launch/AX-drive cycle is too resource-heavy
> to run by default — skip verification there unless the user explicitly asks.

## Build & launch

```bash
just build          # swift build + codesign with "TraggoMenuApp Dev"
./.build/debug/MomentTally > /tmp/app.log 2>&1 &   # plain bash background; wait ~5-10s
```

On a machine with no codesigning identity (e.g. macbook-air), skip `just
build` and use plain `swift build`. Demo mode (`--demo` or `PRIMETIME_DEMO=1`)
never touches the Keychain — token reads and sync connects are guarded by
`!isDemo` — so the unsigned binary launches with zero prompts and is the
preferred target for screenshots and AX driving there.

**Brand fonts in unbundled builds (2026-08-13):** `bundle-app.sh` is the only
thing that injects the licensed Palm Springs face (PR #204), so a bare
`.build/debug` binary renders every `Brand.script` surface in the sans
fallback — easy to mistake for a rendering bug when the same commit "worked"
on a machine where the font is installed in Font Book. To see the real face,
seed the fonts next to the binary after `swift build`:
`mkdir -p .build/debug/Fonts && cp ~/.sfi/brand-assets/fonts/*.otf
.build/debug/Fonts/`. Copy, don't symlink — `registerFonts()`'s
`contentsOfDirectory(at:)` returns an empty list for a symlinked directory.

**Keychain gotcha (fixed 2026-07-23 on macmini):** if launches prompt for the
login-keychain password after every rebuild, the "TraggoMenuApp Dev" cert has
no codeSign trust entry (`security find-identity -v -p codesigning` shows 0
valid), so the ACL's cert-anchored requirement can never validate. Fix once
per machine:

```bash
security find-certificate -c "TraggoMenuApp Dev" -p > /tmp/dev-cert.pem
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db /tmp/dev-cert.pem   # user confirms a dialog
```

(Setting "Always Trust" in Keychain Access can silently fail to persist —
verify with `security dump-trust-settings`.) A launch stuck in
`SecItemCopyMatching` (state `SN`, ~0 CPU, never appears in System Events)
means a dialog is waiting; only the user can dismiss it.

## Driving it

The element map, screenshot/recording techniques, and every AX caveat (the
text-entry unreliability, the two-instances trap, the popover toggle state)
live in [shared/ax-driving.md](../shared/ax-driving.md) — read it before any
System Events work. The same reference backs the `capture` skill (release
asset batches); add new AX learnings there, not here.

## Verification-specific caveats

- The server is `https://traggo.lofi` (fast check: `curl -sk -o /dev/null -w
  "%{http_code}" https://traggo.lofi/`). Mutations hit real user data — create
  your own test timespan (quick-start a tag set, stop it) and delete it when
  done.
