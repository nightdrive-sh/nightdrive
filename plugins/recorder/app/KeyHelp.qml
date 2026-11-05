import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml). shell.qml does what they say: change a key
// there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Recording", keys: [
            ["Space", "Record, pause, go on"],
            ["⏎", "Save into ~/Recordings"],
            ["n", "New: save, and start the next one"],
            ["m", "Microphone (not in the middle of a piece: pause first)"],
            ["l", "While recording: the recordings, or back to the strip"]] },
        { title: "Recordings", keys: [
            ["↑ ↓  j k", "Move"],
            ["Home  End", "The newest, the oldest"],
            ["⏎", "Not recording: open it (narrow window: its own page)"],
            ["Esc", "Narrow window: back to the list"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["⌘Q", "Quit (a recording goes on: the top bar's icon)"]] }
    ]
}
