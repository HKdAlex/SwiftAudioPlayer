//
//  AudioStreamWorker.swift
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

/**
 init task
 +
 |
 |
 +-----v-----+     suspend()   +---------+          +-----------+
 | suspended <-----------------> running +----------> completed |
 +-----+-----+     resume()    +----+----+          +-----------+
 |                            |
 |                            | cancel()
 |                            |
 |          cancel()   +------v------+
 +---------------------> cancelling  |
 +-------------+
 */

protocol AudioDataStreamable {
    //if user taps download then starts to stream
    init(progressCallback: @escaping (_ id: ID, _ dto: StreamProgressDTO) -> (), doneCallback: @escaping (_ id: ID, _ error: Error?)->Bool) //Bool is should save or not
    
    var HTTPHeaderFields: [String: String]? { get set }
    
    func start(withID id: ID, withRemoteURL url: URL, withInitialData data: Data?, andTotalBytesExpectedPreviously previousTotalBytesExpected: Int64?)
    func pause(withId id: ID)
    func resume(withId id: ID)
    func stop(withId id: ID)//FIXME: with persistent play we should return a Data so that download can resume
    func seek(withId id: ID, withByteOffset offset: UInt64)
    func getRunningID() -> ID?
}

///Policy for streaming
///- only one stream at a time
///- starting a stream will cancel the previous
///- when seeking, assume that previous data is discarded
class AudioStreamWorker:NSObject, AudioDataStreamable {
    private let TIMEOUT = 60.0
    
    fileprivate let progressCallback: (_ id: ID, _ dto: StreamProgressDTO) -> ()
    //Will ony be called when the task object will no longer be active
    //Why? So upper layer knows that current streaming activity for this ID is done
    //Why? To know if we should persist the stream data assuming successful completion
    fileprivate let doneCallback: (_ id: ID, _ error: Error?) -> Bool
    private var session: URLSession!
    
    var HTTPHeaderFields: [String: String]?
    
