# EasyDisplay - macOS 局域网投屏与扩展服务端

`EasyDisplay` 是一款专为 macOS 开发的高性能局域网屏幕投屏与扩展服务端应用。它支持通过有线（USB/充电线网络）或无线（Wi-Fi / Bonjour）将 Mac 的屏幕画面实时推送到客户端（如 iPad 或其他设备）。

---

##  核心功能特性

* **局域网自动发现**：基于 `Network.framework` 实现 Bonjour 服务端自动广播（服务类型 `_easydisplay._tcp`），客户端可自动搜索连接。
* **多模网络支持**：完美支持 Wi-Fi 无线连接，以及通过 USB 充电线直连（网卡模式）的高带宽、低延迟传输。
* **高性能屏幕捕获**：集成现代 macOS `ScreenCaptureKit` 框架，精准锁定并高效捕获目标显示器画面。
* **硬件级编码**：深度结合 `VideoToolbox` 框架（`VTCompressionSession`），实现低延迟 H.264 硬件视频编码与 SPS/PPS 参数头实时封装。
* **简洁现代的 UI**：基于 SwiftUI 构建的控制面板，支持自定义服务名称与监听端口，并提供实时的运行状态与连接反馈。

---

##  技术栈

* **语言**：Swift 5.0+
* **界面**：SwiftUI
* **底层框架**：
  * `ScreenCaptureKit`（画面捕获）
  * `VideoToolbox`（H.264 硬件编码）
  * `Network.framework`（TCP 网络传输与 Bonjour 广播）
  * `CoreGraphics` / `Combine`

---

##  项目结构

```text
EasyDisplay/
├── EasyDisplayApp.swift    # 应用入口，初始化 SwiftUI 窗口生命周期
├── ContentView.swift       # 控制面板 UI，管理服务配置与交互逻辑
└── MacBonjourServer.swift  # 核心服务类：处理 Bonjour 广播、TCP 连接、屏幕捕获与 H.264 硬编码
