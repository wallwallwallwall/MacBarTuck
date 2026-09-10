import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager
    let onComplete: (Bool) -> Void

    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var hideSelectedIcons: Bool

    init(
        store: MenuBarItemStore,
        permissions: PermissionManager,
        initialHideSelectedIcons: Bool,
        onComplete: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.permissions = permissions
        self.onComplete = onComplete
        _step = State(initialValue: Step.previewSelection)
        _hideSelectedIcons = State(initialValue: initialHideSelectedIcons)
    }

    private enum Step: Int, CaseIterable {
        case welcome, permissions, customize, ready

        var title: String {
            switch self {
            case .welcome: "开始"
            case .permissions: "权限"
            case .customize: "规则"
            case .ready: "完成"
            }
        }

        static var previewSelection: Step {
            let prefix = "--ui-preview-onboarding-step="
            guard let value = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix(prefix) })?
                .dropFirst(prefix.count) else { return .welcome }

            switch value {
            case "permissions": return .permissions
            case "customize": return .customize
            case "ready": return .ready
            default: return .welcome
            }
        }
    }

    var body: some View {
        ZStack {
            NotchShelfTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                progressHeader
                Divider().overlay(NotchShelfTheme.stroke)

                ZStack {
                    stepContent
                        .id(step)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Divider().overlay(NotchShelfTheme.stroke)
                navigation
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(.dark)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.88),
            value: step
        )
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: permissions.accessibilityGranted) { _, granted in
            if granted && store.items.isEmpty { store.refresh() }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .customize { store.refresh() }
        }
        .alert(
            "登录启动设置失败",
            isPresented: Binding(
                get: { launchAtLogin.errorMessage != nil },
                set: { _ in }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(launchAtLogin.errorMessage ?? "无法更新登录项。")
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchShelfTheme.accentStrong)
                .frame(width: 28, height: 28)
                .background(NotchShelfTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("NotchShelf")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchShelfTheme.primaryText)

            Spacer()

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.rawValue <= step.rawValue ? NotchShelfTheme.accent : NotchShelfTheme.raisedSurface)
                        .frame(width: item == step ? 28 : 9, height: 4)
                }
            }

            Text("\(step.rawValue + 1)/\(Step.allCases.count) · \(step.title)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(NotchShelfTheme.secondaryText)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.leading, 78)
        .padding(.trailing, 24)
        .padding(.top, 8)
        .frame(height: 58)
        .background(NotchShelfTheme.chrome)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .permissions: permissionsStep
        case .customize: customizeStep
        case .ready: readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NotchShelfTheme.deepSurface)
                    .frame(width: 86, height: 86)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(NotchShelfTheme.accent.opacity(0.42), lineWidth: 1)
                    }
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 37, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.accentStrong)
            }

            VStack(spacing: 8) {
                Text("把刘海挡住的图标，收进一层托盘")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.primaryText)
                Text("NotchShelf 自动计算菜单栏安全宽度，也允许你为每个项目指定自动、常显或收纳。")
                    .font(.system(size: 13))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            HStack(spacing: 22) {
                feature("display.2", "双屏支持", "主屏与扩展屏")
                feature("wand.and.stars", "自动避让", "按刘海宽度计算")
                feature("hand.tap.fill", "原生点击", "直接打开原菜单")
            }
        }
        .padding(34)
    }

    private var permissionsStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("只需要两项系统权限")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.primaryText)
                Text("所有扫描、图标截取和点击操作都在本机完成。")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }

            VStack(spacing: 10) {
                permissionCard(
                    icon: "accessibility",
                    title: "辅助功能",
                    detail: "读取菜单栏控件并触发它们原本的点击动作。",
                    granted: permissions.accessibilityGranted,
                    action: permissions.requestAccessibility,
                    openSettings: permissions.openAccessibilitySettings
                )
                permissionCard(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: "屏幕录制",
                    detail: "只截取菜单栏图标的小区域，用于托盘显示。",
                    granted: permissions.screenRecordingGranted,
                    action: permissions.openScreenRecordingSettings,
                    openSettings: permissions.openScreenRecordingSettings
                )
            }
            .frame(maxWidth: 590)

            Label("不联网、无账号、无遥测", systemImage: "lock.shield.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchShelfTheme.success)
        }
        .padding(30)
    }

    private var customizeStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("使用推荐规则开始")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.primaryText)
                Text("首次启动采用自动避让；之后可在项目页逐项调整。")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }

            NotchShelfSurface(padding: 0) {
                VStack(spacing: 0) {
                    onboardingToggle(
                        symbol: "power",
                        title: "登录时启动",
                        detail: "开机后自动保持菜单栏整洁",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                    Divider().overlay(NotchShelfTheme.stroke).padding(.leading, 54)
                    onboardingToggle(
                        symbol: "rectangle.compress.vertical",
                        title: "隐藏已收纳的原图标",
                        detail: "关闭后只保留规则，不改变菜单栏位置",
                        isOn: $hideSelectedIcons
                    )
                }
            }
            .frame(maxWidth: 590)

            HStack(spacing: 8) {
                ruleHint(.automatic, detail: "空间不足时自动收纳")
                ruleHint(.alwaysVisible, detail: "始终留在菜单栏")
                ruleHint(.alwaysHidden, detail: "始终放入托盘")
            }
            .frame(maxWidth: 590)

            HStack(spacing: 8) {
                NotchShelfStatusPill(title: "已发现 \(store.items.count) 项", color: NotchShelfTheme.accent, systemImage: "menubar.rectangle")
                NotchShelfStatusPill(title: "当前收纳 \(store.selectedItems.count) 项", color: NotchShelfTheme.success, systemImage: "tray.full.fill")
                Button("重新扫描") { store.refresh() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .padding(28)
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NotchShelfTheme.success.opacity(0.10))
                    .frame(width: 82, height: 82)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(NotchShelfTheme.success.opacity(0.30), lineWidth: 1)
                    }
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(NotchShelfTheme.success)
                    .symbolEffect(.bounce, value: step)
            }

            VStack(spacing: 7) {
                Text("NotchShelf 已准备好")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.primaryText)
                Text("左键点击菜单栏层叠图标展开托盘，右键可随时打开设置。")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }

            HStack(spacing: 10) {
                summary("辅助功能", value: permissions.accessibilityGranted ? "已授权" : "稍后设置", positive: permissions.accessibilityGranted)
                summary("屏幕录制", value: permissions.screenRecordingGranted ? "已授权" : "稍后设置", positive: permissions.screenRecordingGranted)
                summary("显示器", value: "\(store.displays.count) 块", positive: true)
            }
        }
        .padding(34)
    }

    private var navigation: some View {
        HStack {
            if step != .welcome {
                Button("返回") { move(to: step.rawValue - 1) }
                    .buttonStyle(.borderless)
            }
            Spacer()
            if step == .permissions && (!permissions.accessibilityGranted || !permissions.screenRecordingGranted) {
                Text("权限可以稍后补充")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }
            Button(step == .ready ? "开始使用" : "继续") {
                if step == .ready {
                    onComplete(hideSelectedIcons)
                } else {
                    move(to: step.rawValue + 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(NotchShelfTheme.accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .frame(height: 62)
        .background(NotchShelfTheme.chrome)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchShelfTheme.accentStrong)
                .frame(width: 30, height: 30)
                .background(NotchShelfTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        NotchShelfSurface {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(granted ? NotchShelfTheme.success : NotchShelfTheme.warning)
                    .frame(width: 36, height: 36)
                    .background((granted ? NotchShelfTheme.success : NotchShelfTheme.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NotchShelfTheme.primaryText)
                        if granted {
                            NotchShelfStatusPill(title: "已授权", color: NotchShelfTheme.success, systemImage: "checkmark.circle.fill")
                        }
                    }
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchShelfTheme.secondaryText)
                }
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(NotchShelfTheme.success)
                } else {
                    Button("授权", action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(NotchShelfTheme.accent)
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开系统设置")
                }
            }
        }
    }

    private func onboardingToggle(
        symbol: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? NotchShelfTheme.accentStrong : NotchShelfTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(NotchShelfTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchShelfTheme.primaryText)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(NotchShelfTheme.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    private func ruleHint(_ rule: MenuItemRule, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(rule.localizedTitle, systemImage: rule.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(rule.tint)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(NotchShelfTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchShelfTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rule.tint.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func summary(_ title: String, value: String, positive: Bool) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(positive ? NotchShelfTheme.success : NotchShelfTheme.warning)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(NotchShelfTheme.secondaryText)
        }
        .frame(width: 132, height: 52)
        .background(NotchShelfTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NotchShelfTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func move(to rawValue: Int) {
        guard let next = Step(rawValue: rawValue) else { return }
        step = next
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }
}
