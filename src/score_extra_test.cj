package midi

import std.collection.*
import std.fs.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 乐谱模式扩展测试
// ============================================================

@Test
class ScoreExtraTests {
    // ── 空轨道 ──
    @TestCase
    func emptyTrack() {
        let input =
            "tempo 120\n" +
            "track empty {\n" +
            "    instrument \"piano\"\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
    }

    // ── 仅休止符轨道 ──
    @TestCase
    func restOnlyTrack() {
        let input =
            "tempo 120\n" +
            "track silence {\n" +
            "    instrument \"piano\"\n" +
            "    _:1 _:1\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 0)
    }

    // ── 全音符 ──
    @TestCase
    func wholeNotes() {
        let input =
            "tempo 60\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:1 D4:1\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        @Assert(verifyTempo(data, 60))
    }

    // ── 三十二分音符 ──
    @TestCase
    func thirtySecondNotes() {
        let input =
            "tempo 120\n" +
            "track fast {\n" +
            "    instrument \"piano\"\n" +
            "    C4:32 D4:32 E4:32 F4:32 G4:32 A4:32 B4:32 C5:32\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 8)
    }

    // ── 附点二分音符和附点八分音符 ──
    @TestCase
    func dottedVarieties() {
        let input =
            "tempo 100\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:2. D4:8. E4:1\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)
    }

