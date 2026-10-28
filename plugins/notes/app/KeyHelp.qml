import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml). shell.qml does what they say: change a key
// there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Notes", keys: [
            ["↑ ↓  j k", "Move"],
            ["Home  End", "The newest, the oldest"],
            ["⏎  e", "Open in Apostrophe, to write in it"],
            ["Space  ⇧Space", "Scroll the note"],
            ["⌘B", "Show or hide the notes"],
            ["Esc", "Narrow window: the notes"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["⌘Q", "Quit"]] }
    ]
}
