package midi

import std.fs.*
import std.collection.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 反编译与无损回环测试
// ============================================================

@Test
class DecodeTests {
    // ── 事件模式：手工构造 ──
    @TestCase
    func eventModeManual() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +480 off C4 0 ch 0\n" +
            "    +0 on E4 90 ch 0\n" +
            "    +480 off E4 0 ch 0\n" +
            "    +0 on G4 100 ch 0\n" +
            "    +480 off G4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        @Assert(verifyTempo(data, 120))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)
        @Expect(pitches[0], 60)
        @Expect(pitches[1], 64)
        @Expect(pitches[2], 67)
    }

    // ── 事件模式：Running Status ──
    @TestCase
    func eventModeRunningStatus() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "    running_status on\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +480 on C4 0 ch 0\n" +
            "    +0 on D4 80 ch 0\n" +
            "    +480 on D4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
    }

    // ── 事件模式：CC 事件 ──
    @TestCase
    func eventModeCCEvents() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 cc 10 64 ch 0\n" +
            "    +0 cc 64 127 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +480 off C4 0 ch 0\n" +
            "    +0 cc 64 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        let text = decompile(data)
        @Assert(text.contains("cc 10 64 ch 0"))
        @Assert(text.contains("cc 64 127 ch 0"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 事件模式：Meta 事件 ──
    @TestCase
    func eventModeMetaEvents() {
        let input =
            "midi {\n" +
            "    format 1\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 meta 03 50 69 61 6E 6F\n" +
            "    +0 meta 58 04 02 18 08\n" +
            "    +0 tempo 600000us\n" +
            "    +0 end\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +960 off C4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 2))
        @Assert(verifyTempo(data, 100))
        let text = decompile(data)
        @Assert(text.contains("meta 03 50 69 61 6E 6F"))
        @Assert(text.contains("meta 58 04 02 18 08"))
        @Assert(text.contains("tempo 600000us"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 事件模式：多通道 ──
    @TestCase
    func eventModeMultiChannel() {
        let input =
            "midi {\n" +
            "    format 1\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 end\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +480 off C4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 program 48 ch 1\n" +
            "    +0 on E3 64 ch 1\n" +
            "    +960 off E3 0 ch 1\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 3))
        let programs = extractProgramChanges(data)
        @Expect(programs.size, 2)
        @Expect(programs[0], 0)
        @Expect(programs[1], 48)
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 升降号音名 ──
    @TestCase
    func sharpNoteNames() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C#4 80 ch 0\n" +
            "    +240 off C#4 0 ch 0\n" +
            "    +0 on F#4 80 ch 0\n" +
            "    +240 off F#4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 2)
        @Expect(pitches[0], 61)
        @Expect(pitches[1], 66)
        let text = decompile(data)
        @Assert(text.contains("on C#4"))
        @Assert(text.contains("on F#4"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 乐谱 → 事件 无损回环 ──
    @TestCase
    func scoreToEventRoundTrip() {
        let input =
            "tempo 120\n" +
            "\n" +
            "track melody {\n" +
            "    instrument \"guitar\"\n" +
            "    C4:4 D4:4 E4:8 E4:8 F4:4\n" +
            "    G4:2 _:4 A4:4\n" +
            "}\n" +
            "\n" +
            "track chords {\n" +
            "    instrument \"strings\"\n" +
            "    [C3 E3 G3]:2 [F3 A3 C4]:2\n" +
            "}\n" +
            "\n" +
            "track bass {\n" +
            "    instrument \"bass\"\n" +
            "    C2:2 F2:2\n" +
            "}\n"
        let midi1 = generate(input)
        @Assert(verifyMThd(midi1, 1, 3))
        let text1 = decompile(midi1)
        @Assert(text1.contains("midi"))
        let midi2 = generate(text1)
        @Expect(midi1.size, midi2.size)
        verifyBinaryIdentical(midi1, midi2)
        let text2 = decompile(midi2)
        @Expect(text1, text2)
    }

    // ── testcase/binary 无损回环 ──
    @TestCase
    func binaryFilesRoundTrip() {
        let binaryDir = Path("testcase/binary")
        if (!exists(binaryDir)) { return }
        let entries = Directory.readFrom(binaryDir)
        var count: Int64 = 0
        for (entry in entries) {
            if (!entry.name.endsWith(".mid")) { continue }
            let data = File.readFrom(binaryDir.join(entry.name))
            if (data.size < 14) { continue }
            if (data[0] != 0x4D || data[1] != 0x54) { continue }
            let text = decompile(data)
            @Assert(text.contains("midi"))
            let regen = generate(text)
            @Expect(data.size, regen.size)
            verifyBinaryIdentical(data, regen)
            count++
        }
        @Assert(count >= 11)
    }
}
