import Darwin
import Foundation
import ObjectiveC

struct MenuBarAssessmentConfiguration: Equatable {
    let allowedSystemItems: [Int]
    let allowedBundleIdentifiers: [String]

    init(allowedSystemItems: [Int], allowedBundleIdentifiers: [String]) {
        self.allowedSystemItems = Array(Set(allowedSystemItems)).sorted()
        self.allowedBundleIdentifiers = Array(Set(allowedBundleIdentifiers)).sorted()
    }
}

enum MenuBarAssessmentApplyResult: Equatable {
    case applied(changed: Bool)
    case unavailable
    case failed(String)
    case timedOut
    case cancelled
}

@MainActor
protocol MenuBarAssessmentRuntime: AnyObject {
    var isAvailable: Bool { get }
    func makeConfiguration(_ configuration: MenuBarAssessmentConfiguration) -> AnyObject?
    func makeAssertion() -> AnyObject?
    func activate(
        _ assertion: AnyObject,
        configuration: AnyObject,
        completion: @escaping (NSError?) -> Void
    )
    func invalidate(_ assertion: AnyObject)
}

@MainActor
protocol MenuBarAssessmentModeManaging: AnyObject {
    var isAvailable: Bool { get }
    var activeConfiguration: MenuBarAssessmentConfiguration? { get }
    func apply(
        _ configuration: MenuBarAssessmentConfiguration,
        completion: @escaping (MenuBarAssessmentApplyResult) -> Void
    )
    func invalidate()
}

@MainActor
final class MenuBarAssessmentModeController: MenuBarAssessmentModeManaging {
    typealias TimeoutScheduler = (TimeInterval, @escaping () -> Void) -> Void

    private struct ActiveAssertion {
        let handle: AnyObject
        let configuration: MenuBarAssessmentConfiguration
    }

    private struct PendingAssertion {
        let handle: AnyObject
        let configurationObject: AnyObject
        let configuration: MenuBarAssessmentConfiguration
        let generation: Int
        let completion: (MenuBarAssessmentApplyResult) -> Void
    }

    private let runtime: any MenuBarAssessmentRuntime
    private let scheduleTimeout: TimeoutScheduler
    private let activationTimeout: TimeInterval
    private var active: ActiveAssertion?
    private var pending: PendingAssertion?
    private var generation = 0

    init(
        runtime: (any MenuBarAssessmentRuntime)? = nil,
        activationTimeout: TimeInterval = 3,
        scheduleTimeout: @escaping TimeoutScheduler = { delay, work in
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: DispatchWorkItem(block: work)
            )
        }
    ) {
        self.runtime = runtime ?? DynamicMenuBarAssessmentRuntime()
        self.activationTimeout = activationTimeout
        self.scheduleTimeout = scheduleTimeout
    }

    var isAvailable: Bool { runtime.isAvailable }
    var activeConfiguration: MenuBarAssessmentConfiguration? { active?.configuration }

    func apply(
        _ configuration: MenuBarAssessmentConfiguration,
        completion: @escaping (MenuBarAssessmentApplyResult) -> Void
    ) {
        if pending == nil, active?.configuration == configuration {
            completion(.applied(changed: false))
            return
        }
        guard pending == nil else {
            completion(.failed("A visibility update is already in progress."))
            return
        }
        guard runtime.isAvailable,
              let configurationObject = runtime.makeConfiguration(configuration),
              let handle = runtime.makeAssertion() else {
            completion(.unavailable)
            return
        }

        generation += 1
        let token = generation
        pending = PendingAssertion(
            handle: handle,
            configurationObject: configurationObject,
            configuration: configuration,
            generation: token,
            completion: completion
        )
        runtime.activate(handle, configuration: configurationObject) { [weak self] error in
            Task { @MainActor in
                self?.finishActivation(generation: token, error: error)
            }
        }
        scheduleTimeout(activationTimeout) { [weak self] in
            Task { @MainActor in
                self?.timeOutActivation(generation: token)
            }
        }
    }

    func invalidate() {
        generation += 1
        if let pending {
            runtime.invalidate(pending.handle)
            pending.completion(.cancelled)
            self.pending = nil
        }
        if let active {
            runtime.invalidate(active.handle)
            self.active = nil
        }
    }

    private func finishActivation(generation token: Int, error: NSError?) {
        guard let pending, pending.generation == token, generation == token else { return }
        self.pending = nil
        if let error {
            runtime.invalidate(pending.handle)
            pending.completion(.failed(error.localizedDescription))
            return
        }

        let previous = active
        active = ActiveAssertion(
            handle: pending.handle,
            configuration: pending.configuration
        )
        if let previous { runtime.invalidate(previous.handle) }
        pending.completion(.applied(changed: true))
    }

    private func timeOutActivation(generation token: Int) {
        guard let pending, pending.generation == token, generation == token else { return }
        self.pending = nil
        runtime.invalidate(pending.handle)
        pending.completion(.timedOut)
    }
}

