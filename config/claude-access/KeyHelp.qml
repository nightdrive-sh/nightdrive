import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml). shell.qml does what they say: change a key
// there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Access", keys: [
            ["↑ ↓  j k", "Move between the areas"],
            ["← →  h l", "Read, Modify, Delete, the area's details"],
            ["⏎  Space", "Choose (or the details, on ›)"],
            ["1  2  3", "Allow, Ask, No"],
            ["i", "The area's details"]] },
        { title: "Level", keys: [
            ["⌘1  ⌘2  ⌘3", "Strict, Normal, Open"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["Esc  ⌘Q", "Close"]] }
    ]
}
