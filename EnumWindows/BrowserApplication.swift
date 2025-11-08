import Foundation
import AppKit
import ApplicationServices
import ScriptingBridge

protocol BrowserEntity {
    var rawItem : AnyObject { get }
}

protocol BrowserNamedEntity : BrowserEntity {
    var title : String { get }
}

extension BrowserEntity {
    func performSelectorByName<T>(name : String, defaultValue : T) -> T {
        let sel = Selector(name)
        guard self.rawItem.responds(to: sel) else {
            return defaultValue
        }

        let selectorResult = self.rawItem.perform(sel)

        guard let retainedValue = selectorResult?.takeRetainedValue() else {
            return defaultValue
        }
        
        guard let result = retainedValue as? T else {
            return defaultValue
        }
        
        return result
    }
}

class BrowserTab : BrowserNamedEntity, Searchable, ProcessNameProtocol {
    private let tabRaw : AnyObject
    private let index : Int?
    
    let windowTitle : String
    let processName : String
    
    init(raw: AnyObject, index: Int?, windowTitle: String, processName: String) {
        tabRaw = raw
        self.index = index
        self.windowTitle = windowTitle
        self.processName = processName
    }
    
    var rawItem: AnyObject {
        return self.tabRaw
    }
        
    var url : String {
        return performSelectorByName(name: "URL", defaultValue: "")
    }

    var title : String {
        /* Safari uses 'name' as the tab title, while most of the browsers have 'title' there */
        if self.rawItem.responds(to: Selector("name")) {
            return performSelectorByName(name: "name", defaultValue: "")
        }
        return performSelectorByName(name: "title", defaultValue: "")
    }
    
    var tabIndex : Int {
        guard let i = index else {
            return 0
        }
        return i
    }
    
    var searchStrings : [String] {
        return ["Browser", self.url, self.title, self.processName]
    }
    
    /*
     (lldb) po raw.perform("URL").takeRetainedValue()
     https://encrypted.google.com/search?hl=en&q=objc%20mac%20list%20Browser%20tabs#hl=en&q=swift+call+metho+by+name
     
     
     (lldb) po raw.perform("name").takeRetainedValue()
     scriptingbridge Browsertab - Google Search
 */
}

class iTermTab : BrowserTab {
    override var title : String {
        guard self.rawItem.responds(to: Selector("currentSession")),
            let session: AnyObject = performSelectorByName(name: "currentSession", defaultValue: nil),
            session.responds(to: Selector("name"))
        else {
            return self.windowTitle
        }

        let selectorResult = session.perform(Selector("name"))
        guard let retainedValue = selectorResult?.takeRetainedValue(),
            let tabName = retainedValue as? String
        else {
            return self.windowTitle
        }
        return tabName
    }
}

class BrowserWindow : BrowserNamedEntity {
    private let windowRaw : AnyObject
    
    let processName : String
    
    init(raw: AnyObject, processName: String) {
        windowRaw = raw
        self.processName = processName
    }
    
    var rawItem: AnyObject {
        return self.windowRaw
    }
    
    var tabs : [BrowserTab] {
        let result = performSelectorByName(name: "tabs", defaultValue: [AnyObject]())
        
        return result.enumerated().map { (index, element) in
            if processName == "iTerm" {
                return iTermTab(raw: element, index: index + 1, windowTitle: self.title, processName: self.processName)
            }
            return BrowserTab(raw: element, index: index + 1, windowTitle: self.title, processName: self.processName)
        }
    }

    var title : String {
        /* Safari uses 'name' as the tab title, while most of the browsers have 'title' there */
        if self.rawItem.responds(to: Selector("name")) {
            return performSelectorByName(name: "name", defaultValue: "")
        }
        return performSelectorByName(name: "title", defaultValue: "")
    }
}

class BrowserApplication : BrowserEntity {
    private let app : SBApplication
    private let processName : String
    
    static func connect(processName: String) -> BrowserApplication? {

        let ws = NSWorkspace.shared

        guard let fullPath = ws.fullPath(forApplication: processName) else {
            return nil
        }

        let bundle = Bundle(path: fullPath)
        
        guard let bundleId = bundle?.bundleIdentifier else {
            return nil
        }
        
        let runningBrowsers = ws.runningApplications.filter { $0.bundleIdentifier == bundleId }
        
        guard runningBrowsers.count > 0 else {
            return nil
        }
        
        guard let app = SBApplication(bundleIdentifier: bundleId) else {
            return nil
        }

        return BrowserApplication(app: app, processName: processName)
    }
    
    init(app: SBApplication, processName: String) {
        self.app = app
        self.processName = processName
    }
    
    var rawItem: AnyObject {
        return app
    }
    
