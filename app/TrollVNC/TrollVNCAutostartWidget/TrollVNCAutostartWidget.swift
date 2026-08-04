import SwiftUI
import WidgetKit

struct TrollVNCAutostartEntry: TimelineEntry {
    let date: Date
    let iconColor: Color
}

struct TrollVNCAutostartProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrollVNCAutostartEntry {
        makeEntry(colorCode: 0x003566E7)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrollVNCAutostartEntry) -> Void) {
        completion(makeEntry(colorCode: 0x003566E7))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrollVNCAutostartEntry>) -> Void) {
        let colorCode = TrollVNCWidgetHelper.launchTrollVNCIfNecessary()
        let entry = makeEntry(colorCode: colorCode)
        let nextRefresh = Date().addingTimeInterval(TrollVNCWidgetHelper.widgetRefreshInterval())
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(colorCode: UInt32) -> TrollVNCAutostartEntry {
        let color = Color(
            .sRGB,
            red: Double((colorCode >> 16) & 0xff) / 255.0,
            green: Double((colorCode >> 8) & 0xff) / 255.0,
            blue: Double(colorCode & 0xff) / 255.0,
            opacity: 1.0
        )
        return TrollVNCAutostartEntry(date: Date(), iconColor: color)
    }
}

struct TrollVNCAutostartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrollVNCAutostartEntry

    var body: some View {
        if #available(iOSApplicationExtension 16.0, *), family == .accessoryCircular {
            TrollVNCLockScreenView(color: entry.iconColor)
        } else {
            TrollVNCHomeScreenView(color: entry.iconColor)
        }
    }
}

struct TrollVNCHomeScreenView: View {
    let color: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.1),
                    Color(red: 0.02, green: 0.03, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            TrollVNCIcon(color: color)
                .frame(width: 78, height: 78)
        }
        .tvncWidgetBackground {
            Color(red: 0.04, green: 0.05, blue: 0.06)
        }
    }
}

struct TrollVNCLockScreenView: View {
    let color: Color

    var body: some View {
        TrollVNCIcon(color: color)
            .frame(width: 46, height: 46)
            .tvncWidgetBackground {
                Color.clear
            }
    }
}

struct TrollVNCIcon: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(4, size * 0.12)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.48)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: max(1, size * 0.025))
                Path { path in
                    path.move(to: CGPoint(x: size * 0.26, y: size * 0.3))
                    path.addLine(to: CGPoint(x: size * 0.5, y: size * 0.68))
                    path.addLine(to: CGPoint(x: size * 0.74, y: size * 0.3))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

struct TrollVNCAutostartWidget: Widget {
    let kind = "TrollVNCAutostartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrollVNCAutostartProvider()) { entry in
            TrollVNCAutostartWidgetView(entry: entry)
        }
        .configurationDisplayName("TrollVNC")
        .description("Add to the Home Screen or Lock Screen to keep TrollVNC ready after reboot.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall]
        if #available(iOSApplicationExtension 16.0, *) {
            families.append(.accessoryCircular)
        }
        return families
    }
}

private extension View {
    @ViewBuilder
    func tvncWidgetBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget, content: background)
        } else {
            self.background(background())
        }
    }
}

@main
struct TrollVNCAutostartWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrollVNCAutostartWidget()
    }
}
