package midi.decoder

import std.fs.*

// ============================================================
// MIDI 反编译器 — 统一事件格式输出（无损）
// ============================================================

// 十六进制字符查找表
let HEX_CHARS: Array<Rune> = [
    r'0', r'1', r'2', r'3', r'4', r'5', r'6', r'7',
    r'8', r'9', r'A', r'B', r'C', r'D', r'E', r'F'
]

func byteToHex(b: UInt8): String {
    let hi = HEX_CHARS[Int64(b >> 4)]
    let lo = HEX_CHARS[Int64(b & 0x0F)]
    "${hi}${lo}"
}

// Running Status 检测
func detectRunningStatus(data: Array<UInt8>, headerEnd: Int64, numTracks: Int64): Bool {
    var pos = headerEnd
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) { break }
        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen
        var j = trackStart
        while (j < trackEnd && j < data.size) {
            let vlq = decReadVLQ(data, j, trackEnd)
            j = vlq.newPos
            if (j >= trackEnd) { break }
            let firstByte = data[j]
            if (firstByte >= 0x80) {
                if (firstByte == 0xFF) {
                    j++
                    if (j >= trackEnd) { break }
                    j++
                    let metaVLQ = decReadVLQ(data, j, trackEnd)
                    j = metaVLQ.newPos + Int64(metaVLQ.value)
                } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                    j++
                    let sysVLQ = decReadVLQ(data, j, trackEnd)
                    j = sysVLQ.newPos + Int64(sysVLQ.value)
                } else {
                    let eventType = firstByte & 0xF0
                    j++
                    if (eventType == 0xC0 || eventType == 0xD0) { j += 1 }
                    else { j += 2 }
                }
            } else {
                return true
            }
        }
        pos = trackEnd
        ti++
    }
    false
}

// 通道事件解码
func decodeChannelEvent(sb: StringBuilder, data: Array<UInt8>,
                        eventType: UInt8, channel: UInt8,
                        delta: UInt32, dataPos: Int64, trackEnd: Int64): Unit {
    let ch = Int64(channel)
    if (eventType == 0x90 && dataPos + 1 < trackEnd) {
        let pitch = data[dataPos]
        let vel = data[dataPos + 1]
        sb.append("    +${delta} on ${pitchToName(pitch)} ${vel} ch ${ch}\n")
    } else if (eventType == 0x80 && dataPos + 1 < trackEnd) {
        let pitch = data[dataPos]
        let vel = data[dataPos + 1]
        sb.append("    +${delta} off ${pitchToName(pitch)} ${vel} ch ${ch}\n")
    } else if (eventType == 0xC0 && dataPos < trackEnd) {
        let prog = data[dataPos]
        sb.append("    +${delta} program ${prog} ch ${ch}\n")
    } else if (eventType == 0xB0 && dataPos + 1 < trackEnd) {
        let ctrl = data[dataPos]
        let val2 = data[dataPos + 1]
        sb.append("    +${delta} cc ${ctrl} ${val2} ch ${ch}\n")
    } else if (eventType == 0xD0 && dataPos < trackEnd) {
        let pressure = data[dataPos]
        sb.append("    +${delta} pressure ${pressure} ch ${ch}\n")
    } else if (eventType == 0xA0 && dataPos + 1 < trackEnd) {
        let note = data[dataPos]
        let pressure = data[dataPos + 1]
        sb.append("    +${delta} aftertouch ${pitchToName(note)} ${pressure} ch ${ch}\n")
    } else if (eventType == 0xE0 && dataPos + 1 < trackEnd) {
        let lsb = data[dataPos]
        let msb = data[dataPos + 1]
        sb.append("    +${delta} pitch_bend ${lsb} ${msb} ch ${ch}\n")
    } else {
        sb.append("    +${delta} meta ${byteToHex(eventType | channel)}")
        if (eventType == 0xC0 || eventType == 0xD0) {
            if (dataPos < trackEnd) { sb.append(" ${byteToHex(data[dataPos])}") }
        } else {
            if (dataPos < trackEnd) { sb.append(" ${byteToHex(data[dataPos])}") }
            if (dataPos + 1 < trackEnd) { sb.append(" ${byteToHex(data[dataPos + 1])}") }
        }
        sb.append("\n")
    }
}

