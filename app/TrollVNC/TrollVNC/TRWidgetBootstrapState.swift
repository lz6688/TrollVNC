import Foundation
import WidgetKit

@objcMembers
public final class TRWidgetBootstrapState: NSObject {
    private static let appGroupSuiteName = "group.com.82flex.trollvnc"
    private static let fallbackSuiteName = "com.82flex.trollvnc"

    private static let widgetInstalledMarkerKey = "TVNCWidgetInstalledMarker"
    private static let widgetBootstrapPendingKey = "TVNCWidgetBootstrapPending"
    private static let widgetLastSeenAtKey = "TVNCWidgetLastSeenAt"
    private static let widgetBootstrapAttemptedAtKey = "TVNCWidgetBootstrapAttemptedAt"

    // Keep this prefix aligned with the eventual WidgetKit target's kind string.
    private static let widgetKindPrefix = "com.82flex.trollvnc.widget"

    private static func sharedDefaults() -> UserDefaults {
        if let defaults = UserDefaults(suiteName: appGroupSuiteName) {
            return defaults
        }
        if let defaults = UserDefaults(suiteName: fallbackSuiteName) {
            return defaults
        }
        return .standard
    }

    public static func markWidgetInstalled() {
        let defaults = sharedDefaults()
        let wasInstalled = defaults.bool(forKey: widgetInstalledMarkerKey)
        defaults.set(true, forKey: widgetInstalledMarkerKey)
        if !wasInstalled {
            defaults.set(true, forKey: widgetBootstrapPendingKey)
        }
        defaults.set(Date(), forKey: widgetLastSeenAtKey)
        defaults.synchronize()
    }

    public static func hasPendingWidgetBootstrap() -> Bool {
        sharedDefaults().bool(forKey: widgetBootstrapPendingKey)
    }

    public static func clearPendingWidgetBootstrap() {
        let defaults = sharedDefaults()
        defaults.set(false, forKey: widgetBootstrapPendingKey)
        defaults.synchronize()
    }

    public static func recordBootstrapAttempt() {
        let defaults = sharedDefaults()
        defaults.set(Date(), forKey: widgetBootstrapAttemptedAtKey)
        defaults.synchronize()
    }

    @objc(refreshWidgetPresence:)
    public static func refreshWidgetPresence(_ completion: @escaping (Bool) -> Void) {
        let defaults = sharedDefaults()
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case let .success(widgets):
                    let hasWidget = widgets.contains { $0.kind.hasPrefix(widgetKindPrefix) }
                    defaults.set(hasWidget, forKey: widgetInstalledMarkerKey)
                    if hasWidget {
                        defaults.set(Date(), forKey: widgetLastSeenAtKey)
                    } else {
                        defaults.set(false, forKey: widgetBootstrapPendingKey)
                    }
                    defaults.synchronize()
                    completion(hasWidget)
                case .failure:
                    completion(defaults.bool(forKey: widgetInstalledMarkerKey))
                }
            }
            return
        }

        completion(defaults.bool(forKey: widgetInstalledMarkerKey))
    }
}
