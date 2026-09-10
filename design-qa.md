# NotchShelf Design QA

final result: passed

检查日期：2026-09-10

## 设计目标

- 参考现有菜单栏收纳工具的功能结构，不复制其侧边栏布局、配色和商业入口。
- 使用深色石墨背景、青色主强调、绿色状态和红色风险提示，避免大面积纯白。
- 保持 macOS 原生观感，字体与图标采用系统 SF Pro / SF Symbols，交互控件使用 SwiftUI 原生组件。
- 状态、项目、偏好三页均以高频任务为首要信息，不放营销内容。

## 参考图

- 参考图 1：859 x 658，设置与功能层级参考。
- 参考图 2：861 x 656，项目规则参考。
- 参考图 3：413 x 80，菜单栏托盘参考。

参考图仅用于确定功能范围与信息优先级。NotchShelf 改为顶部导航、紧凑信息带和独立安全预览，未复刻原应用布局。

## 实现截图

- `docs/screenshots/settings.png`：780 x 560，状态页。
- `docs/screenshots/items.png`：780 x 560，项目页与自动、常显、收纳三态规则。
- `docs/screenshots/preferences.png`：780 x 560，偏好页与安全重置。
- `docs/screenshots/onboarding.png`：760 x 560，引导第 1 步。
- `docs/screenshots/onboarding-permissions.png`：760 x 560，引导第 2 步。
- `docs/screenshots/onboarding-customize.png`：760 x 560，引导第 3 步。
- `docs/screenshots/onboarding-ready.png`：760 x 560，引导第 4 步。
- `docs/screenshots/overflow-panel.png`：720 x 260，托盘安全预览。

## 检查结果

- 状态页：标题、运行状态、双显示器、安全宽度、托盘预览和权限入口层级清晰。
- 项目页：搜索、数量、刷新和三态分段控件可辨识，系统安全项目标记明确。
- 偏好页：开关、布局恢复、重新引导、安全重置和退出操作没有遮挡或截断。
- 四步引导：进度、权限、规则说明、完成状态和主操作在 760 x 560 下均完整可见。
- 托盘：图标槽位尺寸稳定，暗色表面、描边和状态文案与主界面一致。
- 字体、间距、颜色、图标资产和中文文案均无剩余 P0、P1、P2 问题。

## 已修复问题

- P2：托盘预览最初随预览窗口横向拉宽，不能准确反映实际组件尺寸。已改为按收纳项目数量计算固定宽度，并在 `overflow-panel.png` 中复查通过。
- P2：关闭自动避让后执行“全部自动”，安全预览仍显示两个自动项目被收纳。已统一预览选择策略，并增加关闭、恢复和受保护项目优先级回归测试。

真实菜单栏移动未纳入本次视觉 QA：当前机器正在运行 iBar，为避免两个工具竞争系统菜单栏，仅使用不会创建 `NSStatusItem` 或移动图标的 `--ui-preview` 模式完成界面验证。
