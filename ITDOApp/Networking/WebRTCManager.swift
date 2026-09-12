import Foundation
import CallKit
import PushKit
import AVFoundation
import ReplayKit

// WebRTC импортируется только если фреймворк добавлен в проект.
// Без него менеджер работает как заглушка — сигналинг работает,
// но peer-to-peer аудио/видео не подключается.
#if canImport(WebRTC)
import WebRTC
#endif

/// Менеджер WebRTC звонков.
/// Сигналинг — через WebSocket (WSClient), в реальном времени, так же как в веб-версии
/// (offer/answer/ICE-кандидаты доставляются пушем через `call_signal`, а не поллингом).
/// Если WS недоступен на момент звонка — используется REST-поллинг (calls/poll.php) как fallback.
final class WebRTCManager: NSObject, ObservableObject {
    static let shared = WebRTCManager()
    
    @Published var callState: CallState = .idle
    @Published var callId: Int?
    @Published var callType: String = "audio"
    @Published var isMuted = false
    @Published var isSpeakerOn = false
    @Published var isFrontCamera = true
    @Published var isSharingScreen = false
    @Published var callDuration: Int = 0
    
    #if canImport(WebRTC)
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    #endif
    
    private var pollTask: Task<Void, Never>?
    private var lastSignalId = 0
    private var durationTimer: Timer?
    private var connectedAt: Date?
    private let callKitProvider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    private var pendingStartContinuation: CheckedContinuation<Int, Error>?
    
    // MARK: - Тоны звонка (аналог WebAudio-тонов в вебе: ringback 425Hz, connected 880Hz, ended 660/440Hz)
    private var toneEngine: AVAudioEngine?
    private var tonePlayer: AVAudioPlayerNode?
    private var ringbackTimer: Timer?
    private var incomingRingtoneTimer: Timer?
    
    #if canImport(WebRTC)
    private var peerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var cameraVideoSource: RTCVideoSource?
    private var cameraVideoTrack: RTCVideoTrack?      // исходная камера — восстанавливается после шаринга экрана
    private var videoCapturer: RTCCameraVideoCapturer?
    private var screenVideoSource: RTCVideoSource?
    private var screenVideoTrack: RTCVideoTrack?
    private var bitrateMonitor: Timer?
    
    /// Полный список ICE-серверов — идентичен RTC_CONFIG из веб-версии (app.js):
    /// свой STUN/TURN (UDP/TCP/TLS) + публичный STUN Google + резервный TURN openrelay.
    private let iceServers = [
        RTCIceServer(urlStrings: ["stun:webrtc.bleyzos.ru:3478"]),
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        RTCIceServer(urlStrings: ["turn:webrtc.bleyzos.ru:3478"],
                      username: "itdo_30ed1d",
                      credential: "QVrYlh6en2ZgTA8lPmi1lyzVsgTSjQUI"),
        RTCIceServer(urlStrings: ["turn:webrtc.bleyzos.ru:3478?transport=tcp"],
                      username: "itdo_30ed1d",
                      credential: "QVrYlh6en2ZgTA8lPmi1lyzVsgTSjQUI"),
        RTCIceServer(urlStrings: ["turns:webrtc.bleyzos.ru:5349?transport=tcp"],
                      username: "itdo_30ed1d",
                      credential: "QVrYlh6en2ZgTA8lPmi1lyzVsgTSjQUI"),
        RTCIceServer(urlStrings: ["turn:openrelay.metered.ca:443?transport=tcp"],
                      username: "openrelayproject",
                      credential: "openrelayproject"),
    ]
    #endif
    
    enum CallState: Equatable {
        case idle
        case outgoingRinging
        case incomingRinging(callId: Int, callerName: String, type: String)
        case connecting
        case connected
        case ended(reason: String)
    }
    
    private var pushRegistry: PKPushRegistry?

    override init() {
        let config = CXProviderConfiguration(localizedName: "ITDO")
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.iconTemplateImageData = nil // можно добавить иконку
        config.ringtoneSound = "ringtone.caf" // кастомный рингтон
        callKitProvider = CXProvider(configuration: config)
        super.init()
        callKitProvider.setDelegate(self, queue: .main)

        // Регистрируем PushKit для VoIP push-уведомлений
        pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry?.delegate = self
        pushRegistry?.desiredPushTypes = [.voIP]
        
        wireWSHandlers()
    }
    
