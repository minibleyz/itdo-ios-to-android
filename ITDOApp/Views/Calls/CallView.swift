import SwiftUI

/// Полноэкранный экран звонка — аудио или видео.
struct CallView: View {
    @StateObject private var rtc = WebRTCManager.shared
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    
    let conversation: Conversation
    
    var body: some View {
        ZStack {
            if rtc.callType == "video" {
                Color.black.ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [DesignTokens.background, DesignTokens.backgroundSecondary],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                topSection
                Spacer()
                if rtc.callType == "video" {
                    CallVideoSection(rtc: rtc)
                }
                Spacer()
                if rtc.callState == .connected {
                    Text(durationString(rtc.callDuration))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 20)
                }
                statusText
                    .padding(.bottom, 30)
                controlButtons
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            if rtc.callState == .idle {
                rtc.startCall(convId: conversation.id, type: "audio")
            }
        }
    }
    
    private var topSection: some View {
        VStack(spacing: 8) {
            if let avatar = conversation.avatar, let url = URL.secure(avatar) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(DesignTokens.backgroundSecondary)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(DesignTokens.backgroundSecondary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: conversation.isGroup ? "person.2.fill" : "person.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(DesignTokens.textSecondary)
                    )
            }
            Text(conversation.displayName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.top, 60)
    }
    
    private var statusText: some View {
        Group {
            switch rtc.callState {
            case .idle:
                EmptyView()
            case .outgoingRinging:
                Text("Вызов...").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
            case .incomingRinging(_, let name, _):
                Text("\(name) звонит...").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
            case .connecting:
                Text("Соединение...").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
            case .connected:
                EmptyView()
            case .ended(let reason):
                Text(endedText(reason)).font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 40) {
            CallControlButton(
                icon: rtc.isMuted ? "mic.slash.fill" : "mic.fill",
                isActive: rtc.isMuted,
                action: { rtc.toggleMute() }
            )
            Button {
                rtc.endCall()
                dismiss()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            CallControlButton(
                icon: rtc.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                isActive: rtc.isSpeakerOn,
                action: { rtc.toggleSpeaker() }
            )
            if rtc.callType == "video" {
                if !rtc.isSharingScreen {
                    CallControlButton(
                        icon: "camera.rotate.fill",
                        isActive: false,
                        action: { rtc.toggleCamera() }
                    )
                }
                CallControlButton(
                    icon: rtc.isSharingScreen ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle",
                    isActive: rtc.isSharingScreen,
                    action: { rtc.toggleScreenShare() }
                )
            }
        }
    }
    
    private func durationString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func endedText(_ reason: String) -> String {
        switch reason {
        case "declined": return "Звонок отклонён"
        case "missed": return "Пропущенный звонок"
        case "disconnected": return "Соединение разорвано"
        default: return "Звонок завершён"
        }
    }
}

// MARK: - Video section (отдельный view чтобы не ломать #if canImport scope)

private struct CallVideoSection: View {
    @ObservedObject var rtc: WebRTCManager
    
    var body: some View {
        #if canImport(WebRTC)
        CallVideoContent(rtc: rtc)
        #else
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.5))
            Text("Видео недоступно")
                .foregroundStyle(.white.opacity(0.5))
        }
        #endif
    }
}

#if canImport(WebRTC)
import WebRTC

private struct CallVideoContent: View {
    @ObservedObject var rtc: WebRTCManager
    
    var body: some View {
        ZStack {
            if let remoteTrack = rtc.remoteVideoTrack {
                VideoView(videoTrack: remoteTrack)
                    .ignoresSafeArea()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 300)
                    .overlay(Text("Ожидание видео...").foregroundStyle(.white.opacity(0.5)))
            }
            if let localTrack = rtc.localVideoTrack {
                VideoView(videoTrack: localTrack)
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.3), lineWidth: 1))
                    .shadow(radius: 8)
                    .offset(x: 100, y: -80)
            }
        }
    }
}
#endif

// MARK: - Control button

private struct CallControlButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isActive ? DesignTokens.accentPrimary : .white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(isActive ? .white : .white.opacity(0.15)))
        }
    }
}

// MARK: - Incoming call banner

struct IncomingCallBanner: View {
    let callId: Int
    let callerName: String
    let callType: String
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Circle()
                    .fill(DesignTokens.accentPrimary.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: callType == "video" ? "video.fill" : "phone.fill")
                            .foregroundStyle(DesignTokens.accentPrimary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(callerName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(callType == "video" ? "Видеозвонок" : "Аудиозвонок")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 16) {
                Button("Отклонить") { onDecline() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Button("Принять") { onAccept() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(DesignTokens.accentRepost)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, 20)
    }
}
