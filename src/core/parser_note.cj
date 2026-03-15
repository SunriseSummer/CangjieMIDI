package midi.core

import std.collection.*

// ============================================================
// 文本乐谱解析器 — 音符与和弦解析
// 基础类型和字符工具见 parser_utils.cj
// ============================================================

// ── 音符标记解析 ──

// 解析单个音符标记，如 "C#4 8" → 音高 + 时值
// 返回 pitch=-1 表示解析失败
func parseNoteToken(runes: Array<Rune>, startPos: Int64, size: Int64): NoteTokenResult {
    var i = startPos
    let base = basePitch(runes[i])
    if (base < 0) {
        return NoteTokenResult(-1, 0, i + 1)
    }
    i++

    // 处理升降号（# 升半音，b 降半音）
    var offset: Int64 = 0
    if (i < size && runes[i] == r'#') {
        offset = 1
        i++
    } else if (i < size && runes[i] == r'b') {
        offset = -1
        i++
    }

    // 读取八度数字（0-9）
    if (i >= size || !isDigitRune(runes[i])) {
        return NoteTokenResult(-1, 0, i)
    }
    let octave = runeToDigit(runes[i])
    i++

    // 计算 MIDI 音高值：(八度+1)*12 + 基础音名偏移 + 升降号
    let pitch = (octave + 1) * 12 + base + offset

    // 跳过空白，读取时值
    while (i < size && isSpaceRune(runes[i])) { i++ }
    let durResult = readNumber(runes, i, size)
    i = durResult.newPos
    let ticks = Int64(durationToTicks(durResult.value))

    NoteTokenResult(pitch, ticks, i)
}

// ── 文本处理工具 ──
func splitWhitespace(s: String): ArrayList<String> {
    let result = ArrayList<String>()
    var current = StringBuilder()
    var inWord = false
    for (ch in s.toRuneArray()) {
        if (isSpaceRune(ch)) {
            if (inWord) {
                result.add(current.toString())
                current = StringBuilder()
                inWord = false
            }
        } else {
            current.append(ch)
            inWord = true
        }
    }
    if (inWord) { result.add(current.toString()) }
    result
}
