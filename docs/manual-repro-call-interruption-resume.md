# Manual repro — call / VoIP interruption resume (PB-03 / upstream #154)

**Fork fix:** `8.0.13` — on interruption `.ended` + `.shouldResume`, re-activate session and `playEngine()` (with short retry) instead of bare `play()`.

## Steps

1. Play a streamed audiobook chapter (Example app or Krishna Library) on a **physical device**.
2. Place or receive a **cellular call** (or WhatsApp/VoIP) until audio pauses.
3. End the call.
4. Expect: playback resumes without tapping Play; no false purchase/subscribe gate for entitled titles.
5. Optional: unplug headphones mid-play → should pause (route `oldDeviceUnavailable`).

## Pass criteria

- [ ] Cellular call: auto-resume when system sets `.shouldResume`
- [ ] VoIP (WhatsApp) when `.shouldResume` is present: auto-resume
- [ ] Entitled title does not show purchase CTA after resume