    // MARK: - WebSocket сигналинг (реалтайм, как в вебе — вместо REST-поллинга)
    
    private func wireWSHandlers() {
        WSClient.shared.onIncomingCall = { [weak self] callId, callerName, type in
            guard let self, self.callState == .idle else { return }
            self.callId = callId
            self.callType = type
            self.callState = .incomingRinging(callId: callId, callerName: callerName, type: type)
            self.playRingtoneLocally()
        }
        
        WSClient.shared.onCallStarted = { [weak self] callId, _ in
            self?.pendingStartContinuation?.resume(returning: callId)
            self?.pendingStartContinuation = nil
        }
        
        WSClient.shared.onCallAnswered = { [weak self] callId, response in
            guard let self, self.callId == callId else { return }
            if response == "decline" {
                self.stopRingbackTone()
                self.callState = .ended(reason: "declined")
                self.cleanup()
            }
            // "accept" — соединение подтвердится через приход первого валидного answer/connectionState
        }
        
        WSClient.shared.onCallSignal = { [weak self] callId, kind, payload in
            guard let self, self.callId == callId else { return }
            let signalPayload = SignalPayload(
                type: payload["type"] as? String,
                sdp: payload["sdp"] as? String,
                candidate: payload["candidate"] as? String,
                sdpMLineIndex: (payload["sdpMLineIndex"] as? Int) ?? (payload["sdpMLineIndex"] as? NSNumber)?.intValue,
                sdpMid: payload["sdpMid"] as? String
            )
            Task { await self.handleSignal(kind: kind, payload: signalPayload) }
        }
        
        WSClient.shared.onCallEnded = { [weak self] callId, status in
            guard let self, self.callId == callId else { return }
            self.stopRingbackTone()
            self.playEndedTone()
            self.callState = .ended(reason: status)
            self.cleanup()
        }
    }
    
    // MARK: - Start outgoing call
    
