# 🎵 CangjieMIDI：MIDI 编程语言 & 编解码工具

乐谱“编程”语言，支持乐谱语言与MIDI文件之间的双向转换。

采用**统一语言设计**，融合两种模式：
- **乐谱模式** — 人类友好的音乐记谱，像编程一样灵活（变量、块结构）
- **事件模式** — 无损精确的 MIDI 事件表达，保证与 `.mid` 文件逐字节一致

---

## MIDI / 音乐基础概念

| 概念 | 说明 |
|------|------|
| **MIDI**            | Musical Instrument Digital Interface，数字音乐的通用标准协议 |
| **`.mid` 文件**     | 标准 MIDI 文件，存储音乐事件序列的二进制格式                 |
| **MThd / MTrk**     | MIDI 文件头 / 轨道块                                         |
| **Format 0/1**      | MIDI 格式：0 = 单轨道，1 = 多轨道                            |
| **TPQ**             | Ticks Per Quarter note，每四分音符的 tick 数（常见：480）    |
| **Delta Time**      | 相邻事件之间的 tick 间隔                                     |
| **VLQ**             | Variable Length Quantity，变长数值编码                       |
| **Note On / Off**   | 音符按键 / 松键事件                                          |
| **音高 (Pitch)**    | MIDI 音高编号 0~127，C4（中央 C）= 60                        |
| **力度 (Velocity)** | 按键力度 0~127                                               |
| **BPM**             | Beats Per Minute，每分钟拍数                                 |
| **Tempo**           | MIDI 以 "微秒/四分音符" 存储，1000000 微秒对应 60 BPM        |
| **GM**              | General MIDI 标准，128 种乐器音色                            |
| **Channel**         | 16 个通道（0~15），通道 9 专用于打击乐                       |
| **CC**              | Control Change，控制器变化（音量/声像/延音等）               |
| **Pitch Bend**      | 弯音，连续改变音高                                           |
| **Running Status**  | 连续相同状态字节时省略以节省空间                             |

---

## 项目架构

```
midi/
├── cjpm.toml                     # 项目配置
├── README.md                     # 本文件
├── src/
│   ├── main.cj                   # 程序入口与 CLI
│   ├── verifier.cj               # MIDI 验证工具
│   ├── verifier_utils.cj         # 验证辅助函数
│   ├── midi_test.cj              # 测试辅助（verifyBinaryIdentical）
│   ├── encode_test.cj            # 编码测试（乐谱模式）
│   ├── decode_test.cj            # 解码测试（事件模式 + 无损回环）
│   ├── core/                     # 核心数据类型与解析
│   │   ├── types.cj              #   数据模型（ScoreData, TrackData, MusicElement）
│   │   ├── parser.cj             #   统一语言解析器（parseScore）
│   │   ├── parser_utils.cj       #   解析辅助工具
│   │   ├── parser_note.cj        #   音符解析
│   │   └── instrument.cj         #   GM 标准乐器映射表
│   ├── encoder/                  # 编码器（文本 → MIDI 二进制）
│   │   ├── encoder.cj            #   统一编码入口（generate）
│   │   ├── event.cj              #   MIDI 事件定义与底层编码
│   │   └── utils.cj              #   编码器工具函数
│   └── decoder/                  # 解码器（MIDI 二进制 → 文本）
│       ├── decoder.cj            #   统一解码入口（decompile）
│       ├── binary.cj             #   二进制读取工具
│       └── note.cj               #   MIDI 编号 → 音名转换
└── testcase/					#   测试用例
    ├── source/                   #   乐谱源文件
    └── binary/                   #   .mid 文件
```

---

## 构建与测试

```bash
# 下载 Cangjie SDK
curl -sL -o cangjie-sdk.tar.gz \
  https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz
tar xzf cangjie-sdk.tar.gz && rm cangjie-sdk.tar.gz

# 构建
source cangjie/envsetup.sh
cd midi
cjpm build

# 运行测试
cjpm test
```

---

## 命令行用法

```bash
# 编译：乐谱 → .mid
midi testcase/source/                          # 编译目录下所有 .txt
midi testcase/source/10_swan_lake_full.txt     # 编译单个文件

# 反编译：.mid → 事件格式文本（无损）
midi -d testcase/binary/ch.mid                 # 反编译单个文件
midi --decompile testcase/binary/              # 反编译整个目录
```

---

## 统一语言设计

本项目使用**一种语言、两种模式**，自动检测输入格式：

| 特性 | 乐谱模式 | 事件模式 |
|------|---------|---------|
| **适用场景** | 人类编写音乐 | 无损 `.mid` 表达 |
| **格式标识** | 以 `tempo` / `track` / `let` 等开头 | 以 `midi {` 开头 |
| **编码** | ✅ `generate()` | ✅ `generate()` |
| **解码输出** | — | ✅ `decompile()` / `-d`（始终无损） |
| **可读性** | ⭐⭐⭐ 高 | ⭐⭐ 中 |
| **二进制还原** | 不保证（创作用途） | ✅ 无损（逐字节一致） |

### 无损保证

反编译（`decompile`）输出事件模式格式，保证：
- 逐事件、逐字节、逐 tick 精确保留所有 MIDI 信息
- 反编译后重编码产生**二进制完全一致**的 `.mid` 文件
- 包含 Running Status 标记，确保压缩行为一致
- 已通过 11 个外部 `.mid` 文件的无损回环测试

