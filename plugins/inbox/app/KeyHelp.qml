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
            ["⇧U", "Mark every message shown read"],
            ["d  ⌫  ⌘⌫", "Delete for good, after asking"],
            ["⌥1 … ⌥8", "Press the message's button (a command asks first)"],
            ["s", "Go to the session that left it"],
            ["t", "Open its task"],
            ["i", "Its first picture over the window (← → the others)"],
            ["p", "Play or pause its sound file (one at a time)"],
            ["← →", "Play the sound before or after: compare a few quickly"],
            ["Space  ⇧Space", "Scroll the message"]] },
        { title: "Selecting", keys: [
            ["v", "Select and go on: j k keep what is selected"],
            ["⇧↑ ⇧↓", "Select from the open message (⇧-click, Ctrl-click)"],
            ["⌘A", "Select every message: a, u and d act on them all"],
            ["Esc", "Only one again"]] },
        { title: "Views", keys: [
            ["1 – 3", "Inbox, Unread, Archive"],
            ["Ctrl ↑ ↓", "Previous, next"],
            ["Tab ⇧Tab", "To the sidebar (↑ ↓ pick a sender), and back"],
            ["⌘B", "Show or hide the sidebars"]] },
        { title: "Window", keys: [
            ["⏎  o  l  →", "Narrow window: open the message"],
            ["Esc  ←", "Narrow window: the messages"],
            ["?", "These keys"],
            ["⌘Q", "Quit"]] }
    ]
}
