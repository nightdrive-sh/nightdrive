import QtQuick
import qs.kit

// Curated's New list asks first, as it costs a few minutes of the Claude plan: the question over the window, where its
// line has room to wrap (on the header row beside the title it was cut short). The answers as Garage's (PanelButton): Enter
// or "Make it" makes the list, Esc, "Cancel" or a click outside doesn't. The window shows it (visible) and takes the
// keys back on answered().
AppPanel {
    id: root
    signal answered(bool yes)
    cardWidth: 440
    onVisibleChanged: if (visible) forceActiveFocus()
    onOutsideTapped: answered(false)
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) answered(true)
        else if (e.key === Qt.Key_Escape) answered(false)
        e.accepted = true
    }
    Text { text: "A new Curated list?"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Text {
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.text; font.family: c.font; font.pixelSize: 12
        text: "Claude picks new albums for you in a few minutes, on your Claude plan. It runs on its own: you can close the window, and the list shows up here when it's ready."
    }
    Row {
        spacing: 8
        PanelButton { c: root.c; label: "Make it"; strong: true; keys: ["Enter"]; onClicked: root.answered(true) }
        PanelButton { c: root.c; label: "Cancel"; keys: ["Esc"]; onClicked: root.answered(false) }
    }
}
