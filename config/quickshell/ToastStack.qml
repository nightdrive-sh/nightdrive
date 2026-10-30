import QtQuick
import Quickshell
import Quickshell.Wayland

// The toasts' place: one surface at the top centre, just below the bar, with the shown cards (Toast.qml) stacked
// downwards in the order they're declared in shell.qml. A long-lived card (dictation, later Ask Claude) goes first, so
// a volume toast meanwhile appears below it instead of covering it.
PanelWindow {
    id: stack
    default property alias cards: column.data
    readonly property bool anyShown: {
        for (let i = 0; i < column.children.length; i++)
            if (column.children[i].shown) return true
        return false
    }

    visible: anyShown
    anchors { top: true }
    margins { top: Theme.barHeight + 8 }
    implicitWidth: Math.max(1, column.width)
    implicitHeight: Math.max(1, column.height)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nightdrive-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}          // clicks pass through the toasts

    Column {
        id: column
        spacing: 8
    }
}