    private var id: ID?
    private var url: URL?
    private var task: URLSessionDataTask?
    private var previousTotalBytesExpectedFromInitalData: Int64?
    private var initialDataBytesCount: Int64 = 0
    fileprivate var totalBytesExpectedForWholeFile: Int64?
    fileprivate var totalBytesExpectedForCurrentStream: Int64?
    fileprivate var totalBytesReceived: Int64 = 0
    private var corruptedBecauseOfSeek = false
    /// Absolute file byte where the current Range request started (0 for full GET).
    private var streamRangeStartByte: UInt64 = 0
    /// Skip doneCallback when we cancel the task ourselves to retry after a drop.
    private var isRecoveringFromNetworkLoss = false
    private var networkRecoveryAttempts = 0
    private let maxNetworkRecoveryAttempts = 5
    private var networkRecoveryWorkItem: DispatchWorkItem?
    
    
    /// Init
    ///
    /// - Parameters:
    ///   - progressCallback: generic callback
    ///   - doneCallback: when finished
    required init(progressCallback: @escaping (_ id: ID, _ dto: StreamProgressDTO) -> (), doneCallback: @escaping (_ id: ID, _ error: Error?) -> Bool) {
        self.progressCallback = progressCallback
        self.doneCallback = doneCallback
        super.init()
        
        let config = URLSessionConfiguration.background(withIdentifier: "SwiftAudioPlayer.stream")
        // Specifies that the phone should keep trying till it receives connection instead of dropping immediately
        if #available(iOS 11.0, tvOS 11.0, *) {
            config.waitsForConnectivity = true
        }
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil) //TODO: should we use ephemeral
    }
    
    func start(withID id: ID, withRemoteURL url: URL, withInitialData data: Data? = nil, andTotalBytesExpectedPreviously previousTotalBytesExpected: Int64? = nil) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id) initialData: \(data?.count ?? 0)")
        
        killPreviousTaskIfNeeded()
        self.id = id
        self.url = url
        self.previousTotalBytesExpectedFromInitalData = previousTotalBytesExpected
        self.networkRecoveryAttempts = 0
        self.isRecoveringFromNetworkLoss = false
        
        if let data = data {
            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: TIMEOUT)
            HTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            request.addValue("bytes=\(data.count)-", forHTTPHeaderField: "Range")
            task = session.dataTask(with: request)
            task?.taskDescription = id
            
            initialDataBytesCount = Int64(data.count)
            streamRangeStartByte = UInt64(data.count)
            // Bytes already in hand are not part of this Range body; track absolute via range start + received.
            totalBytesReceived = 0
            totalBytesExpectedForWholeFile = previousTotalBytesExpected
            
            let progress = previousTotalBytesExpected != nil ? Double(initialDataBytesCount)/Double(previousTotalBytesExpected!) : 0
            
            let dto = StreamProgressDTO(progress: progress, data: data, totalBytesExpected: totalBytesExpectedForWholeFile)
            
            progressCallback(id, dto)
            
            task?.resume()
        } else {
            streamRangeStartByte = 0
            var request = URLRequest(url: url)
            HTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            task = session.dataTask(with: request)
            task?.taskDescription = id
            task?.resume()
        }
    }
    
    private func killPreviousTaskIfNeeded() {
        networkRecoveryWorkItem?.cancel()
        networkRecoveryWorkItem = nil
        guard let task = task else {return}
        if task.state == .running || task.state == .suspended {
            task.cancel()
        }
        self.task = nil
        corruptedBecauseOfSeek = false
        totalBytesExpectedForWholeFile = nil
        totalBytesReceived = 0
        initialDataBytesCount = 0
        streamRangeStartByte = 0
        isRecoveringFromNetworkLoss = false
        networkRecoveryAttempts = 0
    }

    /// Absolute byte offset already obtained for the current URL (for Range resume).
    private var absoluteBytesReceived: UInt64 {
        return streamRangeStartByte + UInt64(max(0, totalBytesReceived))
    }

    private func isTransientNetworkError(_ err: NSError) -> Bool {
        guard err.domain == NSURLErrorDomain else { return false }
        switch err.code {
        case NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed,
             NSURLErrorCannotFindHost:
            return true
        default:
            return false
        }
    }

    /// Restart the Range request from the last absolute byte without treating cancel as stream end.
    private func scheduleNetworkRecovery(id: ID, after error: NSError) {
        guard networkRecoveryAttempts < maxNetworkRecoveryAttempts else {
            Log.error("network recovery exhausted after \(maxNetworkRecoveryAttempts) attempts — surfacing error")
            isRecoveringFromNetworkLoss = false
            let _ = doneCallback(id, error)
            return
        }
        networkRecoveryAttempts += 1
        let delay = min(8.0, pow(2.0, Double(networkRecoveryAttempts - 1)) * 0.5)
        let offset = absoluteBytesReceived
        Log.warn("transient network error (\(error.code)) — recovery attempt \(networkRecoveryAttempts)/\(maxNetworkRecoveryAttempts) from byte \(offset) in \(delay)s")

        isRecoveringFromNetworkLoss = true
        if let task = task, task.state == .running || task.state == .suspended {
            task.cancel()
        }
        self.task = nil

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.id == id, let url = self.url else { return }
            self.startRangedStream(id: id, url: url, fromByte: offset, announceEmptyProgress: false)
            self.isRecoveringFromNetworkLoss = false
        }
        networkRecoveryWorkItem?.cancel()
        networkRecoveryWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startRangedStream(id: ID, url: URL, fromByte offset: UInt64, announceEmptyProgress: Bool) {
        streamRangeStartByte = offset
        totalBytesReceived = 0
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: TIMEOUT)
        HTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if offset > 0 {
            request.addValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        task = session.dataTask(with: request)
        task?.taskDescription = id
        if announceEmptyProgress {
            progressCallback(id, StreamProgressDTO(progress: 0, data: Data(), totalBytesExpected: totalBytesExpectedForWholeFile))
        }
        task?.resume()
    }
    
    func pause(withId id: ID) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id)")
        guard self.id == id else {
            Log.error("incorrect ID for command")
            return
        }
        
        guard let task = task else {
            Log.error("tried to stop a non-existent task")
            return
        }
        
        if task.state == .running {
            task.suspend()
        } else {
            Log.monitor("tried to pause a task that's already suspended")
        }
    }
    
    func resume(withId id: ID) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id)")
        guard self.id == id else {
            Log.error("incorrect ID for command")
            return
        }
        
        guard let task = task else {
            Log.error("tried to resume a non-existent task")
            return
        }
        
        if task.state == .suspended {
            task.resume()
        } else {
            Log.monitor("tried to resume a non-suspended task")
        }
    }
    
    func stop(withId id: ID) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id)")
        guard self.id == id else {
            Log.warn("incorrect ID for command")
            return
        }
        
        guard let task = task else {
            Log.error("tried to stop a non-existent task")
            return
        }
        
        
        if task.state == .running || task.state == .suspended {
            task.cancel()
            self.task = nil
        } else {
            Log.error("stream_error tried to stop a task that's in state: \(task.state.rawValue)")
            
        }
    }
    
    func seek(withId id: ID, withByteOffset offset: UInt64) {
        Log.info("selfID: \(self.id ?? "none"), paramID: \(id), offset: \(offset)")
        guard self.id == id else {
            Log.error("incorrect ID for command")
            return
        }
        
        guard let url = url else {
            Log.monitor("tried to seek without having URL")
            return
        }
        networkRecoveryWorkItem?.cancel()
        networkRecoveryWorkItem = nil
        networkRecoveryAttempts = 0
        isRecoveringFromNetworkLoss = true
        stop(withId: id)
        corruptedBecauseOfSeek = true
        isRecoveringFromNetworkLoss = false
        startRangedStream(id: id, url: url, fromByte: offset, announceEmptyProgress: true)
    }
    
    
    func getRunningID() -> ID? {
        if let task = task, task.state == .running, let id = id {
            return id
        }
        return nil
    }
}


