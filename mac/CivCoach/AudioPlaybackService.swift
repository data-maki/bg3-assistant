import AVFoundation
import Foundation

@MainActor
final class AudioPlaybackService {
    private var player: AVAudioPlayer?

    func play(base64MP3: String) throws {
        guard let data = Data(base64Encoded: base64MP3) else {
            throw CivCoachError.audioDecodingFailed
        }
        player = try AVAudioPlayer(data: data)
        player?.prepareToPlay()
        player?.play()
    }
}
