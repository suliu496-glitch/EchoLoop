# EchoLoop

**Listen closely. Loop a clip. Practice one sentence at a time.**

EchoLoop is an Android audio and video player for language listening practice. It can create timestamped sentence cues from speech recognition, play a selected sentence in a loop, and keep playback controls available when the screen is off.

[简体中文](#简体中文) · [English](#english)

[下载 Android 测试版 / Download Android prerelease](https://github.com/suliu496-glitch/EchoLoop/releases/tag/v1.0.7)

## 简体中文

EchoLoop 是一款面向精听和跟读的 Android 本地音视频播放器。它可以通过 Whisper 兼容语音识别生成带时间戳的句子列表；点击某句即可循环播放，也可以设置循环遍数后自动进入下一句。

**当前版本：** [1.0.7 测试版](https://github.com/suliu496-glitch/EchoLoop/releases/tag/v1.0.7)，支持 Android 8.0 及以上的 arm64 设备。此前无法播放的视频已在一台荣耀平板上验证；其他机型和格式仍需测试。

### 主要功能

- 导入设备上的音频和视频；媒体库只保存文件引用，不复制或移动源文件。
- 通过标点、语音停顿和时长限制，把识别结果整理成句子并编号。
- 无需 AI，直接框选时间范围并点击“添加断句”；句子可左滑编辑或删除，删除前会确认。
- 点选一句跳转试听或单句循环；支持设置遍数、跟读停顿、自动推进和录音对比。
- 拖动时间轴设置 AB 片段，微调边界，并将循环区间按媒体分别保存。
- 导入和编辑 SRT、ASS、VTT 字幕；支持中英双语轨道。
- 支持倍速、顺序播放、单曲循环、列表循环和通知栏/锁屏媒体控制。
- 支持息屏后台音频播放；横屏和平板采用自适应双栏界面。

媒体和断句的导入导出备份功能尚未实现。句子保存在应用本地，卸载应用前请留意本地数据；媒体源文件不由应用复制或移动。

### AI 语音识别与隐私

AI 断句是可选的在线功能。默认使用 Whisper 兼容接口，也可以在应用设置中填写其他兼容服务的 HTTPS 地址、模型名和语言。

只有用户主动发起识别时，EchoLoop 才会把音频发送到设置的服务商。视频音轨会先在设备上导出为临时分段；转写请求完成后，应用会删除它创建的临时音频文件。API Key 通过 Android Keystore 保存，不写入普通设置数据库。服务商的数据处理、保留期限和费用由其自身政策决定。

### 构建

要求 Flutter stable（Dart 3.12.2 或更高版本）、Android SDK、JDK 17 和 Android arm64 构建工具。Gradle 构建会从上游获取 media_kit Android 原生播放依赖，因此首次构建需要网络连接。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

应用最低支持 Android 8.0（API 26），当前配置只构建 `arm64-v8a`。构建和签名说明见 [`docs/05-构建与发布.md`](docs/05-构建与发布.md)。

### 文档

- [使用说明和 AI 断句](docs/06-使用说明.md)
- [架构设计](docs/01-架构设计.md)
- [数据库设计](docs/02-数据库设计.md)
- [测试与验证](docs/04-测试与验证.md)
- [手动断句与备份设计（备份尚未实现）](docs/09-手动断句与备份设计.md)
- [第三方组件声明](THIRD_PARTY_NOTICES.md)
- [贡献指南](CONTRIBUTING.md)

## English

EchoLoop is a local Android audio and video player for focused listening and shadowing practice. It can turn speech recognition results into timestamped sentence cues. Tap a sentence to replay it, or set a repeat count and advance automatically to the next one.

**Current release:** [1.0.7 prerelease](https://github.com/suliu496-glitch/EchoLoop/releases/tag/v1.0.7), for arm64 devices running Android 8.0 or later. A previously failing video has been verified on one Honor tablet; other devices and formats still need testing.

### Features

- Import local audio and video. The library stores file references and does not copy or move source media.
- Split recognition results into numbered sentence cues using punctuation, pauses, and duration limits.
- Manually select a time range and add a sentence without AI; swipe a sentence left to edit or delete it, with confirmation before deletion.
- Seek to or loop a sentence; configure repeat counts, speaking gaps, automatic advance, and recording comparison.
- Set and fine-tune AB loops on a timeline; loop settings are saved per media item.
- Import and edit SRT, ASS, and VTT subtitles, including bilingual tracks.
- Playback speed, sequential playback, repeat-one, repeat-all, and lock-screen/notification controls.
- Background audio playback with the screen off and adaptive layouts for landscape and tablets.

Exporting and importing backups of media and sentence cues is not implemented yet. Sentence cues are stored locally in the app; take care with local data before uninstalling. Source media is not copied or moved by the app.

### AI transcription and privacy

AI sentence segmentation is an optional online feature. EchoLoop defaults to a Whisper-compatible API and lets you configure another compatible HTTPS endpoint, model, and language in the app.

Audio is sent to the configured provider only when you start transcription. For video, EchoLoop extracts temporary audio chunks on device and removes the files it created after the request finishes. The API key is stored through Android Keystore, not in the ordinary settings database. The provider controls its own data retention, processing, and pricing.

### Build

You need Flutter stable with Dart 3.12.2 or later, the Android SDK, JDK 17, and Android arm64 build tools. Gradle retrieves the upstream media_kit Android playback artifact, so network access is required for the first build.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

The minimum Android version is Android 8.0 (API 26). The current build targets `arm64-v8a`. See [`docs/05-构建与发布.md`](docs/05-构建与发布.md) for build and signing details.

### License

EchoLoop is licensed under **GNU GPL-3.0-only**. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Third-party components retain their own licenses.
