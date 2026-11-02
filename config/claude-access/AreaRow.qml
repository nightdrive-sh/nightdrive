import QtQuick
import qs
import qs.kit
import "Words.js" as Words

// An area's row: its glyph and name, Read / Modify / Delete (ChoiceCell), and More › for its panel (AreaPanel). The picked
// row says under it, in plain words, what each of its choices lets Claude do now and what goes to Anthropic.
AppRow {
    id: row
    property var area: ({ glyph: "", name: "", rights: {} })
    required property int index
    property int col: -1                // the keyboard's column when this row is picked: 0–2 a right, 3 the panel
    property int nameWidth: 230
    property int cellWidth: 112
    signal cellClicked(int col, Item cell)
    implicitHeight: body.implicitHeight + 14
    function cellAt(i) { return cells.itemAt(i) }

    TapHandler { onTapped: row.cellClicked(-1, null) }   // a click on the row picks it

    Column {
        id: body
        x: 12; y: 7
        width: parent.width - 24
        spacing: 6

        Row {
            height: 30
            Row {
                width: row.nameWidth
                height: parent.height
                spacing: 10
                Text {
                    width: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.g(row.area.glyph); color: row.selected ? row.c.accent : row.c.dim
                    font { family: Icons.family; pixelSize: 15 }
                }
                Text {
                    width: row.nameWidth - 28
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.area.name; elide: Text.ElideRight
                    color: row.c.text
                    font { family: row.c.font; pixelSize: 13; weight: row.selected ? Font.DemiBold : Font.Normal }
                }
            }
            Repeater {
                id: cells
                model: Words.RIGHTS
                ChoiceCell {
                    id: cell
                    required property string modelData
                    required property int index
                    width: row.cellWidth
                    anchors.verticalCenter: parent.verticalCenter
                    c: row.c
                    info: row.area.rights[modelData] || null
                    current: row.selected && row.col === index
                    onClicked: row.cellClicked(index, cell)
                }
            }
            // The area's details: every tool, and its own choices. A word beside the arrow, as a bare › didn't say
            // there was more behind it (#1902)
            Item {
                width: moreBox.width + 16; height: parent.height
                Rectangle {
                    id: moreBox
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: moreRow.implicitWidth + 20; height: 26; radius: 7
                    color: more.hovered ? row.c.hover : "transparent"
                    border.color: row.selected && row.col === 3 ? row.c.primary : row.c.line
                    border.width: row.selected && row.col === 3 ? 2 : 1
                    HoverHandler { id: more; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: row.cellClicked(3, null) }
                    Row {
                        id: moreRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "More"; color: row.c.text
                            font { family: row.c.font; pixelSize: 12 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.g("chevron-right"); color: row.c.dim
                            font { family: Icons.family; pixelSize: 13 }
                        }
                    }
                }
            }
        }

        // What the choices mean, for the picked row only: the list stays short enough to see at a glance
        Repeater {
            model: row.selected ? Words.lines(row.area) : []
            Text {
                required property string modelData
                x: 28
                width: body.width - 28
                text: modelData
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                lineHeight: 1.15
                color: row.c.dim
                font { family: row.c.font; pixelSize: 12 }
            }
        }
    }
}
