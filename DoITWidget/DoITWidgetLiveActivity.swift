//
//  DoITWidgetLiveActivity.swift
//  DoITWidget
//
//  Created by fahad on 23/06/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DoITWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DoITWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoITWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension DoITWidgetAttributes {
    fileprivate static var preview: DoITWidgetAttributes {
        DoITWidgetAttributes(name: "World")
    }
}

extension DoITWidgetAttributes.ContentState {
    fileprivate static var smiley: DoITWidgetAttributes.ContentState {
        DoITWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DoITWidgetAttributes.ContentState {
         DoITWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DoITWidgetAttributes.preview) {
   DoITWidgetLiveActivity()
} contentStates: {
    DoITWidgetAttributes.ContentState.smiley
    DoITWidgetAttributes.ContentState.starEyes
}
