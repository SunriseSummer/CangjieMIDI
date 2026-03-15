# MIDI 文件格式详解

本文档介绍标准 MIDI 文件（`.mid`）的二进制编码格式，并结合 CangjieMIDI 项目源码说明仓颉语言的实现方式。

---

## 一、格式总览

标准 MIDI 文件由一个**文件头（MThd）**和一个或多个**轨道块（MTrk）**组成。所有多字节整数均采用**大端序**（Big-Endian）。

```
┌──────────────────┐
│   MThd（文件头）   │  14 字节（固定）
├──────────────────┤
│   MTrk（轨道 0）   │  可变长度
├──────────────────┤
│   MTrk（轨道 1）   │  可变长度
├──────────────────┤
│       ...        │
└──────────────────┘
```

### 区块/字段速查表

| 区块 | 标识 | 长度 | 说明 |
|------|------|------|------|
| **MThd** | `4D 54 68 64` | 14 字节 | 文件头，含格式、轨道数、时间分辨率 |
| — 标识符 | `MThd` (4B) | 4 字节 | ASCII 字符 `M` `T` `h` `d` |
| — 数据长度 | `00 00 00 06` | 4 字节 | 固定为 6（后续头数据长度） |
| — 格式 | `00 00` / `00 01` | 2 字节 | 0 = 单轨道, 1 = 多轨道同步 |
| — 轨道数 | UInt16 | 2 字节 | 文件中包含的 MTrk 块数量 |
| — 时间分辨率 | UInt16 | 2 字节 | 每四分音符的 tick 数（TPQ，常用 480） |
| **MTrk** | `4D 54 72 6B` | 可变 | 轨道块，包含事件序列 |
| — 标识符 | `MTrk` (4B) | 4 字节 | ASCII 字符 `M` `T` `r` `k` |
| — 数据长度 | UInt32 | 4 字节 | 后续轨道数据的字节数 |
| — 事件序列 | Delta + Event | 可变 | 由 VLQ 时间偏移 + 事件数据交替组成 |

---

## 二、MThd 文件头

文件头为固定 14 字节结构：

```
字节偏移:  00 01 02 03 | 04 05 06 07 | 08 09 | 10 11 | 12 13
内容:      4D 54 68 64 | 00 00 00 06 | FF FF | NN NN | TT TT
含义:      "MThd"标识  | 头数据长度=6 | 格式   | 轨道数 | TPQ
```

### 格式（Format）

| 值 | 含义 |
|----|------|
| `0` | **单轨道**：所有通道的事件写在一个 MTrk 中 |
| `1` | **多轨道同步**：多个 MTrk 并行，轨道 0 通常放 Tempo 等全局事件 |
| `2` | **多轨道独立**：多个 MTrk 顺序播放（较少使用） |

### 时间分辨率（TPQ）

TPQ = Ticks Per Quarter note，定义四分音符的精度。常见值：

| TPQ | 说明 |
|-----|------|
| 480 | 最常用，足以精确表达 32 分音符和三连音 |
| 96  | 简单编曲 |
| 960 | 高精度专业制作 |

**CangjieMIDI 默认使用 TPQ = 480。**

---

## 三、MTrk 轨道块

每个轨道块包含一系列**事件**，每个事件由 **Delta Time**（时间偏移）和**事件数据**两部分组成。

```
MTrk:
  4D 54 72 6B          ← "MTrk" 标识
  LL LL LL LL          ← 轨道数据长度（UInt32）
  [Delta][Event]       ← 第 1 个事件
  [Delta][Event]       ← 第 2 个事件
  ...
  [Delta][FF 2F 00]    ← End of Track（必须）
```

---

## 四、VLQ 变长数值编码

Delta Time 使用 **VLQ（Variable Length Quantity）** 编码，以节省空间：

### 编码规则

- 每个字节使用低 7 位存储数据，最高位为**延续标志**
- 最高位 = 1：后续还有字节
- 最高位 = 0：当前字节为最后一个字节

