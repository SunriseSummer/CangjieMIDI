package midi.encoder

import std.collection.*
import std.convert.*
import midi.core.*

// ============================================================
// 统一编码器：新语言文本 → MIDI 二进制
// 支持乐谱模式（Score）和事件模式（Event）
// ============================================================

func buildTrackEvents(trackData: TrackData, tempo: Int64,
                       channel: UInt8, isFirstTrack: Bool): ArrayList<TimedEvent> {
    let events = ArrayList<TimedEvent>()
    var pendingDelta: UInt32 = 0
    let velocity: UInt8 = if (trackData.velocity > 0 && trackData.velocity <= 127) {
        UInt8(trackData.velocity)
    } else { DEFAULT_VELOCITY }

    if (isFirstTrack) {
        events.add(TimedEvent(0, MidiEvent.setTempo(UInt32(60000000 / tempo))))
    }
    if (trackData.instrument >= 0) {
        events.add(TimedEvent(0, MidiEvent.programChange(channel, UInt8(trackData.instrument))))
    }

    for (element in trackData.elements) {
        match (element) {
            case MusicElement.SingleNote(note) =>
                let noteVel: UInt8 = if (note.velocity > 0) { UInt8(note.velocity) } else { velocity }
                events.add(TimedEvent(pendingDelta, MidiEvent.noteOn(channel, note.pitch, noteVel)))
                pendingDelta = 0
                events.add(TimedEvent(note.durationTicks, MidiEvent.noteOff(channel, note.pitch)))
            case MusicElement.Chord(chord) =>
                let chordVel: UInt8 = if (chord.velocity > 0) { UInt8(chord.velocity) } else { velocity }
                var first = true
                for (pitch in chord.pitches) {
                    let delta = if (first) { pendingDelta } else { UInt32(0) }
                    events.add(TimedEvent(delta, MidiEvent.noteOn(channel, pitch, chordVel)))
                    if (first) { pendingDelta = 0; first = false }
                }
                var firstOff = true
                for (pitch in chord.pitches) {
                    let delta = if (firstOff) { chord.durationTicks } else { UInt32(0) }
                    events.add(TimedEvent(delta, MidiEvent.noteOff(channel, pitch)))
                    firstOff = false
                }
            case MusicElement.Rest(ticks) =>
                pendingDelta += ticks
            case MusicElement.TempoChange(bpm) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.setTempo(UInt32(60000000 / bpm))))
                pendingDelta = 0
            case MusicElement.CC(info) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.controlChange(channel, info.controller, info.value)))
                pendingDelta = 0
            case MusicElement.PitchBend(info) =>
                events.add(TimedEvent(pendingDelta, MidiEvent.pitchBend(channel, info.lsb, info.msb)))
                pendingDelta = 0
        }
    }
    events.add(TimedEvent(pendingDelta, MidiEvent.endOfTrack()))
    events
}

func encodeTrackChunk(events: ArrayList<TimedEvent>): ArrayList<UInt8> {
    let trackData = ArrayList<UInt8>()
    for (te in events) {
        for (b in encodeVLQ(te.deltaTime)) { trackData.add(b) }
        for (b in encodeEvent(te.event)) { trackData.add(b) }
    }
    let result = ArrayList<UInt8>()
    result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
    writeUInt32BE(result, UInt32(trackData.size))
    for (b in trackData) { result.add(b) }
    result
}

