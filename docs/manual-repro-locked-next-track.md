# Manual repro — locked/background next-track (PB-02 / upstream #162)

**Fork fix:** `8.0.12` — keep `UIBackgroundTask` (`SAPlayer.PlayNextTrack`) until `PlayingStatus.playing` **or** `StreamingBuffer.isReadyForPlaying` (30s timeout / expire).

## Example app

1. Open `Example/SwiftAudioPlayer.xcworkspace`, run on a **physical iPhone** (lock-screen behavior is unreliable on Simulator).
2. Select **3+ remote** audio URLs (Wi‑Fi first, then cellular).
3. Start track 1; ensure remaining URLs are queued via `queueRemoteAudio`.
4. **Lock the device** before track 1 ends (Control Center lock or side button).
5. Expect: track 2 starts while locked; `SAPlayer.Updates.AudioQueue` fires; console does **not** show sustained `Not enough data for read-conversion` / `stream_error` after the transition.
6. Repeat across the 3-URL queue.

## Krishna Library app

1. Build with SPM pin `SwiftAudioPlayer` ≥ `8.0.12`.
2. Play an entitled multi-chapter audiobook; lock before chapter end.
3. Confirm next chapter starts and listening session continues.

## Pass criteria

- [ ] Wi‑Fi: next track starts while locked (3+ URLs)
- [ ] Cellular: same
- [ ] No silent stall on second track when locked