### 示例

| 十进制值 | VLQ 编码 | 说明 |
|----------|----------|------|
| 0 | `00` | 1 字节 |
| 127 | `7F` | 1 字节最大值 |
| 128 | `81 00` | 2 字节 |
| 480 | `83 60` | 常见的四分音符 tick |
| 960 | `87 40` | 二分音符 tick |
| 16383 | `FF 7F` | 2 字节最大值 |
| 100000 | `86 8D 20` | 3 字节 |

### 解码算法

```
value = 0
循环:
    读取一个字节 b
    value = (value << 7) | (b & 0x7F)
    如果 (b & 0x80) == 0，结束循环
```

---

## 五、MIDI 事件类型

MIDI 事件分为三大类：**通道事件**、**元事件**、**系统独占事件**。

### 5.1 通道事件

通道事件的状态字节格式：`高4位=事件类型，低4位=通道号(0~15)`

| 状态字节 | 事件类型 | 数据字节 | 说明 |
|----------|----------|----------|------|
| `8n` | **Note Off** | 音高 + 力度 | 音符松键（n=通道号） |
| `9n` | **Note On** | 音高 + 力度 | 音符按键（力度=0 等效 Note Off） |
| `An` | **Aftertouch** | 音高 + 压力 | 触后（逐键） |
| `Bn` | **Control Change** | 控制器号 + 值 | 控制器变化（CC） |
| `Cn` | **Program Change** | 音色号 | 切换乐器音色（GM 标准 0~127） |
| `Dn` | **Channel Pressure** | 压力值 | 通道触后（整体） |
| `En` | **Pitch Bend** | LSB + MSB | 弯音（14 位，中心值 8192） |

#### Running Status（运行状态）

当连续的通道事件具有相同的状态字节时，后续事件可以**省略状态字节**，只写数据字节。这被称为 Running Status，可显著减小文件体积。

```
正常编码:  90 3C 50  90 40 50  90 43 50    ← 9 字节
运行状态:  90 3C 50  40 50  43 50          ← 7 字节（省略重复的 90）
```

解码时，如果读到的字节 < 0x80，则沿用上一个状态字节。

### 5.2 元事件（Meta Event）

元事件以 `FF` 开头，不发送到 MIDI 设备，仅用于文件内标注信息。

```
FF <类型> <VLQ长度> <数据>
```

| 类型字节 | 名称 | 数据长度 | 说明 |
|----------|------|----------|------|
| `00` | Sequence Number | 2 | 序列号 |
| `01` | Text | 可变 | 文本注释 |
| `02` | Copyright | 可变 | 版权信息 |
| `03` | Track Name | 可变 | 轨道名称 |
| `04` | Instrument Name | 可变 | 乐器名称 |
| `05` | Lyric | 可变 | 歌词 |
| `06` | Marker | 可变 | 标记 |
| `07` | Cue Point | 可变 | 提示点 |
| `20` | Channel Prefix | 1 | 通道前缀 |
| `2F` | **End of Track** | 0 | 轨道结束标记（必须） |
| `51` | **Set Tempo** | 3 | 速度（微秒/四分音符） |
| `54` | SMPTE Offset | 5 | SMPTE 时间偏移 |
| `58` | Time Signature | 4 | 拍号 |
| `59` | Key Signature | 2 | 调号 |
| `7F` | Sequencer-Specific | 可变 | 厂商私有数据 |

#### Tempo（速度）事件详解

Tempo 以 **微秒/四分音符** 存储，3 字节大端整数：

```
FF 51 03 <tt tt tt>
```

| BPM | 微秒值 | 字节表示 |
|-----|--------|----------|
| 60  | 1,000,000 | `0F 42 40` |
| 120 | 500,000 | `07 A1 20` |
| 140 | 428,571 | `06 8A 1B` |

**换算公式**: `微秒 = 60,000,000 / BPM`，`BPM = 60,000,000 / 微秒`

### 5.3 系统独占事件（SysEx）

