import Foundation
import AVFoundation
import Combine

/// Pronunciation priority: 
/// 1. ElevenLabs AI TTS (Brian – neutral American accent)
/// 2. Merriam-Webster stored audio URL
/// 3. Offline AVSpeechSynthesizer (Apple TTS)
class PronunciationService: NSObject, ObservableObject {
    static let shared = PronunciationService()
    
    @Published var isPlaying: Bool = false
    
    // ─────────────────────────────────────────────
    // MARK: Configuration
    // ─────────────────────────────────────────────
    
    /// Key is now managed via AuthManager
    private var elevenLabsAPIKey: String {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["ELEVENLABS_API_KEY"] as? String, !key.isEmpty, key != "YOUR_API_KEY_HERE" {
            return key
        }
        return AuthManager.shared.elevenLabsKey
    }
    /// Brian – Neutral American English (best for accent learning).
    /// Other options: Adam (pNInz6obpgDQGcFmaJgB), Rachel (21m00Tcm4TlvDq8ikWAM)
    private let voiceID = "nPczCjzI2devNBz1zQrb"
    
    // ─────────────────────────────────────────────
    // MARK: Private State
    // ─────────────────────────────────────────────
    
    private var player: AVPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // ─────────────────────────────────────────────
    // MARK: Public API
    // ─────────────────────────────────────────────
    
    /// Speak a word. Tries ElevenLabs → MW audio URL → AVSpeechSynthesizer.
    func speak(word: String, audioURL: URL?) {
        stopAll()
        Task {
            await speakWithElevenLabs(word: word, fallbackURL: audioURL)
        }
    }
    
    func stopAll() {
        player?.pause()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        DispatchQueue.main.async { self.isPlaying = false }
    }
    
    // ─────────────────────────────────────────────
    // MARK: Priority 1 – ElevenLabs
    // ─────────────────────────────────────────────
    
    private func speakWithElevenLabs(word: String, fallbackURL: URL?) async {
        guard !elevenLabsAPIKey.isEmpty,
              elevenLabsAPIKey != "YOUR_ELEVENLABS_API_KEY_HERE",
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else {
            // No valid API key – skip to fallback
            await fallback(word: word, audioURL: fallbackURL)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "Accept")
        
        let body: [String: Any] = [
            "text": word,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                   print("ElevenLabs API Error (\(httpResponse.statusCode)): \(errorJson)")
                } else {
                    print("ElevenLabs API Failed with status: \(httpResponse.statusCode)")
                }
                await fallback(word: word, audioURL: fallbackURL)
                return
            }
            
            guard !data.isEmpty else {
                print("ElevenLabs returned empty data – falling back.")
                await fallback(word: word, audioURL: fallbackURL)
                return
            }
            
            // Write mp3 to a temp file and play it
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("elevenlabs_\(word.lowercased()).mp3")
            try data.write(to: tmpURL)
            print("Now playing via ElevenLabs (Brian voice) for word: \(word)")
            await playLocalFile(url: tmpURL, word: word, fallbackURL: fallbackURL)
            
        } catch {
            print("ElevenLabs network error: \(error) – falling back.")
            await fallback(word: word, audioURL: fallbackURL)
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: Priority 2 – Merriam-Webster Audio URL
    // ─────────────────────────────────────────────
    
    @MainActor
    private func fallback(word: String, audioURL: URL?) async {
        if let url = audioURL {
            print("Attempting MW audio fallback: \(url)")
            playRemoteAudio(url: url, fallbackWord: word)
        } else {
            print("No MW audio available, using Apple TTS for word: \(word)")
            speakWithTTS(word: word)
        }
    }
    
    @MainActor
    private func playLocalFile(url: URL, word: String, fallbackURL: URL?) async {
        configureAudioSession()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observePlayerItem(item, word: word, fallbackURL: fallbackURL)
        isPlaying = true
        player?.play()
    }
    
    @MainActor
    private func playRemoteAudio(url: URL, fallbackWord: String) {
        configureAudioSession()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observePlayerItem(item, word: fallbackWord, fallbackURL: nil)
        isPlaying = true
        player?.play()
    }
    
    private func observePlayerItem(_ item: AVPlayerItem, word: String, fallbackURL: URL?) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in 
            print("Playback finished for word: \(word)")
            self?.isPlaying = false 
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let error = item.error {
               print("Audio Playback Error for '\(word)': \(error.localizedDescription)")
            }
            Task { @MainActor in self.speakWithTTS(word: word) }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: Priority 3 – Apple AVSpeechSynthesizer
    // ─────────────────────────────────────────────
    
    @MainActor
    private func speakWithTTS(word: String) {
        let utterance = AVSpeechUtterance(string: word)
        
        // Prefer a male American English voice
        let maleUSVoice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language == "en-US" && $0.gender == .male
        }
        utterance.voice = maleUSVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42
        utterance.pitchMultiplier = 0.9  // Slightly lower pitch = sounds more natural/male
        isPlaying = true
        synthesizer.speak(utterance)
    }
    
    // ─────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────
    
    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension PronunciationService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isPlaying = false }
    }
}
