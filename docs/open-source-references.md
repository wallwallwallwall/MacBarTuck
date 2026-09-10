# 开源参考

核验日期：2026-09-10。读取 GitHub API、上游 README、源码和许可证；未安装或运行这些参考软件。上游宣称支持不等于 BarTuck 已验证支持。

## 已采用

- [OverflowBar](https://github.com/EvanProgramming/OverflowBar/tree/a5f1588f8353123d2906aa18810a74e0816d1603)，MIT，核验时最近推送为 2026-09-07。既有底层来源，保留原版权。核对发现首次录屏按钮只打开设置的问题也存在于该来源中，不能因为是上游实现就跳过测试。
- [Hidden Bar 的状态栏控制器](https://github.com/dwarvesf/hidden/blob/0dde4b6882144309263ac465375971a5c39b492d/hidden/Features/StatusBar/StatusBarController.swift)，MIT，核验时最近推送为 2026-06-15。参考“移动前展开、结束后收起”和按最宽屏幕计算有界分隔项宽度的模式。BarTuck 保留自己的三态规则和托盘，宽度策略及许可记录见 `StatusItemLayoutPolicy`、`NOTICE`。

## 仅参考功能设计

- [Ice](https://github.com/jordanbaird/Ice)：GPL-3.0，核验时最近推送为 2025-09-20。参考独立托盘、项目搜索、快捷键和自动收起的交互，不复制 GPL 源码或素材进 MIT 工程。
- [Thaw](https://github.com/thaw-app/Thaw)：GPL-3.0，核验时最近推送为 2026-09-09。参考配置备份、显示器场景和问题诊断。其 [FAQ](https://github.com/thaw-app/Thaw/blob/development/FREQUENT_ISSUES.md) 明确列出多屏切换、动态菜单项身份和 macOS 27 兼容性问题，因此不照搬 README 的兼容性承诺。

## 扩展顺序

1. 先通过当前真实收纳、原生点击、恢复和双屏托盘回归，再增加扩展。
2. 优先考虑托盘快捷搜索、可配置全局快捷键、无敏感内容的本地诊断导出。
3. 其次考虑规则导入导出、临时暂停自动收起、显示器配置切换后的规则恢复。
4. 暂不增加脚本触发器、定位权限、网络账号、遥测、自动重启其他应用或全局菜单栏外观改写。

上述扩展未实现。当前不引入额外第三方二进制依赖，也不改变 MIT 许可。
