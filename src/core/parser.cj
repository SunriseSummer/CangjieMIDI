package midi.core

import std.collection.*
import std.convert.*

// ============================================================
// 统一 MIDI 语言解析器 — Score 模式
// ============================================================

// 解析新格式的音符token: "C4:4", "C#4:8", "Bb3:2.", "C4:T480"
func parseColonNote(token: String): NoteInfo {
    let runes = token.toRuneArray()
    let size = runes.size

    // Find the colon separator
    var colonIdx: Int64 = -1
    var i: Int64 = 0
    while (i < size) {
        if (runes[i] == r':') { colonIdx = i; break }
        i++
    }
    if (colonIdx < 0) {
        // No colon - just parse as note name, default quarter
        let nr = parseNoteToken(runes, 0, size)
        return NoteInfo(UInt8(nr.pitch), UInt32(nr.ticks))
    }

    // Parse pitch from chars before colon
    let pitchPart = runes[0..colonIdx]
    let base = basePitch(pitchPart[0])
    var pi: Int64 = 1
    var offset: Int64 = 0
    if (pi < pitchPart.size && pitchPart[pi] == r'#') { offset = 1; pi++ }
    else if (pi < pitchPart.size && pitchPart[pi] == r'b') { offset = -1; pi++ }
    var octave: Int64 = 0
    if (pi < pitchPart.size && isDigitRune(pitchPart[pi])) {
        octave = runeToDigit(pitchPart[pi])
    }
    let pitch = (octave + 1) * 12 + base + offset

    // Parse duration from chars after colon
    let durStart = colonIdx + 1
    let durResult = readNumber(runes, durStart, size)
    let ticks = durationToTicks(durResult.value)

    NoteInfo(UInt8(pitch), ticks)
}

// Parse rest token: "_:4", "_:2.", "_:T480"
func parseColonRest(token: String): UInt32 {
    let runes = token.toRuneArray()
    let size = runes.size
    // Find colon
    var colonIdx: Int64 = -1
    var i: Int64 = 0
    while (i < size) {
        if (runes[i] == r':') { colonIdx = i; break }
        i++
    }
    if (colonIdx < 0) { return 480 }
    let durResult = readNumber(runes, colonIdx + 1, size)
    durationToTicks(durResult.value)
}

// Parse chord token: "[C3 E3 G3]:2"
func parseColonChord(content: String, durStr: String): ChordInfo {
    let pitches = ArrayList<UInt8>()
    let parts = splitWhitespace(content)
    for (p in parts) {
        let runes = p.toRuneArray()
        if (runes.size < 2) { continue }
        if (!isNoteName(runes[0])) { continue }
        let base = basePitch(runes[0])
        var i: Int64 = 1
        var offset: Int64 = 0
        if (i < runes.size && runes[i] == r'#') { offset = 1; i++ }
        else if (i < runes.size && runes[i] == r'b') { offset = -1; i++ }
        if (i < runes.size && isDigitRune(runes[i])) {
            let octave = runeToDigit(runes[i])
            pitches.add(UInt8((octave + 1) * 12 + base + offset))
        }
    }
    let durRunes = durStr.toRuneArray()
    let durResult = readNumber(durRunes, 0, durRunes.size)
    ChordInfo(pitches, durationToTicks(durResult.value))
}

// Extract quoted string from a token like "piano" -> piano
func extractQuoted(s: String): String {
    let r = s.toRuneArray()
    if (r.size >= 2 && r[0] == r'"' && r[r.size - 1] == r'"') {
        return String(r[1..r.size - 1])
    }
    s
}

