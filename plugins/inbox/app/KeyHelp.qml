import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml). shell.qml does what they say: change a key
// there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "Messages", keys: [
            ["↑ ↓  j k", "Move"],
            ["Home  End", "The newest, the oldest"],
            ["/  ⌘F", "Search the titles, text and senders (Esc: every message)"],
            ["a", "Archive (in the archive: back to the inbox); ⌘Z undoes"],
            ["u", "Mark read or unread"],
            ["d  Del", "Delete for good, after asking"],
            ["1 … 8", "Press the message's button (a command asks first)"],
            ["s", "Go to the session that left it"],
            ["t", "Open its task"],
            ["i", "Its first picture over the window (← → the others)"],
            ["p", "Play or pause its sound file (one at a time)"],
            ["← →", "Play the sound before or after: compare a few quickly"],
            ["f", "Inbox, archive and senders: ↑ ↓ pick, ⏎ back"],
            ["Space  ⇧Space", "Scroll the message"],
            ["⌘B", "Show or hide the sidebars"],
            ["Esc", "Narrow window: the messages"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["⌘Q", "Quit"]] }
    ]
}
