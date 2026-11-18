import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml). shell.qml does what they say: change a key
// there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Screens", keys: [
            ["Tab  ⇧Tab", "Pick the next or the previous screen"],
            ["← → ↑ ↓", "Move the picked screen a screen's width that way"],
            ["m", "Make it the main display: workspaces 1–9"],
            ["a", "Put a virtual screen away, or bring it back"]] },
        { title: "Pointer", keys: [
            ["Drag", "Move a screen: it lands beside the nearest one"],
            ["Drag to Away", "Put a virtual screen out of the pointer's reach"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["Esc  ⌘Q", "Close"]] }
    ]
}
