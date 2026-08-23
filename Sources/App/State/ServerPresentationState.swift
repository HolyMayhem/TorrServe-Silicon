import AppKit

struct ServerPresentationState {
    let dotColor: NSColor
    let statusText: String
    let statusTooltip: String
    let canStart: Bool
    let canStop: Bool
    let canBrowse: Bool
    let canDownload: Bool
    let canOpenWeb: Bool
    let canEditPath: Bool
    let menuStatus: String
    let statusIconColor: NSColor
}
