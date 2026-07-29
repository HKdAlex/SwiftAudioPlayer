#  Changelog

## 8.0.12

- Hold `UIBackgroundTask` for queue advance until `PlayingStatus.playing` or stream buffer ready (fixes locked-device next-track stall; upstream #162 / PB-02). See `docs/manual-repro-locked-next-track.md`.


## 7.6.0

- Add Carthage support thanks to @cntrump!

## 7.5.0

- Propagate up any errors from downloading audio. This will cause breaking changes to `SAPlayer.Downloader.downloadAudio(...)`

## 7.3.0

- Take in PR from @cntrump to use the non-deprecated subscription pattern in loop feature