// 轨道事件解码
func decodeTrackEvents(sb: StringBuilder, data: Array<UInt8>,
                       trackStart: Int64, trackEnd: Int64): Unit {
    var j = trackStart
    var runningStatus: UInt8 = 0

    while (j < trackEnd && j < data.size) {
        let vlq = decReadVLQ(data, j, trackEnd)
        let delta = vlq.value
        j = vlq.newPos
        if (j >= trackEnd) { break }

        let firstByte = data[j]

        if (firstByte >= 0x80) {
            if (firstByte == 0xFF) {
                j++
                if (j >= trackEnd) { break }
                let metaType = data[j]
                j++
                let metaVLQ = decReadVLQ(data, j, trackEnd)
                let metaLen = Int64(metaVLQ.value)
                j = metaVLQ.newPos

                if (metaType == 0x51 && metaLen == 3 && j + 2 < trackEnd) {
                    let micro = UInt32(data[j]) << 16 | UInt32(data[j + 1]) << 8 | UInt32(data[j + 2])
                    sb.append("    +${delta} tempo ${micro}us\n")
                } else if (metaType == 0x2F) {
                    sb.append("    +${delta} end\n")
                } else {
                    sb.append("    +${delta} meta ${byteToHex(metaType)}")
                    var mi: Int64 = 0
                    while (mi < metaLen && j + mi < trackEnd) {
                        sb.append(" ${byteToHex(data[j + mi])}")
                        mi++
                    }
                    sb.append("\n")
                }
                j += metaLen
                runningStatus = 0
            } else if (firstByte == 0xF0 || firstByte == 0xF7) {
                j++
                let sysVLQ = decReadVLQ(data, j, trackEnd)
                let sysLen = Int64(sysVLQ.value)
                j = sysVLQ.newPos
                sb.append("    +${delta} sysex ${byteToHex(firstByte)}")
                var si: Int64 = 0
                while (si < sysLen && j + si < trackEnd) {
                    sb.append(" ${byteToHex(data[j + si])}")
                    si++
                }
                sb.append("\n")
                j += sysLen
                runningStatus = 0
            } else {
                let eventType = firstByte & 0xF0
                let channel = firstByte & 0x0F
                runningStatus = firstByte
                j++
                decodeChannelEvent(sb, data, eventType, channel, delta, j, trackEnd)
                if (eventType == 0xC0 || eventType == 0xD0) { j += 1 }
                else { j += 2 }
            }
        } else {
            let eventType = runningStatus & 0xF0
            let channel = runningStatus & 0x0F
            decodeChannelEvent(sb, data, eventType, channel, delta, j, trackEnd)
            if (eventType == 0xC0 || eventType == 0xD0) { j += 1 }
            else { j += 2 }
        }
        if (j > trackEnd) { j = trackEnd }
    }
}

// MIDI 文件字节数组 → 统一事件格式文本（无损）
public func decompile(data: Array<UInt8>): String {
    if (data.size < 14) {
        return "// Error: Invalid MIDI file (too short)\n"
    }
    if (data[0] != 0x4D || data[1] != 0x54 || data[2] != 0x68 || data[3] != 0x64) {
        return "// Error: Invalid MIDI file (bad MThd)\n"
    }

    let format = Int64(decReadU16(data, 8))
    let numTracks = Int64(decReadU16(data, 10))
    let tpq = Int64(decReadU16(data, 12))
    let useRS = detectRunningStatus(data, 14, numTracks)

    let sb = StringBuilder()
    sb.append("midi {\n")
    sb.append("    format ${format}\n")
    sb.append("    tpq ${tpq}\n")
    if (useRS) {
        sb.append("    running_status on\n")
    }
    sb.append("}\n")

    var pos: Int64 = 14
    var ti: Int64 = 0
    while (ti < numTracks) {
        if (pos + 8 > data.size) { break }
        if (data[pos] != 0x4D || data[pos + 1] != 0x54 ||
            data[pos + 2] != 0x72 || data[pos + 3] != 0x6B) { break }
        let trackLen = Int64(decReadU32(data, pos + 4))
        let trackStart = pos + 8
        let trackEnd = trackStart + trackLen
        sb.append("\ntrack {\n")
        decodeTrackEvents(sb, data, trackStart, trackEnd)
        sb.append("}\n")
        pos = trackEnd
        ti++
    }

    sb.toString()
}

// 兼容旧 API
public func decompileReadable(data: Array<UInt8>): String {
    decompile(data)
}

public func decompileToString(midPath: String): String {
    let data = File.readFrom(Path(midPath))
    decompile(data)
}

public func decompileReadableToString(midPath: String): String {
    decompileToString(midPath)
}
