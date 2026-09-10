# 程序坞与状态栏入口

0.1.4 使用 AppKit 的 applicationDockMenu 和 setActivationPolicy 实现本应用的程序坞行为，不修改系统 Dock 配置，也不影响其他软件。

- 默认显示程序坞图标；通用页与状态栏菜单共享同一设置，重启后保留。
- 程序坞菜单添加“设置”和“隐藏程序坞图标”；标准的隐藏、显示和退出由 macOS 提供，避免重复菜单项。
- 状态栏左键保持展开托盘；右键或 Control 点按显示应用菜单，包含设置、程序坞开关、隐藏窗口和退出。
- 隐藏窗口不退出进程；设置入口会重新显示窗口。关闭最后一个窗口也不会退出菜单栏服务。
- 所有退出入口使用 NSApplication.terminate，继续执行已有的布局恢复和结束流程。
- 程序坞激活策略失败时保留原设置并报告错误；预览模式只更新内存状态。

Apple API 依据（2026-09-10 核对）：[applicationDockMenu](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:))、[setActivationPolicy](https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:))。

自动化验证覆盖默认值、启动策略、持久化、隐藏后恢复、错误保留、预览隔离、菜单状态同步、操作分发及隐藏后仍可访问设置和退出，共 19 项；这些测试不代替系统菜单的交互验收。

## 实际验证

2026-09-10，在标准应用目录的 0.1.4 上验证：

- 关闭页面中的程序坞开关后，进程保持运行，系统激活策略由 regular 变为 accessory，设置值保存为 false。
- 页面“退出”后进程确实结束；再次打开应用可进入设置，程序坞隐藏选择保留。
- 恢复开关后激活策略回到 regular，设置值保存为 true。
- 标准“隐藏”动作后进程保持运行且 isHidden 为 true；重新打开后同一进程恢复显示。
- 发现 AppKit 对已经生效的策略返回 false，已补先失败后通过的回归，避免隐藏状态重启时误报错误。
- 程序坞菜单返回值和状态栏菜单的设置、隐藏、退出分发均经自动化检查。Computer Use 无法定位系统 Dock 窗口及跨进程托管的状态栏点击目标，因此两个系统菜单的直接点击尚未验收。

通用页截图已更新。此次不以程序坞测试代表真实菜单项收纳、恢复或转发点击通过；这些功能的权限与验证边界仍见 runtime-qa.md。
