# 开源参考

核验日期：2026-09-15。读取 Apple Developer、GitHub API、上游 README、源码和许可证；未安装或运行这些参考软件。上游宣称支持不等于 MacBarTuck 已验证支持。

## 平台依据

- Apple Developer 的 [发布列表](https://developer.apple.com/news/releases/) 在 2026-09-09 提供 macOS 27.0 RC（26A428）与 Xcode 27 RC（27A266a）；[Xcode 系统要求](https://developer.apple.com/xcode/system-requirements/) 列明 Xcode 27 RC 包含 macOS 27 SDK，并支持 macOS 12 至 27 的部署目标。
- Apple 的 [最新系统提交说明](https://developer.apple.com/news/?id=k1mtkt1k) 明确建议只支持 Apple Silicon 的应用将架构固定为 `arm64`。MacBarTuck 已从项目配置、Debug/Release 构建与 DMG 校验三处限制为 `arm64`，不增加 Intel 或 Rosetta 路径。

## 已采用

- [OverflowBar](https://github.com/EvanProgramming/OverflowBar/tree/a5f1588f8353123d2906aa18810a74e0816d1603)，MIT，核验时最近推送为 2026-09-07。既有底层来源，保留原版权。核对发现首次录屏按钮只打开设置的问题也存在于该来源中，不能因为是上游实现就跳过测试。
- [Hidden Bar 的状态栏控制器](https://github.com/dwarvesf/hidden/blob/0dde4b6882144309263ac465375971a5c39b492d/hidden/Features/StatusBar/StatusBarController.swift)，MIT，核验时最近推送为 2026-06-15。参考按最宽屏幕计算有界分隔项宽度的模式。MacBarTuck 早期也参考了“移动前展开、结束后收起”，但 macOS 26 实机日志证明菜单关闭后的立即回藏会造成整排重排，0.1.10 改为显式批量重新收纳；保留自己的三态规则和托盘，许可记录见 `StatusItemLayoutPolicy`、`NOTICE`。

## 仅参考功能设计

- [Ice](https://github.com/jordanbaird/Ice)：GPL-3.0，核验时最近推送为 2025-09-20。参考独立托盘、项目搜索、快捷键和自动收起的交互，不复制 GPL 源码或素材进 MIT 工程。
- [Thaw](https://github.com/thaw-app/Thaw)：GPL-3.0，核验时最近推送为 2026-09-14。参考配置备份、显示器场景和问题诊断。0.1.11 核对了其固定提交 `0d23b56f` 中的 [应用图标回退](https://github.com/thaw-app/Thaw/blob/0d23b56fdb9d827a2d9942159ce54f1c900c26a4/Thaw/MenuBar/IceBar/MenuBarItemIconFallback.swift) 与 [0.82 高度比例](https://github.com/thaw-app/Thaw/blob/0d23b56fdb9d827a2d9942159ce54f1c900c26a4/Thaw/MenuBar/IceBar/IceBar.swift)；0.1.16 又核对提交 `934b58434a1b53c9170f7f8215479415ca5ecedc` 的 `AXHelpers.extrasMenuBar` 使用方式，确认成熟项目同样从应用的额外菜单栏读取状态项。MacBarTuck 只参考这一系统接口选择，使用现有 AppKit 代码独立实现，不复制 GPL 源码。其 [FAQ](https://github.com/thaw-app/Thaw/blob/development/FREQUENT_ISSUES.md) 记录多屏切换、动态菜单项身份、闪烁和权限等现实边界，因此不照搬上游兼容性承诺。

## 扩展顺序

1. 先通过当前真实收纳、原生点击、恢复和双屏托盘回归，再增加扩展。
2. 优先考虑托盘快捷搜索、可配置全局快捷键、无敏感内容的本地诊断导出。
3. 其次考虑规则导入导出、临时暂停自动收起、显示器配置切换后的规则恢复。
4. 暂不增加脚本触发器、定位权限、网络账号、遥测、自动重启其他应用或全局菜单栏外观改写。

上述扩展未实现。当前不引入额外第三方二进制依赖，也不改变 MIT 许可。

## 0.1.2 本地适配

已有 MIT 基础没有提供可直接复用的跨屏逻辑项目身份接口，因此按本机 WindowServer 采样补充最小关联层：必须存在本应用的对应菜单栏入口，且托管进程、相对位置、宽度及明确标题一致，才能关联跨屏窗口。歧义不合并；保留全部底层窗口用于定向点击。这是经过本机采样与回归测试的适配策略，不是 Apple 提供的稳定镜像 ID 契约。
