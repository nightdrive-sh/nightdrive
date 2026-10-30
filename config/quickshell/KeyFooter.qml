import QtQuick
import qs.kit as Kit

// A footer of keys as caps, then what each does, from one line of text: "Ctrl+Enter: show in Apps  ·  Esc: back". The
// launcher's card and Ask Claude's toast end with it. "Enter creates …" (no colon) works too, and a letter alone with a
// colon ("C: set up"); a part that doesn't start with a key is plain text. The first action with keys is the main one, at
// the right edge like a dialog's default button, so it's always in the same place; on a narrow card it takes more lines.
// Give it anchors.right and the room it may use (maxWidth): it is as wide as its parts in one line, at most that.
Flow {
    id: footer
    property string text: ""
    property real maxWidth: 600

    readonly property var parts: text === "" ? [] : text.split(/\s+·\s+/).map(part => {
        const m = part.match(/^((?:Ctrl|Shift|Alt|Cmd|Enter|Esc|Tab|Space|Backspace|Up|Down|Left|Right|PgUp|PgDn|[A-Z](?=:))(?:\+(?:Ctrl|Shift|Alt|Cmd|Enter|Esc|Tab|Space|Backspace|Up|Down|Left|Right|PgUp|PgDn|[A-Z]))*)(?::\s*|\s+)(.*)$/)
        return m ? { keys: m[1].split("+"), text: m[2] } : { keys: [], text: part }
    })
    readonly property real natural: children.reduce((w, c) => w + (c instanceof Row ? c.implicitWidth + spacing : 0), 0) - spacing

    visible: text !== ""
    width: Math.min(maxWidth, natural + rightPadding)
    rightPadding: 6
    spacing: 6
    layoutDirection: Qt.RightToLeft
    Repeater {
        model: footer.parts
        Row {
            id: part
            required property var modelData
            required property int index
            // The first action with keys is the main one (Enter: open); the rest are quieter
            readonly property bool main: index === 0 && modelData.keys.length > 0
            rightPadding: index > 0 ? 12 : 0     // 18 between actions with the Flow's spacing (right to left)
            spacing: 4
            Repeater {
                model: part.modelData.keys
                Kit.Key { required property string modelData; key: modelData; dim: !part.main }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: part.modelData.keys.length ? 4 : 0
                text: part.modelData.text.charAt(0).toUpperCase() + part.modelData.text.slice(1)
                color: part.main ? Theme.text : Theme.dim
                font { family: Theme.font; pixelSize: 12 }
            }
        }
    }
}
