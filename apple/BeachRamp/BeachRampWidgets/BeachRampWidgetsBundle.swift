import WidgetKit
import SwiftUI
import BeachStatus

@main
struct BeachRampWidgetsBundle: WidgetBundle {
    init() {
        BeachFont.registerFonts()
    }

    // Same widget kinds on every iOS; on 26 the definitions carry the push
    // handler so the server can reload them on a ramp flip. The bundle
    // builder allows `if #available` but no `else`, so the choice is made
    // in a plain property and handed to the builder's own public
    // limited-availability wrapper.
    var body: some Widget {
        WidgetBundleBuilder.buildOptional(Self.chosen)
    }

    private static var chosen: (any Widget & _LimitedAvailabilityWidgetMarker)? {
        if #available(iOS 26.0, *) {
            return WidgetBundleBuilder.buildLimitedAvailability(PushWidgets().body)
        }
        return WidgetBundleBuilder.buildLimitedAvailability(LegacyWidgets().body)
    }
}

/// The widgets as shipped since 1.0: timed refresh only.
struct LegacyWidgets: WidgetBundle {
    var body: some Widget {
        BoardWidget()
        AccessoryWidget()
    }
}

/// The same widgets with the iOS 26 push handler attached.
@available(iOS 26.0, *)
struct PushWidgets: WidgetBundle {
    var body: some Widget {
        BoardWidgetPush()
        AccessoryWidgetPush()
    }
}

/// The Home Screen family: small / medium / large on the sun-following
/// ground, configured per instance (city, all/favorites/one ramp).
struct BoardWidget: Widget {
    static var configuration: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "BoardWidget",
            intent: RampWidgetIntent.self,
            provider: BoardTimelineProvider()
        ) { entry in
            BoardWidgetView(entry: entry)
        }
        .configurationDisplayName("Ramp Board")
        .description("Ramp status, the verdict, and the tide at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }

    var body: some WidgetConfiguration { Self.configuration }
}

/// BoardWidget with the iOS 26 push handler — the same kind, so widgets
/// already on a Home Screen keep working.
@available(iOS 26.0, *)
struct BoardWidgetPush: Widget {
    var body: some WidgetConfiguration {
        BoardWidget.configuration.pushHandler(BeachWidgetPushHandler.self)
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
    static var configuration: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "AccessoryWidget",
            intent: RampWidgetIntent.self,
            provider: BoardTimelineProvider()
        ) { entry in
            AccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Ramps Open Now")
        .description("Ramps open right now.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }

    var body: some WidgetConfiguration { Self.configuration }
}

@available(iOS 26.0, *)
struct AccessoryWidgetPush: Widget {
    var body: some WidgetConfiguration {
        AccessoryWidget.configuration.pushHandler(BeachWidgetPushHandler.self)
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
