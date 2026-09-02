//
//  PDFtoExcelApp.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/14/25.
//

import AppKit
import SwiftUI

/// Receives files opened from Finder, the Dock, or `open -a`.
///
/// SwiftUI's `onOpenURL` does not see these on macOS: AppKit delivers documents
/// to the application delegate, so the app advertising itself as a PDF editor in
/// Info.plist only means anything if something implements this.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var filesToOpen: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        filesToOpen.append(contentsOf: urls.filter { $0.pathExtension.lowercased() == "pdf" })
    }
}

@main
struct PDFtoExcelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(appDelegate)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