    func startCall(convId: Int, type: String = "audio") {
        guard callState == .idle else { return }
        self.callType = type
        
        Task<Void, Never> {
            do {
                let resp: Int
                if WSClient.shared.isConnected {
                    // Реалтайм-старт через WS, аналогично startCall() в app.js
                    resp = try await withCheckedThrowingContinuation { cont in
                        self.pendingStartContinuation = cont
                        WSClient.shared.sendCallStart(convId: convId, type: type)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            if let c = self.pendingStartContinuation {
                                self.pendingStartContinuation = nil
                                c.resume(throwing: URLError(.timedOut))
                            }
                        }
                    }
                } else {
                    struct CallResp: Decodable {
                        let callId: Int
                        let existing: Bool?
                        enum CodingKeys: String, CodingKey { case callId = "call_id"; case existing }
                    }
                    let r: CallResp = try await APIClient.shared.request(
                        "calls/start.php", method: .post,
                        body: ["conv_id": AnyEncodable(convId), "type": AnyEncodable(type)]
                    )
                    resp = r.callId
                }
                
                self.callId = resp
                self.callState = .outgoingRinging
                
                let uuid = UUID()
                self.currentCallUUID = uuid
                
                // Для исходящего звонка НЕ reportNewIncomingCall
                // CallKit сам покажет UI когда callee ответит
                
                startRingbackTone()
                if !WSClient.shared.isConnected { startPolling() }
                setupPeerConnectionAndOffer(callId: resp)
            } catch {
                await MainActor.run { self.callState = .ended(reason: error.localizedDescription) }
                cleanup()
            }
        }
    }
    
    // MARK: - Accept incoming call
    
    func acceptCall(callId: Int) {
        guard case .incomingRinging = callState else { return }
        stopIncomingRingtone()
        self.callId = callId
        self.callState = .connecting
        
        Task {
            do {
                if WSClient.shared.isConnected {
                    WSClient.shared.sendCallAnswer(callId: callId, response: "accept")
                } else {
                    try await APIClient.shared.answerCall(callId: callId)
                }
                if let uuid = currentCallUUID {
                    let action = CXAnswerCallAction(call: uuid)
                    callController.request(CXTransaction(action: action)) { _ in }
                }
                if !WSClient.shared.isConnected { startPolling() }
                setupPeerConnectionAsCallee(callId: callId)
            } catch {
                await MainActor.run { self.callState = .ended(reason: "Не удалось ответить") }
                cleanup()
            }
        }
    }
    
    // MARK: - Decline / End
    
    func declineCall(callId: Int) {
        if WSClient.shared.isConnected {
            WSClient.shared.sendCallAnswer(callId: callId, response: "decline")
        } else {
            Task { try? await APIClient.shared.answerCallDecline(callId: callId) }
        }
        if let uuid = currentCallUUID {
            callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in }
        }
        callState = .ended(reason: "declined")
        cleanup()
    }
    
    func endCall() {
        guard let callId else { callState = .idle; return }
        if WSClient.shared.isConnected {
            WSClient.shared.sendCallEnd(callId: callId)
        } else {
            Task { try? await APIClient.shared.endCall(callId: callId) }
        }
        if let uuid = currentCallUUID {
            callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in }
        }
        playEndedTone()
        callState = .ended(reason: "ended")
        cleanup()
    }
    
    // MARK: - Controls
    
    func toggleMute() {
        isMuted.toggle()
        #if canImport(WebRTC)
        localAudioTrack?.isEnabled = !isMuted
        #endif
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        #if canImport(WebRTC)
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        do {
            try session.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
            try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        } catch {}
        session.unlockForConfiguration()
        #endif
    }
    
    func toggleCamera() {
        guard !isSharingScreen else { return } // как в вебе — флип камеры недоступен во время шаринга экрана
        isFrontCamera.toggle()
        #if canImport(WebRTC)
        if let capturer = videoCapturer {
            guard let device = cameraDevice(front: isFrontCamera) else { return }
            capturer.stopCapture {
                capturer.startCapture(with: device, format: self.videoFormat(for: device), fps: 30)
            }
        }
        #endif
    }
    
    // MARK: - Демонстрация экрана (аналог getDisplayMedia в вебе, через ReplayKit in-app capture)
    
    func toggleScreenShare() {
        guard callType == "video" else { return }
        if isSharingScreen {
            stopScreenShare()
        } else {
            startScreenShare()
        }
    }
    
    private func startScreenShare() {
        #if canImport(WebRTC)
        guard let pc = peerConnection else { return }
        let source = WebRTC.RTCVideoSource()
        screenVideoSource = source
        let track = Self.factory.videoTrack(with: source, trackId: "screen0")
        screenVideoTrack = track
        
        RPScreenRecorder.shared().startCapture(handler: { [weak self] sampleBuffer, bufferType, _ in
            guard let self, bufferType == .video,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000
            let frame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: Int64(timeStampNs))
            self.screenVideoSource?.capturer(self.videoCapturer ?? RTCVideoCapturer(), didCapture: frame)
        }, completionHandler: { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    print("[ScreenShare] start error: \(error)")
                    return
                }
                // Заменяем видеотрек в сендере на трек экрана, локальное превью — тоже экран
                if let sender = pc.senders.first(where: { $0.track?.kind == "video" }) {
                    sender.track = track
                }
                self.localVideoTrack = track
                self.isSharingScreen = true
            }
        })
        #endif
    }
    
    private func stopScreenShare() {
        #if canImport(WebRTC)
        RPScreenRecorder.shared().stopCapture { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if let pc = self.peerConnection,
                   let sender = pc.senders.first(where: { $0.track?.kind == "video" }) {
                    sender.track = self.cameraVideoTrack
                }
                self.localVideoTrack = self.cameraVideoTrack
                self.screenVideoTrack = nil
                self.screenVideoSource = nil
                self.isSharingScreen = false
            }
        }
        #endif
    }
    
    // MARK: - Peer connection setup
    
    private func setupPeerConnectionAndOffer(callId: Int) {
        #if canImport(WebRTC)
        guard let pc = createPeerConnection() else { return }
        peerConnection = pc
        addAudioTrack(to: pc)
        if callType == "video" { addVideoTrack(to: pc) }
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true",
                                   "OfferToReceiveVideo": callType == "video" ? "true" : "false"],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { [weak self] sdp, _ in
            guard let self, let sdp else { return }
            pc.setLocalDescription(sdp) { _ in
                Task {
                    try? await self.sendSignal(callId: callId, kind: "offer",
                                                payload: ["type": sdp.type.rawValue, "sdp": sdp.sdp])
                }
            }
        }
        #endif
    }
    
    private func setupPeerConnectionAsCallee(callId: Int) {
        #if canImport(WebRTC)
        guard let pc = createPeerConnection() else { return }
        peerConnection = pc
        addAudioTrack(to: pc)
        if callType == "video" { addVideoTrack(to: pc) }
        #endif
    }
    
    #if canImport(WebRTC)
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()
    
    private func createPeerConnection() -> RTCPeerConnection? {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                               optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        return pc
    }
    
    private func addAudioTrack(to pc: RTCPeerConnection) {
        let source = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = Self.factory.audioTrack(with: source, trackId: "audio0")
        localAudioTrack = track
        pc.add(track, streamIds: ["ARDAMS"])
        // Битрейт аудио — как в вебе (128kbps)
        if let sender = pc.senders.first(where: { $0.track?.kind == "audio" }) {
            let params = sender.parameters
            if !params.encodings.isEmpty {
                params.encodings[0].maxBitrateBps = NSNumber(value: 128_000)
                sender.parameters = params
            }
        }
    }
    
    private func addVideoTrack(to pc: RTCPeerConnection) {
        guard let device = cameraDevice(front: isFrontCamera) else { return }
        let source = Self.factory.videoSource()
        cameraVideoSource = source
        let capturer = RTCCameraVideoCapturer(delegate: source)
        videoCapturer = capturer
        let track = Self.factory.videoTrack(with: source, trackId: "video0")
        cameraVideoTrack = track
        localVideoTrack = track
        pc.add(track, streamIds: ["ARDAMS"])
        capturer.startCapture(with: device, format: videoFormat(for: device), fps: 30)
        
        // Начальный видео-битрейт 2Mbps, дальше адаптируется adjustBitrate — как в вебе
        if let sender = pc.senders.first(where: { $0.track?.kind == "video" }) {
            let params = sender.parameters
            if !params.encodings.isEmpty {
                params.encodings[0].maxBitrateBps = NSNumber(value: 2_000_000)
                sender.parameters = params
            }
            bitrateMonitor?.invalidate()
            bitrateMonitor = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.adjustBitrate()
            }
        }
    }
    
    /// Порт логики adjustBitrate() из app.js: подстраивает видео-битрейт по packet loss / jitter.
    private func adjustBitrate() {
        guard let pc = peerConnection, callType == "video" else { return }
        pc.statistics { [weak self] report in
            guard let self else { return }
            var targetBitrate: Double = 2_000_000
            var hasIssues = false
            
            for (_, stat) in report.statistics {
                guard stat.type == "inbound-rtp",
                      (stat.values["kind"] as? String) == "video" else { continue }
                let lost = (stat.values["packetsLost"] as? NSNumber)?.doubleValue ?? 0
                let received = (stat.values["packetsReceived"] as? NSNumber)?.doubleValue ?? 0
                let jitter = (stat.values["jitter"] as? NSNumber)?.doubleValue ?? 0
                let lossRate = (received + lost) > 0 ? lost / (received + lost) : 0
                if lossRate > 0.05 {
                    targetBitrate = max(500_000, targetBitrate * 0.7)
                    hasIssues = true
                } else if jitter > 0.1 {
                    targetBitrate = max(800_000, targetBitrate * 0.85)
                    hasIssues = true
                }
            }
            for (_, stat) in report.statistics {
                guard stat.type == "outbound-rtp",
                      (stat.values["kind"] as? String) == "video" else { continue }
                let framesSent = (stat.values["framesSent"] as? NSNumber)?.doubleValue ?? 0
                if !hasIssues && framesSent > 100 {
                    targetBitrate = min(3_000_000, targetBitrate * 1.05)
                }
            }
            
            DispatchQueue.main.async {
                guard let sender = pc.senders.first(where: { $0.track?.kind == "video" }) else { return }
                let params = sender.parameters
                guard !params.encodings.isEmpty else { return }
                let old = params.encodings[0].maxBitrateBps?.doubleValue ?? targetBitrate
                if abs(targetBitrate - old) / max(old, 1) > 0.1 {
                    params.encodings[0].maxBitrateBps = NSNumber(value: targetBitrate)
                    sender.parameters = params
                }
            }
        }
    }
    
    private func cameraDevice(front: Bool) -> AVCaptureDevice? {
        RTCCameraVideoCapturer.captureDevices().first { $0.position == (front ? .front : .back) }
    }
    
    private func videoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        return formats.first { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 1280 } ?? formats.first!
    }
    #endif
    
    // MARK: - Signaling
    
    private func sendSignal(callId: Int, kind: String, payload: [String: Any]) async throws {
        if WSClient.shared.isConnected {
            WSClient.shared.sendCallSignal(callId: callId, kind: kind, payload: payload)
            return
        }
        struct SignalBody: Encodable {
            let call_id: Int
            let kind: String
            let payload: [String: Any]
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(call_id, forKey: .call_id)
                try c.encode(kind, forKey: .kind)
                // Кодируем payload вручную
                let data = try JSONSerialization.data(withJSONObject: payload)
                let json = try JSONSerialization.jsonObject(with: data)
                try c.encode(AnyCodable(json), forKey: .payload)
            }
            enum CodingKeys: String, CodingKey { case call_id, kind, payload }
        }
        try await APIClient.shared.requestVoid(
            "calls/signal.php", method: .post,
            body: SignalBody(call_id: callId, kind: kind, payload: payload)
        )
    }
    
    /// Fallback-поллинг: используется только если WS недоступен на момент звонка.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let callId else { return }
                do {
                    struct SignalResp: Decodable {
                        let id: Int; let kind: String; let payload: SignalPayload?
                    }
                    struct PollResp: Decodable { let call: CallStatus; let signals: [SignalResp] }
                    struct CallStatus: Decodable { let id: Int; let status: String }
                    
                    let resp: PollResp = try await APIClient.shared.request(
                        "calls/poll.php",
                        query: ["call_id": "\(callId)", "since_id": "\(self.lastSignalId)"]
                    )
                    for signal in resp.signals {
                        self.lastSignalId = max(self.lastSignalId, signal.id)
                        await self.handleSignal(kind: signal.kind, payload: signal.payload)
                    }
                    if ["ended", "declined", "missed"].contains(resp.call.status) {
                        await MainActor.run { self.callState = .ended(reason: resp.call.status) }
                        self.cleanup(); return
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    
    private func handleSignal(kind: String, payload: SignalPayload?) async {
        #if canImport(WebRTC)
        guard let pc = peerConnection else { return }
        switch kind {
        case "offer":
            guard let sdpString = payload?.sdp else { return }
            let sdp = RTCSessionDescription(type: .offer, sdp: sdpString)
            do {
                try await pc.setRemoteDescription(sdp)
                let constraints = RTCMediaConstraints(
                    mandatoryConstraints: ["OfferToReceiveAudio": "true",
                                           "OfferToReceiveVideo": callType == "video" ? "true" : "false"],
                    optionalConstraints: nil
                )
                pc.answer(for: constraints) { [weak self] answerSdp, _ in
                    guard let self, let answerSdp else { return }
                    pc.setLocalDescription(answerSdp) { _ in
                        Task {
                            try? await self.sendSignal(callId: self.callId ?? 0, kind: "answer",
                                                        payload: ["type": answerSdp.type.rawValue, "sdp": answerSdp.sdp])
                        }
                    }
                }
            } catch {}
        case "answer":
            guard let sdpString = payload?.sdp else { return }
            try? await pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdpString))
            await MainActor.run {
                if self.callState != .connected {
                    self.stopRingbackTone()
                    self.callState = .connected
                    self.startDurationTimer()
                    self.playConnectedTone()
                }
            }
        case "candidate":
            guard let candidateString = payload?.candidate else { return }
            let candidate = RTCIceCandidate(sdp: candidateString,
                                             sdpMLineIndex: Int32(payload?.sdpMLineIndex ?? 0),
                                             sdpMid: payload?.sdpMid ?? "0")
            pc.add(candidate) { _ in }
        default: break
        }
        #endif
    }
    
    // MARK: - Duration
    
    private func startDurationTimer() {
        connectedAt = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.connectedAt else { return }
            self.callDuration = Int(Date().timeIntervalSince(start))
        }
    }
    
    // MARK: - Тоны звонка (порт логики playCallTone/startRingbackTone/playCallConnectedTone/playCallEndedTone из app.js)
    
    private func ensureToneEngine() -> (AVAudioEngine, AVAudioPlayerNode)? {
        if let engine = toneEngine, let player = tonePlayer { return (engine, player) }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        do {
            try engine.start()
        } catch {
            return nil
        }
        toneEngine = engine
        tonePlayer = player
        return (engine, player)
    }
    
    private func playTone(frequency: Double, duration: Double, gain: Float) {
        guard let (engine, player) = ensureToneEngine() else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let channels = buffer.floatChannelData
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let sample = Float(sin(2.0 * .pi * frequency * t)) * gain
            for ch in 0..<Int(buffer.format.channelCount) {
                channels?[ch][frame] = sample
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
    
    /// 425Hz двойной гудок каждые 4с — как ringback в вебе
    private func startRingbackTone() {
        stopRingbackTone()
        let pattern = { [weak self] in
            guard let self else { return }
            self.playTone(frequency: 425, duration: 1.0, gain: 0.12)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                self.playTone(frequency: 425, duration: 1.0, gain: 0.12)
            }
        }
        pattern()
        ringbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in pattern() }
    }
    
    private func stopRingbackTone() {
        ringbackTimer?.invalidate()
        ringbackTimer = nil
    }
    
    /// Локальный рингтон на входящий (когда экран приложения открыт, дублирует системный CallKit-рингтон).
    /// Повторяется, пока звонок не примут/не сбросят — раньше проигрывался только один раз (0.3с) и сразу затихал.
    private func playRingtoneLocally() {
        stopIncomingRingtone()
        let pattern = { [weak self] in
            guard let self else { return }
            self.playTone(frequency: 660, duration: 0.3, gain: 0.1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.playTone(frequency: 660, duration: 0.3, gain: 0.1)
            }
        }
        pattern()
        incomingRingtoneTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in pattern() }
    }

    private func stopIncomingRingtone() {
        incomingRingtoneTimer?.invalidate()
        incomingRingtoneTimer = nil
    }
    
    /// 880Hz двойной короткий гудок — сигнал установления соединения
    private func playConnectedTone() {
        playTone(frequency: 880, duration: 0.12, gain: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.playTone(frequency: 880, duration: 0.12, gain: 0.15)
        }
    }
    
    /// 660Hz -> 440Hz — сигнал завершения звонка
    private func playEndedTone() {
        playTone(frequency: 660, duration: 0.16, gain: 0.16)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.playTone(frequency: 440, duration: 0.22, gain: 0.16)
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        pollTask?.cancel(); pollTask = nil
        durationTimer?.invalidate(); durationTimer = nil
        connectedAt = nil
        stopRingbackTone()
        stopIncomingRingtone()
        pendingStartContinuation = nil
        #if canImport(WebRTC)
        bitrateMonitor?.invalidate(); bitrateMonitor = nil
        if isSharingScreen { RPScreenRecorder.shared().stopCapture(handler: nil) }
        isSharingScreen = false
        peerConnection?.close(); peerConnection = nil
        localAudioTrack = nil; localVideoTrack = nil; remoteVideoTrack = nil
        cameraVideoTrack = nil; screenVideoTrack = nil; screenVideoSource = nil
        videoCapturer?.stopCapture(); videoCapturer = nil
        #endif
        callId = nil; lastSignalId = 0; callDuration = 0
        isMuted = false; isSpeakerOn = false; currentCallUUID = nil
    }
}

