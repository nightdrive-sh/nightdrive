import QtQuick
import qs.kit

// A name asked for in a panel (a snapshot's, or a VM's to delete it): the question over a field with its text picked,
// Return answers, Esc or a click outside doesn't. ask() opens it; done gets the trimmed text.
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

    Field {
        id: field
        c: root.c
        width: parent.width
        onAccepted: root.answer(true)
        onEscaped: root.answer(false)
    }
}