// Parse track block content tokens, expanding variables
func parseTrackContent(tokens: ArrayList<String>, track: TrackData, score: ScoreData,
                       variables: HashMap<String, ArrayList<String>>): Unit {
    var i: Int64 = 0
    while (i < tokens.size) {
        let tok = tokens[i]

        if (tok == "instrument") {
            if (i + 1 < tokens.size) {
                let name = extractQuoted(tokens[i + 1])
                track.instrument = instrumentNumber(name)
                i += 2
            } else { i++ }
            continue
        }
        if (tok == "velocity") {
            if (i + 1 < tokens.size) {
                try { track.velocity = Int64.parse(tokens[i + 1]) } catch (_: Exception) {}
                i += 2
            } else { i++ }
            continue
        }
        if (tok == "channel") {
            if (i + 1 < tokens.size) {
                try { track.channel = Int64.parse(tokens[i + 1]) } catch (_: Exception) {}
                i += 2
            } else { i++ }
            continue
        }
        if (tok == "tempo") {
            if (i + 1 < tokens.size) {
                try {
                    let bpm = Int64.parse(tokens[i + 1])
                    track.elements.add(MusicElement.TempoChange(bpm))
                } catch (_: Exception) {}
                i += 2
            } else { i++ }
            continue
        }
        if (tok == "cc") {
            if (i + 2 < tokens.size) {
                try {
                    let ctrl = UInt8.parse(tokens[i + 1])
                    let val2 = UInt8.parse(tokens[i + 2])
                    track.elements.add(MusicElement.CC(CCInfo(ctrl, val2)))
                } catch (_: Exception) {}
                i += 3
            } else { i++ }
            continue
        }
        if (tok == "pitch_bend") {
            if (i + 2 < tokens.size) {
                try {
                    let lsb = UInt8.parse(tokens[i + 1])
                    let msb = UInt8.parse(tokens[i + 2])
                    track.elements.add(MusicElement.PitchBend(PitchBendInfo(lsb, msb)))
                } catch (_: Exception) {}
                i += 3
            } else { i++ }
            continue
        }

        // Check for chord: starts with [
        if (tok.startsWith("[")) {
            // Collect everything until we find "]:duration"
            let chordBuf = StringBuilder()
            chordBuf.append(tok)
            var j = i + 1
            while (j < tokens.size) {
                chordBuf.append(" ")
                chordBuf.append(tokens[j])
                if (tokens[j].contains("]:") || tokens[j].contains("]")) {
                    j++
                    break
                }
                j++
            }
            let chordStr = chordBuf.toString()
            // Parse: [C3 E3 G3]:2
            let runes = chordStr.toRuneArray()
            // Find ']' manually
            var bracketEnd: Int64 = -1
            var idx: Int64 = 0
            while (idx < runes.size) {
                if (runes[idx] == r']') { bracketEnd = idx; break }
                idx++
            }
            if (bracketEnd >= 0) {
                let content = String(runes[1..bracketEnd])
                var durStr = "4"
                // After ], check for :duration
                let afterBracket = bracketEnd + 1
                if (afterBracket < runes.size && runes[afterBracket] == r':') {
                    durStr = String(runes[afterBracket + 1..runes.size])
                }
                let chord = parseColonChord(content, durStr)
                track.elements.add(MusicElement.Chord(chord))
            }
            i = j
            continue
        }

        // Check for rest: _:duration
        if (tok.startsWith("_")) {
            let ticks = parseColonRest(tok)
            track.elements.add(MusicElement.Rest(ticks))
            i++
            continue
        }

        // Check for note: contains ":" and starts with note name
        let tokRunes = tok.toRuneArray()
        if (tokRunes.size > 0 && isNoteName(tokRunes[0]) && tok.contains(":")) {
            let note = parseColonNote(tok)
            track.elements.add(MusicElement.SingleNote(note))
            i++
            continue
        }

        // Check for variable reference
        if (let Some(varTokens) <- variables.get(tok)) {
            let expanded = ArrayList<String>()
            for (vt in varTokens) { expanded.add(vt) }
            parseTrackContent(expanded, track, score, variables)
            i++
            continue
        }

        i++
    }
}

