package midi

import std.fs.*
import midi.encoder.*
import midi.decoder.*

// ============================================================
// 事件模式扩展测试
// ============================================================

@Test
class EventExtraTests {
    // ── 多轨道事件模式 ──
    @TestCase
    func multiTrackEvent() {
        let input =
            "midi {\n" +
            "    format 1\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 meta 58 04 02 18 08\n" +
            "    +0 end\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +480 off C4 0 ch 0\n" +
            "    +0 on D4 80 ch 0\n" +
            "    +480 off D4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 program 24 ch 1\n" +
            "    +0 on E3 64 ch 1\n" +
            "    +960 off E3 0 ch 1\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 3))
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── Pressure 事件 ──
    @TestCase
    func pressureEvent() {
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
            "    +120 pressure 100 ch 0\n" +
            "    +360 off C4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("pressure 100 ch 0"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── Aftertouch 事件 ──
    @TestCase
    func aftertouchEvent() {
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
            "    +120 aftertouch C4 90 ch 0\n" +
            "    +360 off C4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("aftertouch C4 90 ch 0"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── Pitch Bend 事件 ──
    @TestCase
    func pitchBendEvent() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 pitch_bend 0 64 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +240 pitch_bend 0 80 ch 0\n" +
            "    +240 off C4 0 ch 0\n" +
            "    +0 pitch_bend 0 64 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("pitch_bend 0 64 ch 0"))
        @Assert(text.contains("pitch_bend 0 80 ch 0"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 大量 CC 事件 ──
    @TestCase
    func manyControlChanges() {
        let sb = StringBuilder()
        sb.append("midi {\n")
        sb.append("    format 0\n")
        sb.append("    tpq 480\n")
        sb.append("}\n\n")
        sb.append("track {\n")
        sb.append("    +0 tempo 500000us\n")
        sb.append("    +0 program 0 ch 0\n")
        // CC 7 = Volume, ramp up
        var v: Int64 = 0
        while (v <= 127) {
            sb.append("    +10 cc 7 ${v} ch 0\n")
            v += 10
        }
        sb.append("    +0 on C4 80 ch 0\n")
        sb.append("    +480 off C4 0 ch 0\n")
        sb.append("    +0 end\n")
        sb.append("}\n")

        let data = generate(sb.toString())
        let text = decompile(data)
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── SysEx 事件 ──
    @TestCase
    func sysexEvent() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 sysex F0 7E 7F 09 01 F7\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +480 off C4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("sysex F0 7E 7F 09 01 F7"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── Meta 轨道名事件 ──
    @TestCase
    func metaTrackName() {
        let input =
            "midi {\n" +
            "    format 1\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 meta 03 4D 65 6C 6F 64 79\n" +
            "    +0 tempo 500000us\n" +
            "    +0 end\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 meta 03 42 61 73 73\n" +
            "    +0 program 33 ch 1\n" +
            "    +0 on C3 64 ch 1\n" +
            "    +960 off C3 0 ch 1\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        @Assert(verifyMThd(data, 1, 2))
        let text = decompile(data)
        @Assert(text.contains("meta 03"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 大 delta 值 ──
    @TestCase
    func largeDelta() {
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
            "    +9600 on D4 80 ch 0\n" +
            "    +480 off D4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("+9600 on D4"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 多通道同一轨道 ──
    @TestCase
    func multiChannelSameTrack() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 480\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 program 24 ch 1\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +0 on E3 64 ch 1\n" +
            "    +480 off C4 0 ch 0\n" +
            "    +0 off E3 0 ch 1\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("ch 0"))
        @Assert(text.contains("ch 1"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 零力度音符 ──
    @TestCase
    func zeroVelocityNoteOff() {
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
            "    +0 on E4 80 ch 0\n" +
            "    +480 on E4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("running_status on"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 不同 TPQ ──
    @TestCase
    func differentTPQ() {
        let input =
            "midi {\n" +
            "    format 0\n" +
            "    tpq 120\n" +
            "}\n" +
            "\n" +
            "track {\n" +
            "    +0 tempo 500000us\n" +
            "    +0 program 0 ch 0\n" +
            "    +0 on C4 80 ch 0\n" +
            "    +120 off C4 0 ch 0\n" +
            "    +0 on D4 80 ch 0\n" +
            "    +120 off D4 0 ch 0\n" +
            "    +0 end\n" +
            "}\n"
        let data = generate(input)
        let text = decompile(data)
        @Assert(text.contains("tpq 120"))
        let data2 = generate(text)
        verifyBinaryIdentical(data, data2)
    }

    // ── 每个 binary 文件单独测试无损 ──
    @TestCase
    func binaryRoundTripBdth() {
        verifyBinaryFile("testcase/binary/bdth.mid")
    }

    @TestCase
    func binaryRoundTripBnsdmm() {
        verifyBinaryFile("testcase/binary/bnsdmm.mid")
    }

    @TestCase
    func binaryRoundTripCh() {
        verifyBinaryFile("testcase/binary/ch.mid")
    }

    @TestCase
    func binaryRoundTripGq() {
        verifyBinaryFile("testcase/binary/gq.mid")
    }

    @TestCase
    func binaryRoundTripLjf() {
        verifyBinaryFile("testcase/binary/ljf.mid")
    }

    @TestCase
    func binaryRoundTripLtx() {
        verifyBinaryFile("testcase/binary/ltx.mid")
    }

    @TestCase
    func binaryRoundTripPgydyd() {
        verifyBinaryFile("testcase/binary/pgydyd.mid")
    }

    @TestCase
    func binaryRoundTripQsws() {
        verifyBinaryFile("testcase/binary/qsws.mid")
    }

    @TestCase
    func binaryRoundTripQt() {
        verifyBinaryFile("testcase/binary/qt.mid")
    }

    @TestCase
    func binaryRoundTripTmmdh() {
        verifyBinaryFile("testcase/binary/tmmdh.mid")
    }

    @TestCase
    func binaryRoundTripYlxb() {
        verifyBinaryFile("testcase/binary/ylxb.mid")
    }

    func verifyBinaryFile(path: String) {
        let p = Path(path)
        if (!exists(p)) { return }
        let data = File.readFrom(p)
        if (data.size < 14) { return }
        let text = decompile(data)
        @Assert(text.contains("midi"))
        let regen = generate(text)
        @Expect(data.size, regen.size)
        verifyBinaryIdentical(data, regen)
    }
}
