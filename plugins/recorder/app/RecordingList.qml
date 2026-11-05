import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The recordings in the folder, newest first (Store.recordings): ↑ ↓ move, ⏎ opens one (in a narrow window, its own
// page). Empty, a line on how to make the first; a folder that can't be read, what went wrong.
Item {
    id: list
    required property QtObject c
    required property var app
    required property var store

    // The header: "Recordings" and how many, level with the view's
    Text {
        id: head
        anchors.left: parent.left; anchors.leftMargin: 18
        anchors.top: parent.top; anchors.topMargin: 12
        text: "Recordings"
        font.family: list.c.font; font.pixelSize: 12; font.weight: Font.DemiBold
        color: list.c.dim
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: head.verticalCenter
        visible: list.store.recordings.length > 0
        text: list.store.recordings.length
        font.family: list.c.font; font.pixelSize: 11
        color: list.c.faint
    }

    ListView {
        id: view
        anchors.fill: parent
        anchors.topMargin: 36
        anchors.leftMargin: 6; anchors.rightMargin: 6
        clip: true
        spacing: 2
        model: list.store.recordings
        currentIndex: list.store.index
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: RecordingRow {
            width: view.width
            c: list.c
            app: list.app
            store: list.store
        }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 48
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: list.store.loaded && !list.store.recordings.length || list.store.error !== ""
        text: list.store.error || "No recordings yet. Space starts one; it goes on with the window closed."
        font.family: list.c.font; font.pixelSize: 12
        color: list.store.error ? list.c.danger : list.c.faint
    }
}
