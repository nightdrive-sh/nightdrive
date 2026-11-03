import QtQuick
import qs

// Ferry's menu: the sends waiting for a computer that is asleep or off (`ferry list --json`'s waiting; Ferry's
// docs/protocol.md › Sends that wait), on a card of their own above what was received, newest first. Ferry sends each
// once its computer is back, or drops it after 3 days. A row says what and for whom ("Waiting for Studio · 3 d left");
// its round X cancels it (`ferry rm ID`), as the phone's and the window's Cancel. Nothing opens or copies here: the
// send isn't on the other end yet. A Ferry older than sends that wait has no waiting: the card stays hidden.
Rectangle {
    id: w
    required property var menu
    readonly property var sends: menu.st && menu.st.waiting
        ? menu.st.waiting.slice().sort((a, b) => b.time - a.time) : []
    // The sends just cancelled, until `ferry list` leaves them out (or a while has gone): their rows fade meanwhile
    property var cancelling: []
    onSendsChanged: cancelling = cancelling.filter(id => sends.some(s => s.id === id))
    Timer { id: cancelGiveUp; interval: 10000; onTriggered: w.cancelling = [] }
    function cancel(s) {
        if (cancelling.includes(s.id)) return
        cancelling = cancelling.concat([s.id])
        cancelGiveUp.restart()
        menu.run(["rm", s.id])
    }
    // How long a send has before Ferry drops it, as Ferry's own window says it (look.left): rounded days from 2 d
    function timeLeft(until) {
        const s = until - Date.now() / 1000
        return s >= 2 * 86400 ? Math.round(s / 86400) + " d left"
             : s >= 3600 ? Math.floor(s / 3600) + " h left" : Math.max(Math.floor(s / 60), 1) + " min left"
    }

    visible: sends.length > 0
    height: visible ? rows.height + 8 : 0
    radius: 14
    color: Theme.card

    Column {
        id: rows
        y: 4
        width: parent.width
        Repeater {
            model: w.sends
            delegate: Item {
                id: r
                required property var modelData
                required property int index
                readonly property bool isFile: modelData.kind === "file"
                readonly property bool gone: w.cancelling.includes(modelData.id)
                property bool navSelected: false
                readonly property bool navEnabled: !gone
                function navActivate() { w.cancel(r.modelData) }   // the row's only action: its X
                readonly property string label: "Cancel " + (isFile ? modelData.name : "text")   // `menu navkey` names it
                readonly property bool lit: !gone && (rowArea.containsMouse && !MenuPointer.pointerAway || navSelected)
                width: rows.width
                height: w.menu.rowHeight
                opacity: gone ? 0.45 : 1

                // The divider starts at the text, as in the received list
                Rectangle {
                    visible: r.index > 0
                    anchors { left: parent.left; leftMargin: 62; right: parent.right; rightMargin: 12 }
                    height: 1
                    color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.6)
                }
                Rectangle {
                    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                    radius: 10
                    color: r.lit ? Theme.hover : "transparent"
                    border { width: r.navSelected ? 1 : 0; color: Theme.primary }
                }
                Rectangle {
                    id: tile
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40; radius: 10
                    color: Theme.sel
                    Text {
                        anchors.centerIn: parent
                        text: Icons.g("clock")
                        color: Theme.accent
                        font { family: Icons.family; pixelSize: 19 }
                    }
                }
                Column {
                    anchors { left: tile.right; leftMargin: 12; right: mark.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        // A code or a password isn't shown on the bar's menu, which others may see (Ferry names it so)
                        text: r.isFile ? r.modelData.name || "" : r.modelData.secret ? "Code or password"
                            : (r.modelData.text || "").replace(/\s+/g, " ").trim()
                        // What was sent may have come from anywhere (a paste): AutoText would draw it as markup
                        textFormat: Text.PlainText
                        color: Theme.accent
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    // A long device name gives way, not the time left: the name is elided before it
                    Row {
                        width: parent.width
                        Text {
                            width: Math.min(implicitWidth, parent.width - leftText.implicitWidth)
                            elide: Text.ElideRight
                            text: r.gone ? "Cancelling…"
                                : [r.isFile ? w.menu.size(r.modelData.size || 0) : "", "Waiting for " + (r.modelData.deviceName || "")]
                                    .filter(x => x).join(" · ")
                            textFormat: Text.PlainText   // the device's name: never markup
                            color: Theme.dim
                            font { family: Theme.font; pixelSize: 11 }
                        }
                        Text {
                            id: leftText
                            text: r.gone ? "" : " · " + w.timeLeft(r.modelData.until)
                            color: Theme.dim
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true   // lights the row; a click beside the X does nothing
                }
                // Cancel: the send leaves the queue and is never made
                Rectangle {
                    id: mark
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 16
                    color: markArea.containsMouse && !r.gone ? Theme.danger : r.lit ? Theme.primary : Theme.sel
                    Text {
                        anchors.centerIn: parent
                        text: Icons.g("x")
                        color: markArea.containsMouse && !r.gone || r.lit ? Theme.bg : Theme.accent
                        font { family: Icons.family; pixelSize: 15 }
                    }
                    MouseArea {
                        id: markArea
                        anchors.fill: parent
                        enabled: !r.gone
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: w.cancel(r.modelData)
                    }
                }
            }
        }
    }
}
