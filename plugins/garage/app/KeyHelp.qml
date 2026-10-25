import QtQuick

// The window's keys for its key sheet (? and Ctrl+?, kit/KeySheet.qml), in the groups it shows them in. shell.qml and
// SnapshotList.qml do what they say: change a key there, and its line here.
QtObject {
    readonly property var groups: [
        { title: "VMs", keys: [
            ["↑ ↓  j k", "Move"],
            ["⌘N", "New VM"],
            ["⌘,", "Settings: memory, CPUs, disk, ISO"],
            ["⌘⌫", "Delete the VM, while it is stopped"],
            ["⌘B", "Show or hide the VMs"],
            ["Esc", "Narrow window: the VMs"]] },
        { title: "Power", keys: [
            ["s", "Start"],
            ["d", "Bring its display forward"],
            ["x", "Shut down"],
            ["⇧X", "Force off: pull the plug"]] },
        { title: "Snapshots", keys: [
            ["t", "Take one, while it is stopped"],
            ["Tab", "To the list, and back"],
            ["⏎", "Restore, while it is stopped"],
            ["e  F2", "Rename"],
            ["Del", "Delete, while it is stopped"]] },
        { title: "Window", keys: [
            ["?", "These keys"],
            ["⌘Q", "Quit"]] }
    ]
}