    var windows : [BrowserWindow] {
        let result = performSelectorByName(name: "windows", defaultValue: [AnyObject]())
        return result.map {
            return BrowserWindow(raw: $0, processName: self.processName)
        }
    }
}

// MARK: - Native macOS tab support (Ghostty)

struct NativeAppTab: AlfredItem, Searchable, ProcessNameProtocol {
    let processName: String
    let windowTitle: String
    let tabTitle: String
    let tabIndex: Int
    
    var uid: String {
        return "native-\(processName)-\(windowTitle)-\(tabIndex)"
    }
    
    var arg: AlfredArg {
        return AlfredArg(arg1: processName, arg2: "\(tabIndex)", arg3: windowTitle)
    }
    
    var autocomplete: String { return tabTitle }
    var title: String { return tabTitle }
    var subtitle: String { return "Window: \(windowTitle)" }
    var searchStrings: [String] { return [processName, windowTitle, tabTitle] }
}

class NativeTabApplication {
    private let applicationElement: AXUIElement
    private let processName: String
    
    static func connect(processName: String) -> NativeTabApplication? {
        let workspace = NSWorkspace.shared
        
        guard let fullPath = workspace.fullPath(forApplication: processName),
              let bundle = Bundle(path: fullPath),
              let bundleId = bundle.bundleIdentifier else {
            return nil
        }
        
        guard let runningApplication = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            return nil
        }
        
        let element = AXUIElementCreateApplication(runningApplication.processIdentifier)
        return NativeTabApplication(applicationElement: element, processName: processName)
    }
    
    init(applicationElement: AXUIElement, processName: String) {
        self.applicationElement = applicationElement
        self.processName = processName
    }
    
    var tabs: [NativeAppTab] {
        guard AXIsProcessTrusted() else {
            return []
        }
        let windows = axElements(applicationElement, attribute: kAXWindowsAttribute as CFString)
        return windows.flatMap { NativeTabWindow(element: $0, processName: processName).tabs }
    }
}

fileprivate struct NativeTabWindow {
    private let element: AXUIElement
    private let processName: String
    
    init(element: AXUIElement, processName: String) {
        self.element = element
        self.processName = processName
    }
    
    var tabs: [NativeAppTab] {
        let windowTitle = axString(element, attribute: kAXTitleAttribute as CFString) ?? processName

        if let tabsFromWindow = tabs(from: element, windowTitle: windowTitle), !tabsFromWindow.isEmpty {
            return tabsFromWindow
        }

        let childElements = axElements(element, attribute: kAXChildrenAttribute as CFString)
        for child in childElements where axRole(child) == kAXTabGroupRole as String {
            if let tabsFromGroup = tabs(from: child, windowTitle: windowTitle), !tabsFromGroup.isEmpty {
                return tabsFromGroup
            }
        }

        return []
    }

    private func tabs(from element: AXUIElement, windowTitle: String) -> [NativeAppTab]? {
        let tabElements = axElements(element, attribute: kAXTabsAttribute as CFString)
        guard !tabElements.isEmpty else {
            return nil
        }

        return tabElements.enumerated().map { index, tabElement in
            let tabTitle = axString(tabElement, attribute: kAXTitleAttribute as CFString) ?? windowTitle
            let resolvedTitle = tabTitle.isEmpty ? windowTitle : tabTitle
            return NativeAppTab(processName: processName,
                                windowTitle: windowTitle,
                                tabTitle: resolvedTitle,
                                tabIndex: index + 1)
        }
    }
}

fileprivate func axElements(_ element: AXUIElement, attribute: CFString) -> [AXUIElement] {
    guard let value = copyAttributeValue(element, attribute: attribute) else {
        return []
    }
    
    guard CFGetTypeID(value) == CFArrayGetTypeID() else {
        return []
    }
    
    let cfArray = unsafeBitCast(value, to: CFArray.self)
    let count = CFArrayGetCount(cfArray)
    var result: [AXUIElement] = []
    for index in 0..<count {
        let rawPointer = CFArrayGetValueAtIndex(cfArray, index)
        let axElement = unsafeBitCast(rawPointer, to: AXUIElement.self)
        result.append(axElement)
    }
    return result
}

fileprivate func axString(_ element: AXUIElement, attribute: CFString) -> String? {
    guard let value = copyAttributeValue(element, attribute: attribute) else {
        return nil
    }
    return value as? String
}

fileprivate func copyAttributeValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success, let unwrapped = value else {
        return nil
    }
    return unwrapped
}

fileprivate func axRole(_ element: AXUIElement) -> String? {
    return axString(element, attribute: kAXRoleAttribute as CFString)
}
