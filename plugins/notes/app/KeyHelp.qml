import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml). shell.qml does what they say: change a key
// there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Notes", keys: [
            ["↑ ↓  j k", "Move"],
            ["Home  End", "The newest, the oldest"],
            ["⏎  e", "Write in it"],
            ["n  ⌘N", "New note: its title, then write"],
            ["F2  r", "Rename: its heading and file follow"],
            ["Del  ⌘⌫", "Move to the trash (⌘Z puts it back)"],
            ["⇧⏎", "Open in Apostrophe"],
            ["Space  ⇧Space", "Scroll the note"],
            ["⌘B", "Show or hide the notes"],
            ["Esc", "Narrow window: the notes"]] },
        { title: "Writing", keys: [
            ["Esc", "Back to reading"],
            ["⌘S", "Save now (it saves by itself); changed elsewhere: keep mine"],
            ["⌘Z  ⇧⌘Z", "Undo, redo"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["⌘Q", "Quit"]] }
    ]
}
