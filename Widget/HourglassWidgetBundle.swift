import WidgetKit
import SwiftUI

@main
struct HourglassWidgetBundle: WidgetBundle {
    var body: some Widget {
        HourglassStatusWidget()
        QuickStartWidget()
        if #available(iOSApplicationExtension 16.1, *) {
            HourglassLiveActivity()
        }
    }
}

extension View {
    /// `containerBackground` is required on iOS 17+, unavailable before.
    @ViewBuilder
    func widgetBackground<B: View>(_ background: B) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { background }
        } else {
            self.background(background)
        }
    }
}

enum WidgetStyle {
    static let background = LinearGradient(colors: [Color(white: 0.12), .black], startPoint: .top, endPoint: .bottom)
}
