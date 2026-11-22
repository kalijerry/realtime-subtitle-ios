# 实时字幕（iOS 26）

把身边的声音实时变成**大字号、黑底白字**的全屏字幕。基于 iOS 26 新出的 `SpeechAnalyzer` + `SpeechTranscriber`，全程在 iPhone 本机识别，不联网、不上传音频。

## 功能

- **实时滚动字幕**：识别中先显示半透明的临时结果（volatile），确定后变成白色定稿（finalized），旧字幕逐渐变暗并从顶部淡出。
- **大字号全屏**：字号 24–80 可调，左对齐 / 居中；轻点屏幕隐藏所有控件，只剩字幕。录音时屏幕常亮；手动锁屏后靠后台音频继续转写，解锁回来字幕都在（来电等打断会自动停止并保留已有字幕）。
- **Liquid Glass 界面**：iOS 26 玻璃质感控件，相机快门式录音键，外圈随音量呼吸，顶部显示计时和声波。
- **多语言**：自动列出本机支持的语言（中文、英文、日文……），首次使用某语言会自动下载模型并显示进度。
- **历史记录**：每次录音自动保存为一条记录（录音中每确定一句就写入，不怕中途退出），可按日期浏览、搜索全文、回看、重命名、删除。
- **导出**：纯文本 `.txt`、字幕 `.srt` / `.vtt`（剪映、Premiere、Final Cut、YouTube 可直接导入）、`Markdown` 笔记（带时间戳）。录音中、录音后或在历史记录里都能通过系统分享面板发到「文件」、AirDrop、微信、备忘录等任意 App，也可以一键拷贝全文。

## 代码结构

```
LiveSubtitle/
├── App/LiveSubtitleApp.swift          入口 + 显示偏好
├── Speech/
│   ├── LiveTranscriber.swift          核心管线：麦克风 → SpeechAnalyzer → 临时/确定结果
│   └── AudioCapture.swift             AVAudioEngine 采集 + 格式转换 + 音量
├── Model/TranscriptSegment.swift      字幕段落 / 整段转写
├── Export/TranscriptExporter.swift    TXT / SRT / VTT / Markdown
└── Views/                             主界面、字幕区、控件、设置、导出面板
```

## 自动发版（GitHub Actions → TestFlight）

工作流在 `.github/workflows/ios.yml`：

| 触发 | 做什么 |
| --- | --- |
| 任何 PR / 推送 | 在 macOS 26 上用模拟器编译，确认代码能过 |
| 合并到 `main`、推送 `v*` 标签、手动运行 | 归档 → 云端自动签名 → 上传 TestFlight，构建号 = 工作流运行序号 |

不需要 Mac，也不需要在本地装证书：签名由 Xcode 的**云端托管证书**完成。只需要在仓库 **Settings › Secrets and variables › Actions** 添加四个 Secret：

| Secret 名称 | 内容 | 在哪里拿 |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10 位 Team ID | developer.apple.com › Account › Membership details |
| `ASC_KEY_ID` | API Key 的 Key ID | App Store Connect › 用户和访问 › 集成 › App Store Connect API |
| `ASC_ISSUER_ID` | Issuer ID（UUID） | 同上页面顶部 |
| `ASC_KEY_P8` | 下载的 `AuthKey_XXXXXX.p8` 文件**完整内容**（含 BEGIN/END 行） | 生成 Key 时下载，只能下载一次 |

注意：

1. 云端签名需要 API Key 有创建分发证书的权限。当前的 Key 是 **App Manager** 角色；如果「签名并上传」这一步报权限错误（例如 cloud signing permission），请在 App Store Connect 重新生成一个 **Admin** 角色的 Key，替换 `ASC_KEY_ID` 和 `ASC_KEY_P8`。
2. App Store Connect 里的 App 记录已创建（Bundle ID `com.kalijerry.realtimesubtitle`），Team ID `RLJ7LHQHT8` 已写进工程。
3. 没配好 Secret 时，上传这一步会自动跳过，不会让 CI 变红。

## 系统要求

- iOS / iPadOS 26 及以上（`SpeechAnalyzer` 是 iOS 26 新 API）
- Xcode 26 编译
