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
        AccessoryWidget()
    }
}

/// The Home Screen family: small / medium / large on the sun-following
/// ground, configured per instance (city, all/favorites/one ramp).
struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "BoardWidget",
            intent: RampWidgetIntent.self,
            provider: BoardTimelineProvider()
        ) { entry in
            BoardWidgetView(entry: entry)
        }
        .configurationDisplayName("Beach Ramps")
        .description("Ramp status, the verdict, and the tide at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BoardWidgetView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

/// Lock Screen accessories: monochrome ring / bar / inline.
struct AccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "AccessoryWidget",
            intent: RampWidgetIntent.self,
            provider: BoardTimelineProvider()
        ) { entry in
            AccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Beach Ramps")
        .description("Ramps open right now.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AccessoryWidgetView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            AccessoryCircularView(entry: entry)
        }
    }
}