SysEx 事件用于传输厂商特定数据：

```
F0 <VLQ长度> <数据...>    ← 标准 SysEx（以 F7 结尾）
F7 <VLQ长度> <数据...>    ← 转义 SysEx / 延续
```

---

## 六、音高编码

MIDI 使用 0~127 的整数表示音高：

| 音名 | MIDI 编号 | 说明 |
|------|-----------|------|
| C-1 | 0 | 最低音 |
| A0 | 21 | 钢琴最低音 |
| C4 | 60 | **中央 C** |
| A4 | 69 | 标准音 440Hz |
| C8 | 108 | 钢琴最高音 |
| G9 | 127 | 最高音 |

**计算公式**: `MIDI 编号 = (八度 + 1) × 12 + 音名偏移`

| 音名 | C | C# | D | D# | E | F | F# | G | G# | A | A# | B |
|------|---|-----|---|-----|---|---|-----|---|-----|---|-----|---|
| 偏移 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |

---

## 七、实例：一个最小 MIDI 文件

以下是一个包含单音符 C4 四分音符（TPQ=480）的完整 MIDI 文件（十六进制）：

```
4D 54 68 64    ← "MThd"
00 00 00 06    ← 头数据长度 = 6
00 00          ← 格式 0（单轨道）
00 01          ← 1 个轨道
01 E0          ← TPQ = 480

4D 54 72 6B    ← "MTrk"
00 00 00 14    ← 轨道数据长度 = 20

00 FF 51 03    ← Delta=0, Set Tempo
07 A1 20       ← 500000 微秒 = 120 BPM
00 C0 00       ← Delta=0, Program Change ch0 乐器 0
00 90 3C 50    ← Delta=0, Note On C4 力度80
83 60 80 3C 00 ← Delta=480(VLQ=83 60), Note Off C4
00 FF 2F 00    ← Delta=0, End of Track
```

---

## 八、仓颉编程实现

CangjieMIDI 项目使用仓颉（Cangjie）编程语言实现了完整的 MIDI 编解码器。以下是核心实现概述。

### 8.1 项目架构

```
src/
├── core/                    ← 核心模块
│   ├── types.cj             ← 数据模型（NoteInfo, ChordInfo, TrackData, ScoreData）
│   ├── parser.cj            ← 统一语言解析器（乐谱模式）
│   ├── parser_utils.cj      ← 解析辅助工具（VLQ、时值转换）
│   ├── parser_note.cj       ← 音符/和弦解析
│   └── instrument.cj        ← GM 乐器映射表（128 音色）
├── encoder/                 ← 编码器模块
│   ├── encoder.cj           ← 统一编码入口（乐谱模式 + 事件模式）
│   ├── event.cj             ← MIDI 事件类型与底层字节编码
│   └── utils.cj             ← 格式检测、十六进制解析、文件组装
└── decoder/                 ← 解码器模块
    ├── decoder.cj           ← 无损反编译器（二进制 → 事件模式文本）
    ├── binary.cj            ← 大端读取、VLQ 解码
    └── note.cj              ← 音高 → 音名转换
```

### 8.2 VLQ 编码实现

VLQ 编码在 `src/encoder/event.cj` 中实现。每 7 位一组，高位字节设置延续标志 `0x80`：

```cangjie
public func encodeVLQ(value: UInt32): ArrayList<UInt8> {
    let result = ArrayList<UInt8>()
    if (value == 0) { result.add(0); return result }
    var v = value
    let temp = ArrayList<UInt8>()
    while (v > 0) {
        temp.add(UInt8(v & 0x7F))  // 取低 7 位
        v = v >> 7
    }
    // 反转输出，高位字节设置 continuation bit
    var i = Int64(temp.size) - 1
    while (i >= 0) {
        var b = temp[i]
        if (i > 0) { b = b | 0x80 }  // 非最后字节设置延续标志
        result.add(b)
        i--
    }
    result
}
```

