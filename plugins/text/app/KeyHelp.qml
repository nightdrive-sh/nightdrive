import QtQuick

// The window's keys for its key sheet (Ctrl+?, kit/KeySheet.qml: ? alone is a character to type here). shell.qml does
// what they say: change a key there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Files", keys: [
            ["⌘O", "Open files"],
            ["⌘N", "New file: where it goes first"],
            ["⌘S", "Save; changed elsewhere: keep mine"],
            ["⌘W", "Close the file (asks if it isn't saved)"],
            ["Ctrl Tab  ⇧Ctrl Tab", "The next, the previous open file"],
            ["⌘B", "Show or hide the open files"]] },
        { title: "Text", keys: [
            ["⌘F", "Find: ⏎ next, ⇧⏎ previous, Esc back"],
            ["⌘G  ⇧⌘G", "Find the next, the previous"],
            ["⌘Z  ⇧⌘Z", "Undo, redo"],
            ["⌘A", "Select all"]] },
        { title: "Window", keys: [
            ["Ctrl ?", "These keys"],
            ["⌘Q", "Quit (asks about what isn't saved)"]] }
    ]
}
