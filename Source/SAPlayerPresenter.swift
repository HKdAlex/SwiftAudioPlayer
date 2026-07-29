//
//  SAPlayerPresenter.swift
//  SwiftAudioPlayer
//
//  Created by Tanha Kabir on 2019-01-29.
//  Copyright © 2019 Tanha Kabir, Jon Mercer
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import AVFoundation
import MediaPlayer
#if os(iOS)
import UIKit // Added for UIBackgroundTaskIdentifier
#endif
class SAPlayerPresenter {
    weak var delegate: SAPlayerDelegate?
    var shouldPlayImmediately = false //for auto-play
    
    var needle: Needle?
    var duration: Duration?
    
    private var key: String?
    private var isPlaying: SAPlayingStatus = .buffering
    
    private var urlKeyMap: [Key: URL] = [:]
    
    var durationRef: UInt = 0
    var needleRef: UInt = 0
    var playingStatusRef: UInt = 0
    var audioQueue: [SAAudioQueueItem] = []

    #if os(iOS)
    /// Keeps the process awake while the next remote track buffers after a queue advance (upstream #162 / PB-02).
    private var playNextBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var playNextPlayingSubscriptionId: UInt?
    private var playNextBufferSubscriptionId: UInt?
    private var playNextTimeoutWorkItem: DispatchWorkItem?
    private let playNextBackgroundTimeoutSeconds: TimeInterval = 30
    #endif
    
    init(delegate: SAPlayerDelegate?) {
        self.delegate = delegate

        durationRef = AudioClockDirector.shared.attachToChangesInDuration(closure: { [weak self] (duration) in
            guard let self = self else { throw DirectorError.closureIsDead }
            
            self.delegate?.updateLockScreenPlaybackDuration(duration: duration)
            self.duration = duration
            
            self.delegate?.setLockScreenInfo(withMediaInfo: self.delegate?.mediaInfo, duration: duration)
        })
        
        needleRef = AudioClockDirector.shared.attachToChangesInNeedle(closure: { [weak self] (needle) in
            guard let self = self else { throw DirectorError.closureIsDead }
            
            self.needle = needle
            self.delegate?.updateLockScreenElapsedTime(needle: needle)
        })
        
        playingStatusRef = AudioClockDirector.shared.attachToChangesInPlayingStatus(closure: { [weak self] (isPlaying) in
            guard let self = self else { throw DirectorError.closureIsDead }
            
            if(isPlaying == .paused && self.shouldPlayImmediately) {
                self.shouldPlayImmediately = false
                self.handlePlay()
            }
            
            // solves bug nil == owningEngine || GetEngine() == owningEngine where too many
            // ended statuses were notified to cause 2 engines to be initialized and causes an error.
            // TODO don't need guard
            guard isPlaying != self.isPlaying else { return }
            self.isPlaying = isPlaying
            
            if(self.isPlaying == .ended) {
                self.playNextAudioIfExists()
            }
        })
    }

    deinit {
        #if os(iOS)
        endPlayNextBackgroundWork(reason: "presenter-deinit")
        #endif
        AudioClockDirector.shared.detachFromChangesInDuration(withID: durationRef)
        AudioClockDirector.shared.detachFromChangesInNeedle(withID: needleRef)
        AudioClockDirector.shared.detachFromChangesInPlayingStatus(withID: playingStatusRef)
    }
    
    func getUrl(forKey key: Key) -> URL? {
        return urlKeyMap[key]
    }
    
    func addUrlToKeyMap(_ url: URL) {
        urlKeyMap[url.key] = url
    }
    
    func handleClear() {
        delegate?.clearEngine()
        AudioClockDirector.shared.resetCache()
        
        needle = nil
        duration = nil
        key = nil
        delegate?.mediaInfo = nil
        delegate?.clearLockScreenInfo()
    }
    
    func handlePlaySavedAudio(withSavedUrl url: URL) {
        resetCacheForNewAudio(url: url)
        delegate?.setLockScreenControls(presenter: self)
        delegate?.startAudioDownloaded(withSavedUrl: url)
    }
    
    func handlePlayStreamedAudio(withRemoteUrl url: URL, bitrate: SAPlayerBitrate) {
        resetCacheForNewAudio(url: url)
        delegate?.setLockScreenControls(presenter: self)
        delegate?.startAudioStreamed(withRemoteUrl: url, bitrate: bitrate)
    }
    
    private func resetCacheForNewAudio(url: URL) {
        self.key = url.key
        urlKeyMap[url.key] = url
        
        AudioClockDirector.shared.setKey(url.key)
        AudioClockDirector.shared.resetCache()
    }
    
    func handleQueueStreamedAudio(withRemoteUrl url: URL, mediaInfo: SALockScreenInfo?, bitrate: SAPlayerBitrate) {
        audioQueue.append(SAAudioQueueItem(loc: .remote, url: url, mediaInfo: mediaInfo, bitrate: bitrate))
    }
    
    func handleQueueSavedAudio(withSavedUrl url: URL, mediaInfo: SALockScreenInfo?) {
        audioQueue.append(SAAudioQueueItem(loc: .saved, url: url, mediaInfo: mediaInfo))
    }
    
    func handleRemoveFirstQueuedItem() -> URL? {
        guard audioQueue.count != 0 else { return nil }
        
        return audioQueue.remove(at: 0).url
    }
    
