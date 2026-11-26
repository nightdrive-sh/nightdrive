import QtQuick

// The top bar's "…" (BarOverflow): the modules that didn't fit on this screen's bar, in the bar's order. A row opens the
// module's menu in this one's place, below the "…" (or runs its "click"); one without either is only listed. TopBar.overflow is the list of the
// bar whose "…" was clicked.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 10
    signal close()
    signal openMenu(string name)       // shell.qml opens that menu where this one is

    MenuHeader { width: parent.width; title: "More" }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: TopBar.overflow
            MenuRow {
                required property var modelData
                readonly property var st: TopBar.states[modelData.def.name] || null
                width: parent.width
                // The same icon and name as Settings › Top bar › Items (the module's own icon is a state, often
                // a number)
                icon: TopBar.moduleGlyph(modelData.def)
                label: TopBar.moduleLabel(modelData.def)
                detail: st && st.text ? st.text : ""
                interactive: modelData.menu !== "" || !!modelData.def.click
                padded: true
                // A module whose left click is a command (modules.jsonc "click") runs it here too
                onClicked: {
                    if (modelData.def.click) { TopBar.run(modelData.def.click, modelData.def.name); m.close() }
                    else m.openMenu(modelData.menu)
                }
            }
        }
    }
}