VLQ 解码在 `src/decoder/binary.cj` 中实现：

```cangjie
func decReadVLQ(data: Array<UInt8>, pos: Int64, end: Int64): DecVLQ {
    var value: UInt32 = 0
    var i = pos
    while (i < end) {
        let b = data[i]
        value = (value << 7) | UInt32(b & 0x7F)
        i++
        if ((b & 0x80) == 0) { break }  // 最高位为 0 表示结束
    }
    DecVLQ(value, i)
}
```

### 8.3 MIDI 事件编码

事件使用枚举类型建模（`src/encoder/event.cj`），状态字节的高 4 位表示事件类型，低 4 位表示通道号：

```cangjie
func encodeEvent(event: MidiEvent): ArrayList<UInt8> {
    let result = ArrayList<UInt8>()
    match (event.kind) {
        case NoteOn =>
            result.add(0x90 | event.channel)   // 状态: 1001nnnn
            result.add(event.data1)            // 音高
            result.add(event.data2)            // 力度
        case NoteOff =>
            result.add(0x80 | event.channel)   // 状态: 1000nnnn
            result.add(event.data1)            // 音高
            result.add(event.data2)            // 力度
        case ProgramChange =>
            result.add(0xC0 | event.channel)   // 状态: 1100nnnn
            result.add(event.data1)            // 音色号
        case SetTempo =>
            result.add(0xFF); result.add(0x51); result.add(0x03)
            result.add(event.data1)            // 微秒高字节
            result.add(event.data2)            // 微秒中字节
            result.add(event.data3)            // 微秒低字节
        case EndOfTrack =>
            result.add(0xFF); result.add(0x2F); result.add(0x00)
        // ... 其他事件类型
    }
    result
}
```

### 8.4 文件组装

编码器将所有轨道数据组装为完整 MIDI 文件（`src/encoder/utils.cj`）：

```cangjie
func assembleMidiFile(trackDataList: ArrayList<ArrayList<UInt8>>,
                      format: UInt16, tpq: UInt16): Array<UInt8> {
    let result = ArrayList<UInt8>()
    // MThd 标识
    result.add(0x4D); result.add(0x54); result.add(0x68); result.add(0x64)
    writeUInt32BE(result, 6)                  // 头数据长度
    writeUInt16BE(result, format)              // 格式 (0 或 1)
    writeUInt16BE(result, UInt16(trackCount))  // 轨道数
    writeUInt16BE(result, tpq)                 // TPQ
    // 依次写入每个 MTrk 块
    for (td in trackDataList) {
        result.add(0x4D); result.add(0x54); result.add(0x72); result.add(0x6B)
        writeUInt32BE(result, UInt32(td.size)) // 轨道数据长度
        for (b in td) { result.add(b) }
    }
    result.toArray()
}
```

### 8.5 反编译器（Running Status 检测）

反编译器（`src/decoder/decoder.cj`）将二进制 `.mid` 文件解析为事件模式文本。解码时需要处理 Running Status：

```cangjie
// 如果字节 >= 0x80，则为新的状态字节
if (firstByte >= 0x80) {
    runningStatus = firstByte  // 记录当前状态
    // 正常解码事件...
} else {
    // firstByte < 0x80，使用 Running Status
    let eventType = runningStatus & 0xF0
    let channel = runningStatus & 0x0F
    // 用上一次的状态字节解码...
}
```

反编译器会自动检测原始文件是否使用了 Running Status，并在事件模式输出的 `midi {}` 头中标注 `running_status on`，确保再编译时生成完全相同的二进制。

### 8.6 编解码流程

```
乐谱模式编码:  文本 → parseScore() → ScoreData → buildTrackEvents() → encodeTrackChunk() → .mid
事件模式编码:  文本 → generateEvent() → 逐行解析 +delta 事件 → assembleMidiFile() → .mid
反编译:        .mid → decompile() → 事件模式文本

无损回环:      .mid → decompile() → 文本 → generateEvent() → .mid（逐字节一致）
```