    func handleClearQueued() -> [URL] {
        guard audioQueue.count != 0 else { return [] }
        
        let urls = audioQueue.map { item in
            return item.url
        }
        
        audioQueue = []
        return urls
    }
    
    func handleStopStreamingAudio() {
        delegate?.clearEngine()
        AudioClockDirector.shared.resetCache()
    }
}

//MARK:- Used by outside world including:
// SPP, lock screen, directors
extension SAPlayerPresenter {

    func handleTogglePlayingAndPausing() {
        if isPlaying == .playing {
            handlePause()
        } else if isPlaying == .paused {
            handlePlay()
        }
    }

    func handleAudioRateChanged(rate: Float) {
        delegate?.updateLockScreenChangePlaybackRate(speed: rate)
    }
    
    func handleScrubbingIntervalsChanged() {
        delegate?.updateLockScreenSkipIntervals()
    }
}

//MARK:- For lock screen
extension SAPlayerPresenter : LockScreenViewPresenter {
    
    func getIsPlaying() -> Bool {
        return isPlaying == .playing
    }

    func handlePlay() {
        delegate?.playEngine()
        self.delegate?.updateLockScreenPlaying()
    }

    func handlePause() {
        delegate?.pauseEngine()
        self.delegate?.updateLockScreenPaused()
    }

    func handleSkipBackward() {
        guard let backward = delegate?.skipForwardSeconds else { return }
        handleSeek(toNeedle: (needle ?? 0) - backward)
    }
    
    func handleSkipForward() {
        guard let forward = delegate?.skipForwardSeconds else { return }
        handleSeek(toNeedle: (needle ?? 0) + forward)
    }

    func handleSeek(toNeedle needle: Needle) {
        delegate?.seekEngine(toNeedle: needle)
    }
}

//MARK:- AVAudioEngineDelegate
extension SAPlayerPresenter: AudioEngineDelegate {
    func didError() {
        Log.monitor("We should have handled engine error")
    }
}

//MARK:- Autoplay
extension SAPlayerPresenter {
    #if os(iOS)
    /// Ends the play-next background task and any readiness subscriptions.
    /// 8.0.10 began a UIBackgroundTask but ended it immediately after starting the stream —
    /// iOS then suspends before remote buffering completes when the device is locked.
    private func endPlayNextBackgroundWork(reason: String) {
        if let id = playNextPlayingSubscriptionId {
            AudioClockDirector.shared.detachFromChangesInPlayingStatus(withID: id)
            playNextPlayingSubscriptionId = nil
        }
        if let id = playNextBufferSubscriptionId {
            AudioClockDirector.shared.detachFromChangesInBufferedRange(withID: id)
            playNextBufferSubscriptionId = nil
        }
        playNextTimeoutWorkItem?.cancel()
        playNextTimeoutWorkItem = nil

        guard playNextBackgroundTask != .invalid else { return }
        Log.info("Ending SAPlayer.PlayNextTrack background work: \(reason)")
        UIApplication.shared.endBackgroundTask(playNextBackgroundTask)
        playNextBackgroundTask = .invalid
    }

    private func beginPlayNextBackgroundHold() {
        endPlayNextBackgroundWork(reason: "superseded by new play-next")

        playNextBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SAPlayer.PlayNextTrack") { [weak self] in
            Log.warn("Background task for playing next track expired.")
            self?.endPlayNextBackgroundWork(reason: "expired")
        }

        // Prefer PlayingStatus.playing; also accept buffer-ready so we do not hold forever
        // if play() is delayed after the stream becomes playable.
        playNextPlayingSubscriptionId = AudioClockDirector.shared.attachToChangesInPlayingStatus(closure: { [weak self] status in
            guard let self = self else { throw DirectorError.closureIsDead }
            if status == .playing {
                self.endPlayNextBackgroundWork(reason: "playing")
            }
        })

        playNextBufferSubscriptionId = AudioClockDirector.shared.attachToChangesInBufferedRange(closure: { [weak self] buffer in
            guard let self = self else { throw DirectorError.closureIsDead }
            if buffer.isReadyForPlaying {
                self.endPlayNextBackgroundWork(reason: "buffer-ready")
            }
        })

        let timeout = DispatchWorkItem { [weak self] in
            self?.endPlayNextBackgroundWork(reason: "timeout-\(Int(self?.playNextBackgroundTimeoutSeconds ?? 30))s")
        }
        playNextTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + playNextBackgroundTimeoutSeconds, execute: timeout)
    }
    #endif

    func playNextAudioIfExists() {
        Log.info("looking foor next audio in queue to play")
        guard audioQueue.count > 0 else {
            Log.info("no queued audio")
            return
        }

        #if os(iOS)
        beginPlayNextBackgroundHold()
        #endif

        let nextAudioURL = audioQueue.removeFirst()

        Log.info("getting ready to play \(nextAudioURL)")
        AudioQueueDirector.shared.changeInQueue(url: nextAudioURL.url)
        
        handleClear()
        
        delegate?.mediaInfo = nextAudioURL.mediaInfo
        
        switch nextAudioURL.loc {
        case .remote:
            handlePlayStreamedAudio(withRemoteUrl: nextAudioURL.url, bitrate: nextAudioURL.bitrate)
            break
        case .saved:
            handlePlaySavedAudio(withSavedUrl: nextAudioURL.url)
            break
        }
        
        shouldPlayImmediately = true
        // Do not end the iOS background task here — wait for playing / buffer-ready / timeout / expire.
    }
}
