# Manual repro — network drop stream recovery (PB-04 / upstream #158/#186)

**Fork fix:** `8.0.14` — on transient `NSURLError*` (connection lost / timeout / offline), retry Range request from last absolute byte (up to 5 attempts with backoff) instead of `doneCallback(nil)` silent stall.

## Steps

1. Play a remote audiobook stream on a physical device (Wi‑Fi).
2. Mid-chapter, toggle **Airplane Mode** on for ~5–15s, then off.
3. Expect: playback resumes near pre-drop position (±5s) **or** a recoverable error is surfaced — not silent zero / stuck forever.
4. Repeat once on cellular.

## Pass criteria

- [ ] Brief airplane toggle: resume or explicit recoverable error
- [ ] Position within ±5s of pre-drop when resume succeeds
