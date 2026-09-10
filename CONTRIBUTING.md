# 参与 NotchShelf 开发

感谢参与 NotchShelf。提交改动前请先确认目标仍是 Apple Silicon、macOS 15+ 和本地优先的菜单栏工具。

## 开发环境

- Apple Silicon Mac。
- macOS 15.0 或更高版本。
- Xcode 16 或更高版本。

## 验证命令

```bash
./scripts/run-unit-tests.sh

xcodebuild \
  -project NotchShelf.xcodeproj \
  -scheme NotchShelf \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath work/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

界面改动可以使用安全预览，不会创建菜单栏宿主或移动真实图标：

```bash
open -n work/DerivedData-Debug/Build/Products/Debug/NotchShelf.app \
  --args --ui-preview --ui-preview-tab=status

open -n work/DerivedData-Debug/Build/Products/Debug/NotchShelf.app \
  --args --ui-preview --ui-preview-onboarding

open -n work/DerivedData-Debug/Build/Products/Debug/NotchShelf.app \
  --args --ui-preview --ui-preview-panel
```

## 提交要求

- 保留 `LICENSE` 和 `NOTICE` 中的 OverflowBar 署名与固定来源提交。
- 不引入遥测、账号、云同步或不必要的网络依赖。
- 菜单栏移动逻辑的改动必须覆盖负坐标扩展屏、刘海安全区和恢复路径。
- 新增规则行为时，为 `Tests/OverflowPolicyTests.swift` 增加直接测试。
- 不提交 `work/`、`dist/`、Xcode 用户状态或本机权限数据。

涉及真实菜单栏移动的测试，请先退出 iBar、Bartender、Ice 等同类工具，并确认重要工作已保存。测试完成后执行“安全重置”，确认所有项目恢复可见。
