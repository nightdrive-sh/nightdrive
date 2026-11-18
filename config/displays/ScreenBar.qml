import QtQuick
import qs
import qs.kit

// Under the picture: the picked screen, what it is and where (main, off, away), and what can be done with it: Make main
// for one of the desk's, Put away or Bring back for a virtual one. In a narrow window the buttons go under the words.
Flow {
    id: root
    required property QtObject c
    property var screen: null
    signal makeMain()
    signal toggleAway()
    spacing: 10

    readonly property bool narrow: width < 520
    readonly property string state: {
        const s = screen
        if (!s) return ""
        const bits = []
        if (s.main) bits.push("Main display: workspaces 1–9")
        if (s.away) bits.push("Away: out of the pointer's reach")
        if (s.note !== "") bits.push(s.note)
        bits.push(s.w + " × " + s.h)
        return bits.join("  ·  ")
    }

    Column {
        width: root.narrow ? root.width : root.width - buttons.width - root.spacing
        spacing: 2
        Text {
            width: parent.width; elide: Text.ElideRight
            text: root.screen ? root.screen.name : ""
            color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            text: root.state
            color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
        }
    }

    Row {
        id: buttons
        spacing: 8
        AppButton {
            visible: !!root.screen && root.screen.kind !== "virtual" && !root.screen.main
            c: root.c; glyph: "panel-top"; label: "Make main"
            tip: "Workspaces 1–9 on this display"; keys: "m"
            onClicked: root.makeMain()
        }
        AppButton {
            visible: !!root.screen && root.screen.kind === "virtual"
            c: root.c; glyph: root.screen && root.screen.away ? "monitor" : "archive"
            label: root.screen && root.screen.away ? "Bring back" : "Put away"
            tip: root.screen && root.screen.away ? "Back beside your displays" : "Out of the pointer's reach"; keys: "a"
            onClicked: root.toggleAway()
        }
    }
}
