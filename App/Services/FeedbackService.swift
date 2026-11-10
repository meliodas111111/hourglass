import Foundation
import AVFoundation
import AudioToolbox
import UIKit

/// In-app sound + haptics (the alarm path for when the app is in the foreground).
@MainActor
final class FeedbackService {
    private var player: AVAudioPlayer?
    private var vibrationTask: Task<Void, Never>?
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func prepareFlipHaptic() { impact.prepare() }

    func flipHaptic(enabled: Bool) {
        guard enabled else { return }
        impact.impactOccurred(intensity: 1)
    }

    func lightHaptic(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Phase end / finish: sound (over the silent switch — `.playback`) and a short vibration pattern.
    func playAlert(sound: AlertSound, volume: Double, vibrate: Bool, isFinal: Bool) {
        stopAlert()
        if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                try session.setActive(true)
                let p = try AVAudioPlayer(contentsOf: url)
                p.volume = Float(volume)
                p.numberOfLoops = isFinal ? 1 : 0
                p.play()
                player = p
            } catch {
                AnalyticsService.shared.record(error: error, context: "audio")
            }
        }
        if vibrate {
            notification.notificationOccurred(.success)
            vibrationTask = Task {
                for _ in 0..<(isFinal ? 3 : 1) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
            }
        }
    }

    /// Settings → preview of the selected sound.
    func preview(sound: AlertSound, volume: Double) {
        playAlert(sound: sound, volume: volume, vibrate: false, isFinal: false)
    }

    func stopAlert() {
        vibrationTask?.cancel()
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
