import Foundation
import WidgetKit

@objc(TVNCWidgetTimelineReloader)
public final class WidgetTimelineReloader: NSObject {
    @objc public static func reloadAutostartTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: "TrollVNCAutostartWidget")
    }
}