    // ── 大和弦 ──
    @TestCase
    func largeChord() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    [C3 E3 G3 C4 E4 G4]:2\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 6)
    }

    // ── 连续和弦 ──
    @TestCase
    func consecutiveChords() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"guitar\"\n" +
            "    [C3 E3 G3]:4 [F3 A3 C4]:4 [G3 B3 D4]:4 [C3 E3 G3]:4\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 12) // 4 chords × 3 notes
    }

    // ── 变量嵌套使用 ──
    @TestCase
    func variableReuse() {
        let input =
            "tempo 120\n" +
            "let phrase = { C4:8 D4:8 E4:8 F4:8 }\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    phrase\n" +
            "    G4:4\n" +
            "    phrase\n" +
            "    A4:2\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 10) // 4 + 1 + 4 + 1
    }

    // ── 多变量定义 ──
    @TestCase
    func multipleVariables() {
        let input =
            "tempo 120\n" +
            "let intro = { C4:4 D4:4 }\n" +
            "let chorus = { E4:4 F4:4 G4:4 }\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    intro\n" +
            "    chorus\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 5) // 2 + 3
    }

    // ── 高/低音域 ──
    @TestCase
    func extremeOctaves() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C1:4 C2:4 C3:4 C4:4 C5:4 C6:4 C7:4 C8:4\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 8)
        @Expect(pitches[0], 24)  // C1
        @Expect(pitches[3], 60)  // C4
        @Expect(pitches[7], 108) // C8
    }

    // ── 所有音名 ──
    @TestCase
    func allNoteNames() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:8 D4:8 E4:8 F4:8 G4:8 A4:8 B4:8\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 7)
        @Expect(pitches[0], 60) // C4
        @Expect(pitches[1], 62) // D4
        @Expect(pitches[2], 64) // E4
        @Expect(pitches[3], 65) // F4
        @Expect(pitches[4], 67) // G4
        @Expect(pitches[5], 69) // A4
        @Expect(pitches[6], 71) // B4
    }

    // ── 所有升降号 ──
    @TestCase
    func allAccidentals() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C#4:8 D#4:8 F#4:8 G#4:8 A#4:8\n" +
            "    Db4:8 Eb4:8 Gb4:8 Ab4:8 Bb4:8\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 10)
        @Expect(pitches[0], 61) // C#4
        @Expect(pitches[1], 63) // D#4
        @Expect(pitches[5], 61) // Db4 = C#4
        @Expect(pitches[9], 70) // Bb4
    }

    // ── 交替音符和休止 ──
    @TestCase
    func alternatingNotesAndRests() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4 _:4 D4:4 _:4 E4:4 _:4 F4:4 _:4\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 4)
    }

    // ── 注释处理 ──
    @TestCase
    func comments() {
        let input =
            "// 这是一首测试曲\n" +
            "tempo 120  // 速度设置\n" +
            "\n" +
            "// 下面是主轨道\n" +
            "track melody {\n" +
            "    instrument \"piano\"  // 钢琴\n" +
            "    C4:4 D4:4  // 第一小节\n" +
            "    E4:4 F4:4  // 第二小节\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 4)
    }

    // ── 多轨道通道自动分配 ──
    @TestCase
    func autoChannelAssignment() {
        let input =
            "tempo 120\n" +
            "track t1 {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4\n" +
            "}\n" +
            "track t2 {\n" +
            "    instrument \"guitar\"\n" +
            "    E4:4\n" +
            "}\n" +
            "track t3 {\n" +
            "    instrument \"bass\"\n" +
            "    G3:4\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 3))
        let programs = extractProgramChanges(data)
        @Expect(programs.size, 3)
    }

    // ── 内联速度变化 ──
    @TestCase
    func inlineTempoChange() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4 D4:4\n" +
            "    tempo 90\n" +
            "    E4:4 F4:4\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        // Should contain two tempo events
        var tempoCount: Int64 = 0
        var i: Int64 = 0
        while (i + 2 < data.size) {
            if (data[i] == 0xFF && data[i + 1] == 0x51 && data[i + 2] == 0x03) {
                tempoCount++
            }
            i++
        }
        @Expect(tempoCount, 2) // one for 120, one for 90
    }

    // ── CC 和 PitchBend ──
    @TestCase
    func ccAndPitchBend() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    cc 64 127\n" +
            "    C4:4\n" +
            "    cc 64 0\n" +
            "    pitch_bend 0 64\n" +
            "    D4:4\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        // Verify round-trip
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 和弦后接音符 ──
    @TestCase
    func chordThenNotes() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    [C4 E4 G4]:4 C5:4 B4:4 A4:4\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 6) // 3 chord + 3 single
    }

    // ── 原始 tick 时值混合 ──
    @TestCase
    func mixedTickAndDuration() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4 D4:T360 E4:8 F4:T60\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 4)
    }

    // ── 乐谱完整回环 ──
    @TestCase
    func fullScoreRoundTrip() {
        let input =
            "tempo 96\n" +
            "\n" +
            "track lead {\n" +
            "    instrument \"flute\"\n" +
            "    velocity 100\n" +
            "    A4:4 B4:4 C5:4 D5:4\n" +
            "    E5:2 _:4 D5:4\n" +
            "    C5:4 B4:4 A4:2\n" +
            "}\n" +
            "\n" +
            "track chords {\n" +
            "    instrument \"strings\"\n" +
            "    velocity 75\n" +
            "    [A3 C4 E4]:2 [D3 F3 A3]:2\n" +
            "    [E3 G3 B3]:2 [D3 F3 A3]:2\n" +
            "    [A3 C4 E4]:2 [E3 G#3 B3]:2\n" +
            "}\n" +
            "\n" +
            "track bass {\n" +
            "    instrument \"bass\"\n" +
            "    A2:2 D3:2\n" +
            "    E2:2 D3:2\n" +
            "    A2:2 E2:2\n" +
            "}\n"
        let midi1 = generate(input)
        @Assert(verifyMThd(midi1, 1, 3))
        @Assert(verifyTempo(midi1, 96))
        let text = decompile(midi1)
        let midi2 = generate(text)
        verifyBinaryIdentical(midi1, midi2)
    }

    // ── testcase/source 编译验证 ──
    @TestCase
    func sourceFilesCompile() {
        let sourceDir = Path("testcase/source")
        if (!exists(sourceDir)) { return }
        let entries = Directory.readFrom(sourceDir)
        var count: Int64 = 0
        for (entry in entries) {
            if (!entry.name.endsWith(".txt")) { continue }
            let bytes = File.readFrom(sourceDir.join(entry.name))
            let input = String.fromUtf8(bytes)
            let data = generate(input)
            // Every source file must produce valid MIDI
            @Assert(data.size >= 14)
            @Assert(data[0] == 0x4D) // 'M'
            @Assert(data[1] == 0x54) // 'T'
            @Assert(data[2] == 0x68) // 'h'
            @Assert(data[3] == 0x64) // 'd'
            // Every source file .mid must be lossless round-trippable
            let text = decompile(data)
            let data2 = generate(text)
            verifyBinaryIdentical(data, data2)
            count++
        }
        @Assert(count >= 42)
    }
}