// Tokenize input respecting braces and quotes
func tokenizeInput(input: String): ArrayList<String> {
    let result = ArrayList<String>()
    let runes = input.toRuneArray()
    let size = runes.size
    var i: Int64 = 0
    while (i < size) {
        // Skip whitespace and newlines
        if (runes[i] == r' ' || runes[i] == r'\t' || runes[i] == r'\n' || runes[i] == r'\r') {
            i++
            continue
        }
        // Skip comments
        if (i + 1 < size && runes[i] == r'/' && runes[i + 1] == r'/') {
            while (i < size && runes[i] != r'\n') { i++ }
            continue
        }
        // Braces as separate tokens
        if (runes[i] == r'{' || runes[i] == r'}') {
            result.add(String(runes[i]))
            i++
            continue
        }
        // Quoted string
        if (runes[i] == r'"') {
            let sb = StringBuilder()
            sb.append(runes[i])
            i++
            while (i < size && runes[i] != r'"') {
                sb.append(runes[i])
                i++
            }
            if (i < size) { sb.append(runes[i]); i++ }
            result.add(sb.toString())
            continue
        }
        // Regular token
        let sb = StringBuilder()
        while (i < size && runes[i] != r' ' && runes[i] != r'\t' && runes[i] != r'\n' &&
               runes[i] != r'\r' && runes[i] != r'{' && runes[i] != r'}') {
            if (i + 1 < size && runes[i] == r'/' && runes[i + 1] == r'/') { break }
            sb.append(runes[i])
            i++
        }
        let s = sb.toString()
        if (!s.isEmpty()) { result.add(s) }
    }
    result
}

// Main parser entry point
public func parseScore(input: String): ScoreData {
    let score = ScoreData()
    let variables = HashMap<String, ArrayList<String>>()
    let tokens = tokenizeInput(input)
    let size = tokens.size
    var i: Int64 = 0

    while (i < size) {
        let tok = tokens[i]

        // Global tempo
        if (tok == "tempo" && i + 1 < size) {
            // Check if we're not inside a track block (simple heuristic: 
            // global tempo comes before any track)
            try {
                let bpm = Int64.parse(tokens[i + 1])
                score.tempo = bpm
            } catch (_: Exception) {}
            i += 2
            continue
        }

        // Variable definition: let name = { ... }
        if (tok == "let" && i + 3 < size) {
            let varName = tokens[i + 1]
            // skip "="
            i += 3 // skip "let", name, "="
            if (i < size && tokens[i] == "{") {
                i++ // skip "{"
                let varTokens = ArrayList<String>()
                var depth: Int64 = 1
                while (i < size && depth > 0) {
                    if (tokens[i] == "{") { depth++ }
                    else if (tokens[i] == "}") {
                        depth--
                        if (depth == 0) { break }
                    }
                    varTokens.add(tokens[i])
                    i++
                }
                if (i < size) { i++ } // skip "}"
                variables[varName] = varTokens
            }
            continue
        }

        // Track block: track name { ... }
        if (tok == "track") {
            var trackName = "track"
            i++
            if (i < size && tokens[i] != "{") {
                trackName = tokens[i]
                i++
            }
            if (i < size && tokens[i] == "{") {
                i++ // skip "{"
                let trackTokens = ArrayList<String>()
                var depth: Int64 = 1
                while (i < size && depth > 0) {
                    if (tokens[i] == "{") { depth++ }
                    else if (tokens[i] == "}") {
                        depth--
                        if (depth == 0) { break }
                    }
                    trackTokens.add(tokens[i])
                    i++
                }
                if (i < size) { i++ } // skip "}"

                let track = TrackData(trackName)
                parseTrackContent(trackTokens, track, score, variables)
                score.tracks.add(track)
            }
            continue
        }

        i++
    }

    if (score.tracks.size == 0) {
        score.tracks.add(TrackData("default"))
    }
    score
}
