/*
 This file is part of TrollVNC
 Copyright (c) 2025 82Flex <82flex@gmail.com> and contributors

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License version 2
 as published by the Free Software Foundation.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see <https://www.gnu.org/licenses/>.
*/

import SwiftUI
import WidgetKit

private struct TrollVNCWidgetEntry: TimelineEntry {
    let date: Date
    let serviceRunning: Bool
}

private struct TrollVNCWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrollVNCWidgetEntry {
        return TrollVNCWidgetEntry(date: Date(), serviceRunning: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrollVNCWidgetEntry) -> Void) {
        TVNCServiceLauncher.log("widget getSnapshot begin isPreview=\(context.isPreview) logPath=\(TVNCServiceLauncher.debugLogPath())")
        let running = context.isPreview ? TVNCServiceLauncher.isServiceRunning() : TVNCServiceLauncher.ensureServiceRunning()
        TVNCServiceLauncher.log("widget getSnapshot complete running=\(running)")
        completion(TrollVNCWidgetEntry(date: Date(), serviceRunning: running))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrollVNCWidgetEntry>) -> Void) {
        TVNCServiceLauncher.log("widget getTimeline begin isPreview=\(context.isPreview) logPath=\(TVNCServiceLauncher.debugLogPath())")
        let running = TVNCServiceLauncher.ensureServiceRunning()
        let entry = TrollVNCWidgetEntry(date: Date(), serviceRunning: running)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        TVNCServiceLauncher.log("widget getTimeline complete running=\(running) nextRefresh=\(nextRefresh)")
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct TrollVNCWidgetEntryView: View {
    let entry: TrollVNCWidgetEntry

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .containerBackground(Color(.systemBackground), for: .widget)
        } else {
            content
                .background(Color(.systemBackground))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.serviceRunning ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(entry.serviceRunning ? "Running" : "Starting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Text("TrollVNC")
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
    }
}

@main
private struct TrollVNCWidget: Widget {
    private let kind = "com.82flex.TrollVNCApp.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrollVNCWidgetProvider()) { entry in
            TrollVNCWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("TrollVNC")
        .description("TrollVNC service status")
        .supportedFamilies([.systemSmall])
    }
}