func generateScore(input: String): Array<UInt8> {
    let score = parseScore(input)
    let encodedTracks = ArrayList<ArrayList<UInt8>>()

    if (score.tempoChanges.size > 0) {
        let tempoEvents = ArrayList<TimedEvent>()
        tempoEvents.add(TimedEvent(0, MidiEvent.setTempo(UInt32(60000000 / score.tempo))))
        let sorted = ArrayList<TempoEntry>()
        for (tc in score.tempoChanges) { sorted.add(tc) }
        var si: Int64 = 1
        while (si < sorted.size) {
            let key = sorted[si]
            var sj = si - 1
            while (sj >= 0 && sorted[sj].tick > key.tick) {
                sorted[sj + 1] = sorted[sj]
                sj--
            }
            sorted[sj + 1] = key
            si++
        }
        var prevTick: UInt32 = 0
        for (tc in sorted) {
            let delta = if (tc.tick > prevTick) { tc.tick - prevTick } else { UInt32(0) }
            tempoEvents.add(TimedEvent(delta, MidiEvent.setTempo(UInt32(60000000 / tc.bpm))))
            prevTick = tc.tick
        }
        tempoEvents.add(TimedEvent(0, MidiEvent.endOfTrack()))
        encodedTracks.add(encodeTrackChunk(tempoEvents))
    }

    var channelIdx: UInt8 = 0
    var isFirst = score.tempoChanges.size == 0
    for (td in score.tracks) {
        let ch: UInt8 = if (td.channel >= 0 && td.channel <= 15) {
            UInt8(td.channel)
        } else {
            let assigned = channelIdx
            channelIdx++
            if (channelIdx == 9) { channelIdx = 10 }
            assigned
        }
        encodedTracks.add(encodeTrackChunk(buildTrackEvents(td, score.tempo, ch, isFirst)))
        isFirst = false
    }

    let trackCount = encodedTracks.size
    let format: UInt16 = if (trackCount <= 1) { 0 } else { 1 }
    let result = ArrayList<UInt8>()
    result.add(0x4D); result.add(0x54); result.add(0x68); result.add(0x64)
    writeUInt32BE(result, 6)
    writeUInt16BE(result, format)
    writeUInt16BE(result, UInt16(trackCount))
    writeUInt16BE(result, TICKS_PER_QUARTER)
    for (track in encodedTracks) {
        for (b in track) { result.add(b) }
    }
    result.toArray()
}

// ── 事件模式编码 ──

func findChannel(parts: ArrayList<String>): UInt8 {
    var i: Int64 = 0
    while (i < parts.size - 1) {
        if (parts[i] == "ch") {
            try { return UInt8.parse(parts[i + 1]) } catch (_: Exception) {}
        }
        i++
    }
    return 0
}

func writeChannelStatus(td: ArrayList<UInt8>, status: UInt8,
                        useRS: Bool, lastStatus: UInt8): Unit {
    if (useRS && status == lastStatus) {} else { td.add(status) }
}

