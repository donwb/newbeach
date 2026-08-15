import WidgetKit
import SwiftUI
import BeachStatus

@main
struct BeachRampWidgetsBundle: WidgetBundle {
    init() {
        BeachFont.registerFonts()
    }

    var body: some Widget {
        BoardWidget()
    }
}

/// Placeholder while the target skeleton lands — the real board widgets
/// (small/medium/large + accessories) replace this.
struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BoardWidget", provider: PlaceholderProvider()) { entry in
            PlaceholderView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Beach Ramps")
        .description("Ramp status at a glance.")
    }
}

struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct PlaceholderView: View {
    let entry: PlaceholderProvider.Entry

    var body: some View {
        Text("Beach Ramps")
            .font(.archivo(15, weight: .extraBold))
    }
}