---

## 一、乐谱模式语法

像编程一样写音乐 — 支持变量、块结构、灵活的音符表达。

### 全局指令

| 指令 | 说明 | 示例 |
|------|------|------|
| `tempo <bpm>` | 设定全局速度 | `tempo 120` |
| `let <名> = { ... }` | 定义变量（可复用片段） | `let theme = { C4:4 D4:4 }` |
| `track <名称> { ... }` | 轨道块 | `track melody { ... }` |

### 轨道内指令

| 指令 | 说明 | 示例 |
|------|------|------|
| `instrument "名称"` | 设定乐器（GM 标准名） | `instrument "piano"` |
| `velocity <0-127>` | 设定力度 | `velocity 90` |
| `channel <0-15>` | 指定 MIDI 通道 | `channel 9` |
| `tempo <bpm>` | 轨道内变速 | `tempo 100` |
| `cc <控制器> <值>` | 控制器变化 | `cc 64 127` |
| `pitch_bend <lsb> <msb>` | 弯音控制 | `pitch_bend 0 64` |

### 音符语法

| 语法 | 说明 | 示例 |
|------|------|------|
| `<音名>:<时值>` | 单音符 | `C4:4`（四分音符 C4） |
| `<音名>#` | 升半音 | `C#4:8`（八分音符 C#4） |
| `<音名>b` | 降半音 | `Bb3:2`（二分音符 Bb3） |
| `:<时值>.` | 附点（时值 ×1.5） | `C4:4.`（附点四分音符） |
| `:T<ticks>` | 原始 tick 时值 | `C4:T216` |
| `_:<时值>` | 休止符 | `_:4`（四分休止符） |
| `[<音名>...]:<时值>` | 和弦 | `[C3 E3 G3]:2` |

### 标准时值

| 时值 | 名称 | ticks (TPQ=480) |
|------|------|-----------------|
| `1` | 全音符 | 1920 |
| `2` | 二分音符 | 960 |
| `4` | 四分音符 | 480 |
| `8` | 八分音符 | 240 |
| `16` | 十六分音符 | 120 |
| `32` | 三十二分音符 | 60 |

### 乐谱模式完整示例

```
tempo 132 // 全局速度

// 把重复出现的和弦定义为变量，减少冗余编码
let Am = { [A3 C4 E4]:2 }
let Em = { [E3 G#3 B3]:2 }

track melody {          // 声明音轨
    instrument "violin" // 声明乐器
    A4:4  B4:4  C5:4  D5:4 // 音符序列，同一音轨中从左往右、自上而下播放
    E5:4  D5:4  C5:4  B4:4
    A4:4  G#4:4  A4:4  B4:4
    C5:4  B4:4  A4:2
}

track harmony {         // 和其他音轨并发执行
    instrument "strings"
    Am Am               // 引用变量
    Em Am
    Am Em
    Am Em
}

track bass {
    instrument "bass"
    A2:2  C3:2
    E2:2  A2:2
    A2:2  E2:2
    A2:2  E2:2
}
```

---

## 二、事件模式语法

由 `decompile()` / `-d` 输出，用于 `.mid` 文件的无损表达。

### 文件头

```
midi {
    format 1
    tpq 480
    running_status on    // 可选
}
```

### 轨道事件

每行格式：`+<delta> <事件类型> <参数...>`

```
track {
    +0 tempo 500000us
    +0 program 0 ch 0
    +0 on C4 80 ch 0
    +480 off C4 0 ch 0
    +0 end
}
```

### 事件类型速查

| 事件 | 格式 | 示例 |
|------|------|------|
| Note On | `+<δ> on <音名> <力度> ch <通道>` | `+0 on C4 80 ch 0` |
| Note Off | `+<δ> off <音名> <力度> ch <通道>` | `+480 off C4 0 ch 0` |
| Program Change | `+<δ> program <编号> ch <通道>` | `+0 program 0 ch 0` |
| Control Change | `+<δ> cc <控制器> <值> ch <通道>` | `+0 cc 64 127 ch 0` |
| Pitch Bend | `+<δ> pitch_bend <LSB> <MSB> ch <通道>` | `+0 pitch_bend 0 64 ch 0` |
| Aftertouch | `+<δ> aftertouch <音名> <压力> ch <通道>` | `+0 aftertouch C4 80 ch 0` |
| Pressure | `+<δ> pressure <值> ch <通道>` | `+0 pressure 64 ch 0` |
| Set Tempo | `+<δ> tempo <微秒>us` | `+0 tempo 500000us` |
| Meta | `+<δ> meta <类型hex> <数据hex...>` | `+0 meta 03 50 69 61 6E 6F` |
| SysEx | `+<δ> sysex <状态hex> <数据hex...>` | `+0 sysex F0 7E 7F 09 01 F7` |
| End of Track | `+<δ> end` | `+0 end` |

## 三、常用 CC 控制器编号

| CC 编号 | 名称 | 说明 |
|---------|------|------|
| 1 | Modulation | 调制轮 |
| 7 | Volume | 音量 |
| 10 | Pan | 声像（左右位置） |
| 11 | Expression | 表情控制 |
| 64 | Sustain | 延音踏板（0=关, 127=开） |
| 91 | Reverb | 混响量 |
| 93 | Chorus | 合唱量 |