func encodeEventLine(td: ArrayList<UInt8>, parts: ArrayList<String>,
                     delta: UInt32, useRS: Bool, lastStatus: UInt8): UInt8 {
    let vlqBytes = encodeVLQ(delta)
    for (b in vlqBytes) { td.add(b) }
    if (parts.size < 1) { return lastStatus }
    let eventType = parts[0]

    if (eventType == "on") {
        if (parts.size < 4) { return lastStatus }
        let pitch = noteNameToMidi(parts[1])
        if (pitch < 0) { return lastStatus }
        var vel: UInt8 = 0
        try { vel = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0x90 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(UInt8(pitch)); td.add(vel)
        return status
    }
    if (eventType == "off") {
        if (parts.size < 4) { return lastStatus }
        let pitch = noteNameToMidi(parts[1])
        if (pitch < 0) { return lastStatus }
        var vel: UInt8 = 0
        try { vel = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0x80 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(UInt8(pitch)); td.add(vel)
        return status
    }
    if (eventType == "program") {
        if (parts.size < 2) { return lastStatus }
        var prog: UInt8 = 0
        try { prog = UInt8.parse(parts[1]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xC0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(prog)
        return status
    }
    if (eventType == "cc") {
        if (parts.size < 3) { return lastStatus }
        var ctrl: UInt8 = 0
        var val2: UInt8 = 0
        try { ctrl = UInt8.parse(parts[1]) } catch (_: Exception) {}
        try { val2 = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xB0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(ctrl); td.add(val2)
        return status
    }
    if (eventType == "pressure") {
        if (parts.size < 2) { return lastStatus }
        var pval: UInt8 = 0
        try { pval = UInt8.parse(parts[1]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xD0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(pval)
        return status
    }
    if (eventType == "aftertouch") {
        if (parts.size < 3) { return lastStatus }
        let pitch = noteNameToMidi(parts[1])
        if (pitch < 0) { return lastStatus }
        var pval: UInt8 = 0
        try { pval = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xA0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(UInt8(pitch)); td.add(pval)
        return status
    }
    if (eventType == "pitch_bend") {
        if (parts.size < 3) { return lastStatus }
        var lsb: UInt8 = 0
        var msb: UInt8 = 0
        try { lsb = UInt8.parse(parts[1]) } catch (_: Exception) {}
        try { msb = UInt8.parse(parts[2]) } catch (_: Exception) {}
        let ch = findChannel(parts)
        let status: UInt8 = 0xE0 | ch
        writeChannelStatus(td, status, useRS, lastStatus)
        td.add(lsb); td.add(msb)
        return status
    }
    if (eventType == "tempo") {
        if (parts.size < 2) { return lastStatus }
        var tempoStr = parts[1]
        if (tempoStr.endsWith("us")) {
            let r = tempoStr.toRuneArray()
            tempoStr = String(r[0..r.size - 2])
        }
        var micro: UInt32 = 500000
        try { micro = UInt32.parse(tempoStr) } catch (_: Exception) {}
        td.add(0xFF); td.add(0x51); td.add(0x03)
        td.add(UInt8((micro >> 16) & 0xFF))
        td.add(UInt8((micro >> 8) & 0xFF))
        td.add(UInt8(micro & 0xFF))
        return 0
    }
    if (eventType == "end") {
        td.add(0xFF); td.add(0x2F); td.add(0x00)
        return 0
    }
    if (eventType == "meta") {
        if (parts.size < 2) { return lastStatus }
        let metaType = parseHexByte(parts[1])
        let dataLen = parts.size - 2
        td.add(0xFF); td.add(metaType)
        let lenVLQ = encodeVLQ(UInt32(dataLen))
        for (b in lenVLQ) { td.add(b) }
        var di: Int64 = 2
        while (di < parts.size) { td.add(parseHexByte(parts[di])); di++ }
        return 0
    }
    if (eventType == "sysex") {
        if (parts.size < 2) { return lastStatus }
        td.add(parseHexByte(parts[1]))
        let dataLen = parts.size - 2
        let lenVLQ = encodeVLQ(UInt32(dataLen))
        for (b in lenVLQ) { td.add(b) }
        var si: Int64 = 2
        while (si < parts.size) { td.add(parseHexByte(parts[si])); si++ }
        return 0
    }
    lastStatus
}

func generateEvent(input: String): Array<UInt8> {
    var tpq: UInt16 = 480
    var format: UInt16 = 0
    var useRS = false
    let trackDataList = ArrayList<ArrayList<UInt8>>()
    var currentTrack: ?ArrayList<UInt8> = None
    var inTrack = false
    var inHeader = false
    var lastStatus: UInt8 = 0

    for (line in input.split("\n")) {
        var trimmed = line.trimAscii()
        // Strip inline comments
        let runes = trimmed.toRuneArray()
        var commentPos: Int64 = -1
        var index: Int64 = 0
        while (index + 1 < runes.size) {
            if (runes[index] == r'/' && runes[index + 1] == r'/') { commentPos = index; break }
            index++
        }
        if (commentPos >= 0) {
            trimmed = String(runes[0..commentPos]).trimAscii()
        }
        if (trimmed.isEmpty()) { continue }

        if (trimmed.startsWith("midi")) { inHeader = true; continue }
        if (inHeader) {
            if (trimmed == "}") { inHeader = false; continue }
            let parts = splitByWhitespace(trimmed)
            if (parts.size >= 2) {
                if (parts[0] == "format") {
                    try { format = UInt16.parse(parts[1]) } catch (_: Exception) {}
                } else if (parts[0] == "tpq") {
                    try { tpq = UInt16.parse(parts[1]) } catch (_: Exception) {}
                } else if (parts[0] == "running_status") {
                    useRS = parts[1] == "on"
                }
            }
            continue
        }

        if (trimmed.startsWith("track")) {
            currentTrack = ArrayList<UInt8>()
            inTrack = true
            lastStatus = 0
            continue
        }
        if (trimmed == "}") {
            if (inTrack) {
                if (let Some(td) <- currentTrack) { trackDataList.add(td) }
                currentTrack = None
                inTrack = false
                lastStatus = 0
            }
            continue
        }

        if (inTrack) {
            if (let Some(td) <- currentTrack) {
                if (trimmed.startsWith("+")) {
                    let r = trimmed.toRuneArray()
                    let content = String(r[1..r.size])
                    let parts = splitByWhitespace(content)
                    if (parts.size < 2) { continue }
                    var delta: UInt32 = 0
                    try { delta = UInt32.parse(parts[0]) } catch (_: Exception) { continue }
                    let eventParts = ArrayList<String>()
                    var pi: Int64 = 1
                    while (pi < parts.size) { eventParts.add(parts[pi]); pi++ }
                    lastStatus = encodeEventLine(td, eventParts, delta, useRS, lastStatus)
                }
            }
        }
    }
    assembleMidiFile(trackDataList, format, tpq)
}

// ── 核心入口 ──

public func generate(input: String): Array<UInt8> {
    if (isMidiReadableFormat(input)) {
        return generateEvent(input)
    }
    generateScore(input)
}
