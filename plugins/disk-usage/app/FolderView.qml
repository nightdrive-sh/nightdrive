import QtQuick
import QtQuick.Layouts
import qs
import qs.kit
import "Fmt.js" as Fmt

// The folder on show: where it is (a trail back to the place, each part a click away), its size in big figures, how it
// splits (SplitBar), and its entries biggest first (ItemRow). While a scan runs, its progress shows instead (ScanView).
// The window (shell.qml, `app`) holds the tree and the keys; this draws them.
Item {
    id: root
    required property QtObject c
    required property var app
    readonly property alias list: list
    readonly property alias listView: listView

    // The trail's parts from the place on; a long one shows its last parts after a …
    readonly property int shownParts: width < 640 ? 2 : 4

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20; Layout.rightMargin: 16; Layout.topMargin: 16
            Layout.preferredHeight: 26
            spacing: 6
            AppIconButton {
                visible: root.app.trail.length > 1
                c: root.c; glyph: "arrow-left"; tip: "Up a folder"; keys: "←"
                onClicked: root.app.up()
            }
            Row {
                Layout.fillWidth: true
                Layout.leftMargin: root.app.trail.length > 1 ? 2 : 8
                clip: true
                spacing: 6
                Text {
                    visible: root.app.trail.length > root.shownParts
                    anchors.verticalCenter: parent.verticalCenter
                    text: "…  ›"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
                }
                Repeater {
                    model: root.app.trail.length
                    delegate: Row {
                        id: part
                        required property int index
                        readonly property bool last: index === root.app.trail.length - 1
                        visible: index >= root.app.trail.length - root.shownParts
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        spacing: 6
                        Text {
                            textFormat: Text.PlainText
                            text: part.index === 0 ? root.app.placeName : root.app.trail[part.index].n
                            color: part.last ? root.c.title : partHover.hovered ? root.c.text : root.c.dim
                            font.family: root.c.font; font.pixelSize: 13
                            font.weight: part.last ? Font.Medium : Font.Normal
                            HoverHandler { id: partHover; enabled: !part.last; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: !part.last; onTapped: root.app.goTo(part.index) }
                        }
                        Text {
                            visible: !part.last
                            text: "›"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
                        }
                    }
                }
            }
            AppIconButton {
                visible: root.app.tree !== null
                c: root.c; glyph: "folder-open"; tip: "Show in Files"; keys: "o"; tipAlign: "right"
                onClicked: root.app.showInFiles(-1)
            }
            AppIconButton {
                c: root.c; glyph: "refresh-cw"; tip: "Scan again"; keys: "⌘R"; tipAlign: "right"
                onClicked: root.app.rescan()
            }
        }

        // The size, what it is of, and how it splits
        Column {
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.topMargin: 22
            visible: root.app.here !== null && !root.app.scanning
            spacing: 6
            Text {
                text: root.app.here ? Fmt.bytes(root.app.hereSize) : ""
                color: root.c.title; font.family: root.c.font; font.pixelSize: 30; font.weight: Font.Light
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: root.app.summary
                color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
            }
            Item { width: 1; height: 10 }
            SplitBar {
                width: parent.width
                c: root.c
                parts: root.app.parts
                total: root.app.hereSize
                onHotChanged: root.app.hot = hot
                onPicked: index => root.app.enter(index)
            }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.topMargin: 20
            Layout.preferredHeight: 1
            visible: root.app.here !== null && !root.app.scanning
            color: root.c.divider
        }

        FocusScope {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            Keys.onPressed: e => root.app.pressed(e)
            ListView {
                id: listView
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                visible: !root.app.scanning
                clip: true
                model: root.app.rows
                currentIndex: root.app.current
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                spacing: 2
                topMargin: 8; bottomMargin: 12
                TouchScroll { view: listView }
                delegate: ItemRow {
                    required property var modelData
                    required property int index
                    c: root.c
                    item: modelData
                    biggest: root.app.rows.length ? root.app.rows[0].s : 0
                    total: root.app.hereSize
                    tint: root.app.tints[index] || root.c.faint
                    hot: root.app.hot === index
                    selected: index === root.app.current
                    active: list.activeFocus
                    onOpen: { root.app.current = index; root.app.enter(index) }
                }
            }
            // Nothing to list: an empty folder, one that couldn't be read, or no scan yet
            Text {
                visible: !root.app.scanning && root.app.rows.length === 0
                anchors.centerIn: parent
                width: parent.width - 48; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: root.app.tree === null ? (root.app.scanner.error || "")
                    : root.app.here && root.app.here.u ? "This folder couldn't be read: it isn't yours"
                    : "Nothing in this folder"
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
            }
            ScanView {
                visible: root.app.scanning
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 440)
                c: root.c
                scanner: root.app.scanner
                what: root.app.scanner.graft ? root.app.scanner.path.split("/").pop() : root.app.placeName
                onStop: root.app.stopScan()
            }
        }

        // When it was scanned, and what was left out; what just happened, for a while, in its place
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.bottomMargin: 18; Layout.topMargin: 6
            elide: Text.ElideRight
            text: root.app.note || root.app.scanNote
            color: root.app.note ? root.c.text : root.c.faint
            font.family: root.c.font; font.pixelSize: 11
        }
    }
}
