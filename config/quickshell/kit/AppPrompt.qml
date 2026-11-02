import QtQuick
import qs.kit

// A name asked for in a panel (Garage: a snapshot's, or a VM's to delete it): the question over a field with its text
// picked, so typing replaces it. Return answers, Esc or a click outside doesn't. ask(title, initial, then) opens it;
// then gets the trimmed text, and closed comes out either way, for the app to take the focus back.
AppPanel {
    id: root
    property var done: null
    visible: done !== null
    cardWidth: 440
    onOutsideTapped: answer(false)

    function ask(title, initial, then) {
        field.label = title
        field.text = initial
        done = then
        field.input.forceActiveFocus()
        field.input.selectAll()
    }
    signal closed()
    function answer(ok) {
        const d = done
        done = null
        if (ok && d) d(field.text.trim())
        closed()
    }

    AppField {
        id: field
        c: root.c
        width: parent.width
        onAccepted: root.answer(true)
        onEscaped: root.answer(false)
    }
}