@MainActor
private final class DynamicMenuBarAssessmentRuntime: MenuBarAssessmentRuntime {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString(
        "initWithAllowedSystemItems:allowedBundleIdentifiers:"
    )
    private static let activateSelector = NSSelectorFromString(
        "activateWithConfiguration:completionHandler:"
    )
    private static let invalidateSelector = NSSelectorFromString("invalidate")
    private static let initSelector = NSSelectorFromString("init")
    private static let allocSelector = NSSelectorFromString("alloc")

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let configurationClass: AnyClass?
    private let assertionClass: AnyClass?

    init() {
        frameworkHandle = dlopen(Self.frameworkPath, RTLD_LAZY | RTLD_LOCAL)
        if frameworkHandle == nil {
            configurationClass = nil
            assertionClass = nil
        } else {
            configurationClass = NSClassFromString("MBAssessmentModeConfiguration")
            assertionClass = NSClassFromString("MBAssessmentModeAssertion")
        }
    }

    var isAvailable: Bool {
        guard frameworkHandle != nil,
              let configurationClass,
              let assertionClass else { return false }
        return class_getInstanceMethod(configurationClass, Self.configureSelector) != nil &&
            class_getInstanceMethod(assertionClass, Self.activateSelector) != nil &&
            class_getInstanceMethod(assertionClass, Self.invalidateSelector) != nil
    }

    func makeConfiguration(_ configuration: MenuBarAssessmentConfiguration) -> AnyObject? {
        guard isAvailable,
              let configurationClass,
              let allocated = allocate(configurationClass),
              let method = class_getInstanceMethod(configurationClass, Self.configureSelector) else {
            return nil
        }
        typealias Configure = @convention(c) (
            AnyObject, Selector, NSArray, NSArray
        ) -> Unmanaged<NSObject>?
        let configure = unsafeBitCast(method_getImplementation(method), to: Configure.self)
        return configure(
            allocated,
            Self.configureSelector,
            configuration.allowedSystemItems.map(NSNumber.init(value:)) as NSArray,
            configuration.allowedBundleIdentifiers as NSArray
        )?.takeRetainedValue()
    }

    func makeAssertion() -> AnyObject? {
        guard isAvailable,
              let assertionClass,
              let allocated = allocate(assertionClass),
              let method = class_getInstanceMethod(assertionClass, Self.initSelector) else {
            return nil
        }
        typealias Initialize = @convention(c) (
            AnyObject, Selector
        ) -> Unmanaged<NSObject>?
        let initialize = unsafeBitCast(method_getImplementation(method), to: Initialize.self)
        return initialize(allocated, Self.initSelector)?.takeRetainedValue()
    }

    func activate(
        _ assertion: AnyObject,
        configuration: AnyObject,
        completion: @escaping (NSError?) -> Void
    ) {
        guard let assertionClass,
              let method = class_getInstanceMethod(assertionClass, Self.activateSelector) else {
            completion(NSError(
                domain: "MacBarTuck.AssessmentMode",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Assessment mode is unavailable."]
            ))
            return
        }
        typealias Callback = @convention(block) (NSError?) -> Void
        typealias Activate = @convention(c) (
            AnyObject, Selector, AnyObject, Callback
        ) -> Void
        let activate = unsafeBitCast(method_getImplementation(method), to: Activate.self)
        let callback: Callback = { error in completion(error) }
        activate(assertion, Self.activateSelector, configuration, callback)
    }

    func invalidate(_ assertion: AnyObject) {
        guard let assertionClass,
              let method = class_getInstanceMethod(assertionClass, Self.invalidateSelector) else {
            return
        }
        typealias Invalidate = @convention(c) (AnyObject, Selector) -> Void
        let invalidate = unsafeBitCast(method_getImplementation(method), to: Invalidate.self)
        invalidate(assertion, Self.invalidateSelector)
    }

    private func allocate(_ type: AnyClass) -> NSObject? {
        guard let method = class_getClassMethod(type, Self.allocSelector) else { return nil }
        typealias Allocate = @convention(c) (
            AnyClass, Selector
        ) -> Unmanaged<NSObject>
        let allocate = unsafeBitCast(method_getImplementation(method), to: Allocate.self)
        return allocate(type, Self.allocSelector).takeUnretainedValue()
    }
}