//MARK:- URLSessionDataDelegate
extension AudioStreamWorker: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Log.debug("selfID: ", id, " dataTaskID: ", dataTask.taskDescription, " dataSize: ", data.count, " expected: ", totalBytesExpectedForWholeFile, " received: ", totalBytesReceived)
        guard let id = id else {
            //FIXME: should be an error when done with testing phase
            Log.monitor("stream worker in weird state 9847467")
            return
        }
        
        guard self.task == dataTask else {
            Log.error("stream_error not the same task 638283") //Probably because of seek
            return
        }
        
        guard var totalBytesExpected = totalBytesExpectedForCurrentStream else {
            Log.monitor("should not be called 223r2")
            return
        }
        
        if totalBytesExpected <= 0 {
            totalBytesExpected = totalBytesReceived
        }
        
        totalBytesReceived = totalBytesReceived + Int64(data.count)
        let absoluteReceived = Int64(self.absoluteBytesReceived)
        let progressBase = totalBytesExpectedForWholeFile ?? totalBytesExpected
        let progress = progressBase > 0 ? Double(absoluteReceived)/Double(progressBase) : 0
        
        Log.debug("network streaming progress \(progress)")
        self.progressCallback(id, StreamProgressDTO(progress: progress, data: data, totalBytesExpected: totalBytesExpectedForWholeFile ?? totalBytesExpected))
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Log.debug(dataTask.taskDescription, id, response.description)
        guard id != nil else {
            Log.monitor("stream worker in weird state 2049jg3")
            return
        }
        
        guard self.task == dataTask else {
            Log.error("stream_error not the same task 517253")
            return
        }
        
        Log.info("response length: \(response.expectedContentLength)")
        
        //the value will smaller if you seek. But we want to hold the OG total for duration calculations
        if !corruptedBecauseOfSeek {
            totalBytesExpectedForWholeFile = response.expectedContentLength + initialDataBytesCount
        }
        
        totalBytesExpectedForCurrentStream = response.expectedContentLength
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Log.debug(task.taskDescription, id)
        guard let id = id else {
            Log.error("stream_error stream worker in weird state 345b45")
            return
        }
        
        if self.task != task && self.task != nil {
            Log.error("stream_error not the same task 3901833")
            return
        }
        
        if let err: NSError = error as NSError? {
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                if isRecoveringFromNetworkLoss {
                    Log.info("cancelled stream task for network recovery — not completing stream")
                    return
                }
                Log.info("cancelled downloading")
                let _ = doneCallback(id, nil)
                return
            }
            
            if isTransientNetworkError(err) {
                // Previously called doneCallback(id, nil) on connection lost — silent stall (upstream #158/#186).
                scheduleNetworkRecovery(id: id, after: err)
                return
            }
            
            Log.monitor("\(task.currentRequest?.url?.absoluteString ?? "nil url") error: \(err.localizedDescription)")
            
            let _ = doneCallback(id, err)
            return
        }
        
        networkRecoveryAttempts = 0
        let shouldSave = doneCallback(id, nil)
        if shouldSave && !corruptedBecauseOfSeek {
            // TODO want to save file after streaming so we do not have to download again
//            guard (task.response?.suggestedFilename?.pathExtension) != nil else {
//                Log.monitor("Could not determine file type for file from id: \(task.taskDescription ?? "nil") and url: \(task.currentRequest?.url?.absoluteString ?? "nil")")
//                return
//            }
            
            // TODO no longer saving streamed files
            //            FileStorage.Audio.write(id, fileExtension: fileType, data: data)
        }
    }
    
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        // TODO: Notify to user that waiting for better connection
    }
}
