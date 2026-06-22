//
//  DoITWidgetBundle.swift
//  DoITWidget
//
//  Created by fahad on 23/06/2026.
//

import WidgetKit
import SwiftUI

@main
struct DoITWidgetBundle: WidgetBundle {
    var body: some Widget {
        DoITWidget()
        DoITWidgetControl()
        DoITWidgetLiveActivity()
    }
}
