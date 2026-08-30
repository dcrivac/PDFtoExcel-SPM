//
//  PDFtoExcelApp.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/14/25.
//

import SwiftUI

@main
struct PDFtoExcelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
