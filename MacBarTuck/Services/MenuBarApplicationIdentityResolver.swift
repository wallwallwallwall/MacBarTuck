import AppKit

final class MenuBarApplicationIdentityResolver {
    struct ApplicationRecord {
        let displayName: String?
        let bundleIdentifier: String?
        let bundleURL: URL?
        let icon: NSImage?
    }

    struct Identity {
        let displayName: String
        let bundleIdentifier: String?
        let bundleURL: URL?
        let icon: NSImage?
    }

    typealias RunningApplicationLookup = (String) -> ApplicationRecord?
    typealias InstalledApplicationLookup = (String) -> URL?
    typealias ApplicationMetadataLookup = (URL) -> ApplicationRecord?

    private let runningApplication: RunningApplicationLookup
    private let installedApplicationURL: InstalledApplicationLookup
    private let applicationMetadata: ApplicationMetadataLookup
    private var cache: [String: Identity] = [:]
    private var missingBundleIdentifiers = Set<String>()

    init(
        runningApplication: @escaping RunningApplicationLookup = { bundleIdentifier in
            guard let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first else { return nil }
            return ApplicationRecord(
                displayName: app.localizedName,
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL,
                icon: app.icon
            )
        },
        installedApplicationURL: @escaping InstalledApplicationLookup = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        },
        applicationMetadata: @escaping ApplicationMetadataLookup = { url in
            let bundle = Bundle(url: url)
            let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let hasDeclaredIcon = bundle?.infoDictionary.map(
                MenuBarApplicationIdentityResolver.declaresApplicationIcon
            ) ?? false
            let icon: NSImage? = if hasDeclaredIcon {
                (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage)
                    ?? NSWorkspace.shared.icon(forFile: url.path)
            } else {
                nil
            }
            icon?.isTemplate = false
            return ApplicationRecord(
                displayName: displayName,
                bundleIdentifier: bundle?.bundleIdentifier,
                bundleURL: url,
                icon: icon
            )
        }
    ) {
        self.runningApplication = runningApplication
        self.installedApplicationURL = installedApplicationURL
        self.applicationMetadata = applicationMetadata
    }

    func resolve(bundleIdentifier: String) -> Identity? {
        if let cached = cache[bundleIdentifier] { return cached }
        if missingBundleIdentifiers.contains(bundleIdentifier) { return nil }

        if MenuBarSystemItemClassifier.isInputSourceAgent(bundleIdentifier) {
            let identity = Identity(
                displayName: "Input Source",
                bundleIdentifier: bundleIdentifier,
                bundleURL: nil,
                icon: nil
            )
            cache[bundleIdentifier] = identity
            return identity
        }

        let running = runningApplication(bundleIdentifier)
        let locatedURL = running?.bundleURL ?? installedApplicationURL(bundleIdentifier)
        if let locatedURL {
            let outerURL = Self.outermostApplicationURL(for: locatedURL)
            if outerURL != locatedURL, let outer = applicationMetadata(outerURL) {
                let identity = makeIdentity(from: outer, fallbackIdentifier: bundleIdentifier)
                cache[bundleIdentifier] = identity
                return identity
            }
            if let metadata = applicationMetadata(outerURL) {
                let combined = ApplicationRecord(
                    displayName: running?.displayName ?? metadata.displayName,
                    bundleIdentifier: running?.bundleIdentifier ?? metadata.bundleIdentifier,
                    bundleURL: outerURL,
                    icon: metadata.icon ?? running?.icon
                )
                let identity = makeIdentity(from: combined, fallbackIdentifier: bundleIdentifier)
                cache[bundleIdentifier] = identity
                return identity
            }
        }

        if let running {
            let identity = makeIdentity(from: running, fallbackIdentifier: bundleIdentifier)
            cache[bundleIdentifier] = identity
            return identity
        }

        missingBundleIdentifiers.insert(bundleIdentifier)
        return nil
    }

    func invalidate() {
        cache.removeAll(keepingCapacity: true)
        missingBundleIdentifiers.removeAll(keepingCapacity: true)
    }

    static func outermostApplicationURL(for url: URL) -> URL {
        var current = url.standardizedFileURL
        var outermost: URL?
        while current.path != "/" {
            if current.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                outermost = current
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return outermost ?? url.standardizedFileURL
    }

    static func declaresApplicationIcon(_ infoDictionary: [String: Any]) -> Bool {
        for key in ["CFBundleIconFile", "CFBundleIconName"] {
            if let value = infoDictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        if let files = infoDictionary["CFBundleIconFiles"] as? [Any], !files.isEmpty {
            return true
        }
        if let icons = infoDictionary["CFBundleIcons"] as? [String: Any], !icons.isEmpty {
            return true
        }
        return false
    }

    private func makeIdentity(from record: ApplicationRecord,
                              fallbackIdentifier: String) -> Identity {
        Identity(
            displayName: record.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? fallbackIdentifier,
            bundleIdentifier: record.bundleIdentifier ?? fallbackIdentifier,
            bundleURL: record.bundleURL,
            icon: record.icon
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
