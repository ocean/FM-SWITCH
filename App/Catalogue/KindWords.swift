import Foundation

/// Kinds for firmwares no list sorts, from the words in their name and description, so the
/// filters find them too.
///
/// A firmware can match several, such as a generative chord firmware being both ambient and
/// chords. Kinds a list gives are left as they are.
enum KindWords {
    /// The words for each kind, matched as whole words, ignoring case.
    ///
    /// A word ending in `*` matches any word it starts, such as "arpeggiat*" for "arpeggiator"
    /// and "arpeggiated".
    static let words: KeyValuePairs<String, [String]> = [
        "synth": [
            "synth", "synths", "synthesiser", "synthesizer", "synthesisers", "synthesizers", "operator",
            "operators", "dx7", "oscillator", "oscillators", "wavetable", "wavetables", "organ", "organs",
            "polyphonic", "monophonic", "physical model*", "karplus", "subtractive", "additive",
        ],
        "groove": [
            "groovebox", "grooveboxes", "groove box", "sequencer", "sequencers", "step sequenc*", "16 step",
            "beatmaker", "beat maker", "acid", "303", "bassline", "basslines",
        ],
        "drums": [
            "drum", "drums", "drum machine", "drum machines", "drummachine", "sampler", "samplers", "sample",
            "samples", "sampling", "percussion", "808", "909", "break beats", "breakbeat", "breakbeats", "breaks",
            "rhythm", "rhythms",
        ],
        "ambient": ["ambient", "generative", "drone", "drones", "soundscape", "soundscapes", "meditat*", "binaural"],
        "chords": ["chord", "chords", "arpeggiat*", "arp", "arps", "progression", "progressions", "strum*"],
        "tracker": ["tracker", "trackers"],
        "game": ["game", "games", "puzzle", "puzzles"],
        "dev": ["sdk", "template", "templates", "test firmware", "diagnostic", "diagnostics", "bootloader"],
        "other": [
            "midi monitor", "midi controller", "midi processor", "midi interface", "controller", "controllers",
            "audio interface", "macro keyboard", "tuner", "ear train*", "metronome", "looper",
        ],
    ]

    /// Phrases for the FM-1 itself, which say nothing about the firmware, so they're left out.
    static let ignored = ["pocket synth", "mini synth", "fm 1 synth", "fm1 synth"]

    /// Kinds for firmwares whose words mislead, by their ID, in place of the guess.
    ///
    /// An empty list leaves the firmware with no kind.
    static let corrections: [String: [String]] = [
        "fm1-editor-maestro": ["other"],
        "fm1-editor-purplemonkey": ["game"],
        "fm1-editor-noct-fm": ["other"],
        // Its description mentions installing over the bootloader, which isn't what it's for.
        "fm1-editor-riddim-roots": ["groove", "drums", "ambient"],
        "fm1-editor-doom-fm1-smk": ["game"],
        "mutant-cloud-mwave-fm1-doom": ["game"],
        "fm1-editor-astra": ["other"],
        "mutant-cloud-astra-fm-1": ["other"],
        "mutant-cloud-bluetooth-control-multi-firmware-m-vave-fm1-fm1": ["other"],
    ]

    /// The kinds whose words `text` uses, in the order of ``words``.
    static func kinds(in text: String) -> [String] {
        // Words separated by single spaces, with one either end, so " drum " matches only the word.
        var spaced = " " + text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
        for phrase in ignored {
            spaced = spaced.replacingOccurrences(of: " \(phrase) ", with: " ")
        }
        return words.filter { _, words in
            words.contains { word in
                word.hasSuffix("*") ? spaced.contains(" \(word.dropLast())") : spaced.contains(" \(word) ")
            }
        }
        .map(\.key)
    }

    /// `entries`, with kinds from ``corrections`` or their own words for those no list sorts.
    static func filled(_ entries: [CatalogueEntry]) -> [CatalogueEntry] {
        entries.map { entry in
            guard entry.kinds.isEmpty else { return entry }
            var sorted = entry
            sorted.kinds = corrections[entry.id] ?? kinds(in: "\(entry.name) \(entry.what ?? "")")
            return sorted
        }
    }
}