// MARK: - RTCPeerConnectionDelegate

#if canImport(WebRTC)
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            switch newState {
            case .connected:
                if self.callState != .connected {
                    self.stopRingbackTone()
                    self.callState = .connected
                    self.startDurationTimer()
                    self.playConnectedTone()
                }
            case .disconnected, .failed, .closed:
                self.playEndedTone()
                self.callState = .ended(reason: "disconnected")
                self.cleanup()
            default: break
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let videoTrack = stream.videoTracks.first {
            DispatchQueue.main.async { self.remoteVideoTrack = videoTrack }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task {
            try? await sendSignal(callId: callId ?? 0, kind: "candidate",
                                   payload: ["candidate": candidate.sdp,
                                              "sdpMLineIndex": candidate.sdpMLineIndex,
                                              "sdpMid": candidate.sdpMid ?? "0"])
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
#endif

// MARK: - PushKit (VoIP push для звонков на экране блокировки)

extension WebRTCManager: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        // Отправляем токен на бэкенд для отправки VoIP push
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        print("[PushKit] VoIP token: \(token)")
        Task {
            try? await APIClient.shared.registerVoipToken(token)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("[PushKit] Incoming VoIP push: \(payload.dictionaryPayload)")
        handleVoipPush(payload: payload)
        completion()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[PushKit] VoIP token invalidated")
    }

    private func handleVoipPush(payload: PKPushPayload) {
        let data = payload.dictionaryPayload

        // Ожидаем payload: { "call_id": 123, "caller_name": "Иван", "call_type": "audio" }
        guard let callId = data["call_id"] as? Int else {
            print("[PushKit] No call_id in payload")
            return
        }

        let callerName = data["caller_name"] as? String ?? "Звонок"
        let callType = data["call_type"] as? String ?? "audio"

        // Показываем системный UI звонка через CallKit
        let uuid = UUID()
        self.currentCallUUID = uuid
        self.callId = callId
        self.callType = callType
        self.callState = .incomingRinging(callId: callId, callerName: callerName, type: callType)

        let handle = CXHandle(type: .generic, value: callerName)
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.hasVideo = callType == "video"

        callKitProvider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("[PushKit] reportNewIncomingCall error: \(error)")
            }
        }

        // Системный рингтон играет CallKit; локальный WebAudio-тон как дублирующий сигнал в UI
        playRingtoneLocally()
    }
}

