package midi

import std.collection.*
import midi.core.*
import midi.encoder.*

// ============================================================
// 统一语言编码测试
// ============================================================

@Test
class EncodeTests {
    // ── 乐谱模式：基础编码 ──
    @TestCase
    func basicScoreMode() {
        let input =
            "tempo 120\n" +
            "\n" +
            "track melody {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4 D4:4 E4:4 F4:4\n" +
            "    G4:2\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        @Assert(verifyTempo(data, 120))
        let pitches = extractNoteOnPitches(data)
        @Assert(pitches.size >= 5)
    }

    // ── 乐谱模式：多轨道 ──
    @TestCase
    func multiTrackScore() {
        let input =
            "tempo 108\n" +
            "\n" +
            "track melody {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4 C4:4 G4:4 G4:4\n" +
            "    A4:4 A4:4 G4:2\n" +
            "}\n" +
            "\n" +
            "track harmony {\n" +
            "    instrument \"strings\"\n" +
            "    [C3 E3 G3]:2 [C3 E3 G3]:2\n" +
            "    [F3 A3 C4]:2 [C3 E3 G3]:2\n" +
            "}\n" +
            "\n" +
            "track bass {\n" +
            "    instrument \"bass\"\n" +
            "    C2:2 E2:2\n" +
            "    F2:2 C2:2\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 3))
        @Assert(countTracks(data), 3)
        let programs = extractProgramChanges(data)
        @Assert(programs.size >= 3)
        @Expect(programs[0], 0)   // piano
        @Expect(programs[1], 48)  // strings
        @Expect(programs[2], 33)  // bass
        @Assert(verifyTempo(data, 108))
    }

    // ── 乐谱模式：力度控制 ──
    @TestCase
    func velocityControl() {
        let input =
            "tempo 100\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    velocity 100\n" +
            "    C4:4 D4:4 E4:4 F4:4\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        var foundVel100 = false
        var i: Int64 = 14
        while (i + 2 < data.size) {
            if ((data[i] & 0xF0) == 0x90 && data[i + 2] == 100) {
                foundVel100 = true; break
            }
            i++
        }
        @Assert(foundVel100)
    }

    // ── 乐谱模式：附点音符 ──
    @TestCase
    func dottedNotes() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4. D4:8. E4:2.\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
    }

    // ── 乐谱模式：升降号 ──
    @TestCase
    func accidentals() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C#4:4 Bb3:4 F#4:8\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)
        @Expect(pitches[0], 61) // C#4
        @Expect(pitches[1], 58) // Bb3
        @Expect(pitches[2], 66) // F#4
    }

    // ── 乐谱模式：休止符 ──
    @TestCase
    func rests() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:4 _:4 D4:4\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 2)
    }

    // ── 乐谱模式：变量 ──
    @TestCase
    func variables() {
        let input =
            "tempo 120\n" +
            "let motif = { C4:4 D4:4 E4:4 }\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    motif\n" +
            "    motif\n" +
            "}\n"
        let data = generate(input)
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 6) // motif x 2 = 6 notes
    }

    // ── GM 乐器映射 ──
    @TestCase
    func gmInstrumentMapping() {
        @Expect(instrumentNumber("piano"), 0)
        @Expect(instrumentNumber("guitar"), 24)
        @Expect(instrumentNumber("bass"), 33)
        @Expect(instrumentNumber("violin"), 40)
        @Expect(instrumentNumber("strings"), 48)
        @Expect(instrumentNumber("trumpet"), 56)
        @Expect(instrumentNumber("flute"), 73)
        @Expect(GM_INSTRUMENTS.size, 128)
        @Expect(programToInstrument(0), "piano")
        @Expect(programToInstrument(58), "tuba")
    }

    // ── 乐谱模式：原始 tick 时值 ──
    @TestCase
    func rawTickDurations() {
        let input =
            "tempo 120\n" +
            "track t {\n" +
            "    instrument \"piano\"\n" +
            "    C4:T216 D4:T432 _:T100 E4:T108\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 0, 1))
        let pitches = extractNoteOnPitches(data)
        @Expect(pitches.size, 3)
    }

    // ── 乐谱模式：通道指定 ──
    @TestCase
    func channelPreservation() {
        let input =
            "tempo 120\n" +
            "track melody {\n" +
            "    channel 1\n" +
            "    instrument \"bright_piano\"\n" +
            "    C4:4 D4:4\n" +
            "}\n" +
            "track drums {\n" +
            "    channel 9\n" +
            "    instrument \"piano\"\n" +
            "    C4:32 D4:32\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 2))
    }
}
