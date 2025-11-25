import Foundation
import ApplicationServices
import CoreGraphics

/// An Alfred item that displays an error message to the user
struct ErrorAlfredItem: AlfredItem {
    let title: String
    let subtitle: String

    var uid: String { return "error" }
    var arg: AlfredArg { return AlfredArg(arg1: "", arg2: "", arg3: "") }
    var autocomplete: String { return "" }
    var icon: String { return "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns" }
    var processName: String { return "" }
    var tabIndex: Int { return 0 }
}

/// Outputs an error message as an Alfred item and exits
func exitWithError(title: String, subtitle: String) -> Never {
    let errorItem = ErrorAlfredItem(title: title, subtitle: subtitle)
    print(AlfredDocument(withItems: [errorItem]).xml.xmlString)
    exit(1)
}

/// Removes browser window from the list of windows and adds tabs to the results array
func searchBrowserTabsIfNeeded(processName: String,
                               windows: [WindowInfoDict],
                               query: String,
                               results: inout [[AlfredItem]]) -> [WindowInfoDict] {
    
    let activeWindowsExceptBrowser = windows.filter { ($0.processName != processName) }
    
    let browserTabs =
        BrowserApplication.connect(processName: processName)?.windows
            .flatMap { return $0.tabs }
            .search(query: query)
    
    results.append(browserTabs ?? [])
    
    return activeWindowsExceptBrowser
}

func searchNativeTabsIfNeeded(processName: String,
                              windows: [WindowInfoDict],
                              query: String,
                              results: inout [[AlfredItem]]) -> [WindowInfoDict] {
    guard let nativeApplication = NativeTabApplication.connect(processName: processName) else {
        return windows
    }
    
    let nativeTabs = nativeApplication.tabs
    guard !nativeTabs.isEmpty else {
        return windows
    }
    
    let remainingWindows = windows.filter { $0.processName != processName }
    results.append(nativeTabs.search(query: query))
    return remainingWindows
}

func search(query: String, onlyTabs: Bool) {
    var results : [[AlfredItem]] = []
    
    var allActiveWindows : [WindowInfoDict] = Windows.all
    
    for browserName in ["Safari", "Safari Technology Preview",
                        "Google Chrome", "Google Chrome Canary",
                        "Opera", "Opera Beta", "Opera Developer",
                        "Brave Browser", "iTerm"] {
        allActiveWindows = searchBrowserTabsIfNeeded(processName: browserName,
                                                     windows: allActiveWindows,
                                                     query: query,
                                                     results: &results) // inout!
    }
    
    allActiveWindows = searchNativeTabsIfNeeded(processName: "Ghostty",
                                               windows: allActiveWindows,
                                               query: query,
                                               results: &results)
    
    if !onlyTabs {
        results.append(allActiveWindows.search(query: query))
    }
    
    let alfredItems : [AlfredItem] = results.flatMap { $0 }

    print(AlfredDocument(withItems: alfredItems).xml.xmlString)
}

func checkScreenRecordingPermission() {
    guard #available(macOS 10.15, *) else {
        return
    }

    guard CGPreflightScreenCaptureAccess() else {
        exitWithError(
            title: "Screen Recording Permission Required",
            subtitle: "Grant permission to Alfred in System Settings > Privacy & Security > Screen Recording"
        )
    }
}

checkScreenRecordingPermission()

/*
 a naive perf test, decided to keep it here for convenience

let start = DispatchTime.now() // <<<<<<<<<< Start time

for _ in 0...100 {
    search(query: "pull", onlyTabs: false)
}
let end = DispatchTime.now()   // <<<<<<<<<<   end time
let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)
let timeInterval = Double(nanoTime) / 1_000_000_000 // Technically could overflow for long running tests

print("TIME SPENT: \(timeInterval)")
*/

if(CommandLine.commands().isEmpty) {
    print("Unknown command!")
    print("Commands:")
    print("--search=<query> to search for active windows/Safari tabs.")
    print("--search-tabs=<query> to search for active browser tabs.")
    exit(1)
}

for command in CommandLine.commands() {
    switch command {
    case let searchCommand as SearchCommand:
        search(query: searchCommand.query, onlyTabs: false)
        exit(0)
    case let searchCommand as OnlyTabsCommand:
        search(query: searchCommand.query, onlyTabs: true)
        exit(0)
    default:
        print("Unknown command!")
        print("Commands:")
        print("--search=<query> to search for active windows/Safari tabs.")
        print("--search-tabs=<query> to search for active browser tabs.")
        exit(1)
    }
    
}