// MARK: - CXProviderDelegate

extension WebRTCManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) { cleanup() }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if let callId { acceptCall(callId: callId) }
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) { endCall(); action.fulfill() }
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) { action.fulfill() }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        isMuted = action.isMuted
        #if canImport(WebRTC)
        localAudioTrack?.isEnabled = !isMuted
        #endif
        action.fulfill()
    }
}

// MARK: - CallView video helper

#if canImport(WebRTC)
import WebRTC

struct VideoView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        videoTrack.add(view)
        return view
    }
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
}
#endif

// MARK: - APIClient extension

extension APIClient {
    func answerCallDecline(callId: Int) async throws {
        try await requestVoid("calls/answer.php", method: .post, body: ["call_id": AnyEncodable(callId), "action": AnyEncodable("decline")])
    }
}

// SignalPayload — shared между WebRTC и non-WebRTC builds
private struct SignalPayload: Decodable {
    let type: String?; let sdp: String?
    let candidate: String?; let sdpMLineIndex: Int?; let sdpMid: String?
    enum CodingKeys: String, CodingKey {
        case type, sdp, candidate
        case sdpMLineIndex = "sdpMLineIndex"
        case sdpMid = "sdpMid"
    }
}

/// Helper для кодирования Any в JSON
private struct AnyCodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value as? String { try c.encode(v) }
        else if let v = value as? Int { try c.encode(v) }
        else if let v = value as? Double { try c.encode(v) }
        else if let v = value as? Bool { try c.encode(v) }
        else if let v = value as? [String: Any] {
            try c.encode(v.mapValues { AnyCodable($0) })
        } else if let v = value as? [Any] {
            try c.encode(v.map { AnyCodable($0) })
        } else if value is NSNull {
            try c.encodeNil()
        }
    }
}
