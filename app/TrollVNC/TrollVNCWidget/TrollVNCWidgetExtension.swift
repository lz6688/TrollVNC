import SwiftUI
import WidgetKit

private let tvncWidgetKind = "com.82flex.trollvnc.widget.status"
private let tvncWidgetAppGroup = "group.com.82flex.trollvnc"
private let tvncWidgetFallbackSuite = "com.82flex.trollvnc"

private let tvncWidgetInstalledMarkerKey = "TVNCWidgetInstalledMarker"
private let tvncWidgetBootstrapPendingKey = "TVNCWidgetBootstrapPending"
private let tvncWidgetLastSeenAtKey = "TVNCWidgetLastSeenAt"

private enum TVNCWidgetSharedState {
    static func defaults() -> UserDefaults {
        if let defaults = UserDefaults(suiteName: tvncWidgetAppGroup) {
            return defaults
        }
        if let defaults = UserDefaults(suiteName: tvncWidgetFallbackSuite) {
            return defaults
        }
        return .standard
    }

    static func markInstalledIfNeeded() {
        let defaults = defaults()
        let wasInstalled = defaults.bool(forKey: tvncWidgetInstalledMarkerKey)
        defaults.set(true, forKey: tvncWidgetInstalledMarkerKey)
        if !wasInstalled {
            defaults.set(true, forKey: tvncWidgetBootstrapPendingKey)
        }
        defaults.set(Date(), forKey: tvncWidgetLastSeenAtKey)
        defaults.synchronize()
    }
}

private struct TVNCWidgetEntry: TimelineEntry {
    let date: Date
}

private struct TVNCWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TVNCWidgetEntry {
        TVNCWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TVNCWidgetEntry) -> Void) {
        TVNCWidgetSharedState.markInstalledIfNeeded()
        completion(TVNCWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TVNCWidgetEntry>) -> Void) {
        TVNCWidgetSharedState.markInstalledIfNeeded()

        let currentDate = Date()
        let entry = TVNCWidgetEntry(date: currentDate)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)
            ?? currentDate.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

private struct TVNCWidgetEntryView: View {
    let entry: TVNCWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TrollVNC")
                .font(.headline)

            Text("Widget Ready")
                .font(.subheadline)
                .foregroundColor(.primary)

            Text("Background refresh will try to launch TrollVNC.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("Tap to open the app")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "trollvnc://widget/open"))
    }
}

private struct TVNCStatusWidget: Widget {
    let kind: String = tvncWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TVNCWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                TVNCWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TVNCWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(.systemBackground))
            }
        }
        .configurationDisplayName("TrollVNC")
        .description("After the widget is added, background refresh can try to launch TrollVNC.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TrollVNCWidgetBundle: WidgetBundle {
    var body: some Widget {
        TVNCStatusWidget()
    }
}
