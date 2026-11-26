import QtQuick
import qs.kit

// A name asked for in a panel (Garage: a snapshot's, or a VM's to delete it): the question over a field with its text
// picked, so typing replaces it. Return answers, Esc or a click outside doesn't. ask(title, initial, then) opens it;
// then gets the trimmed text, and closed comes out either way, for the app to take the focus back. A fourth argument
// picks only the text's start up to there (a file's name without its ".pdf", as Files' rename does).
AppPanel {
    id: root
    property var done: null
    visible: done !== null
    cardWidth: 440
    onOutsideTapped: answer(false)

    function ask(title, initial, then, pickTo) {
        field.label = title
        field.text = initial
        done = then
        field.input.forceActiveFocus()
        if (pickTo !== undefined && pickTo >= 0) field.input.select(0, pickTo)
        else field.input.selectAll()
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
