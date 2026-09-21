import AppKit

/// Manages playing system sound effects and discovering available system alert sounds.
public final class SoundEffectManager: Sendable {
    public static let shared = SoundEffectManager()
    
    public static let defaultSoundName = "Pop"
    
    /// Standard built-in macOS alert sounds.
    public static let standardSystemSounds: [String] = [
        "Basso",
        "Blow",
        "Bottle",
        "Frog",
        "Funk",
        "Glass",
        "Hero",
        "Morse",
        "Ping",
        "Pop",
        "Purr",
        "Sosumi",
        "Submarine",
        "Tink"
    ]
    
    /// Returns the list of available system sounds from system directories, or standard sounds as fallback.
    public static var availableSounds: [String] {
        var soundNames = Set<String>()
        
        let librarySounds = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds").path
        let directories = [
            "/System/Library/Sounds",
            "/Library/Sounds",
            librarySounds
        ].compactMap { $0 }
        
        let fm = FileManager.default
        for dir in directories {
            if let files = try? fm.contentsOfDirectory(atPath: dir) {
                for file in files {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if ["aiff", "aif", "wav", "mp3", "m4a", "caf"].contains(ext) {
                        let baseName = (file as NSString).deletingPathExtension
                        if !baseName.isEmpty {
                            soundNames.insert(baseName)
                        }
                    }
                }
            }
        }
        
        if soundNames.isEmpty {
            return standardSystemSounds
        }
        
        // Ensure standard sounds are always included
        for sound in standardSystemSounds {
            soundNames.insert(sound)
        }
        
        return Array(soundNames).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Plays the specified sound by name asynchronously on MainActor.
    @MainActor
    public static func playSound(named name: String) {
        guard !name.isEmpty else { return }
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.stop()
            sound.play()
        }
    }
}
