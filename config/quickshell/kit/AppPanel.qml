import QtQuick

// A panel over the window (settings, a question before what can't be undone, a first start): the window dimmed behind a
// card in the middle, what it holds in a column inside. A click outside comes out as outsideTapped (most panels close on
// it); its keys are the app's (Keys.onPressed on the panel, once it has the focus). behind is the window's content under
// it, turned off while the panel shows: in Qt 6 the pointer handlers under an item that takes a press still get it, so a
// click on the panel also clicked the row under it (#1683). The focus goes back where it was if the app gives it nowhere.
Rectangle {
    id: root
    required property QtObject c
    property int cardWidth: 560
    property alias spacing: column.spacing
    default property alias content: column.data
    property Item behind: null
    signal outsideTapped()
    anchors.fill: parent
    color: c.scrim
    Binding { target: root.behind; property: "enabled"; value: false; when: root.visible && root.behind !== null }
    property Item focusBefore: null
    onVisibleChanged: {
        if (visible) {
            focusBefore = Window.activeFocusItem
            return
        }
        // After the app's own focus call, which may have come while behind was still off
        const back = focusBefore
        Qt.callLater(() => { if (back && !Window.activeFocusItem) back.forceActiveFocus() })
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.outsideTapped()
        onWheel: wheel => wheel.accepted = true
    }
    Rectangle {
        anchors.centerIn: parent
        width: root.cardWidth
        height: column.implicitHeight + 72
        radius: 14
        color: root.c.solid
        border.color: root.c.line
        MouseArea { anchors.fill: parent }      // a click inside keeps it open
        Column {
            id: column
            x: 40; y: 36
            width: parent.width - 80
            spacing: 18
        }
    }
}
