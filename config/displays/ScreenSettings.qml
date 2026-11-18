import QtQuick
import qs
import qs.kit

// The picked screen's panel, beside the picture (below it in a narrow window): what it is and where (main, lid closed,
// away), Make main or Put away / Bring back, then its own settings as Settings › Display has them: resolution, scale
// (the size it looks like) and refresh rate, each a list with the one in use checked. A virtual screen's size is VNC
// Display's, and a screen that is off has nothing to set until it is on: a line says so instead.
Item {
    id: root
    required property QtObject c
    required property DisplayCtl ctl
    property var screen: null
    signal makeMain()
    signal toggleAway()

    readonly property var info: screen ? ctl.of(screen.id) : null
    readonly property bool settable: !!screen && screen.kind !== "virtual" && screen.on && info !== null
    readonly property string state: {
        const s = screen
        if (!s) return ""
        const bits = []
        if (s.main) bits.push("Main display: workspaces 1–9")
        if (s.away) bits.push("Away: out of the pointer's reach")
        if (s.note !== "") bits.push(s.note)
        bits.push("looks like " + s.w + " × " + s.h)
        return bits.join("  ·  ")
    }

    // As wide as the panel and the option rows' inset on both sides (OptionRow), so their fill isn't clipped
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: -10; anchors.rightMargin: -10
        contentHeight: col.height + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TouchScroll { view: flick; step: 60 }

        Column {
            id: col
            x: 10
            width: flick.width - 20
            spacing: 6

            Text {
                width: parent.width; elide: Text.ElideRight
                text: root.screen ? root.screen.name : ""
                color: root.c.title; font.family: root.c.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: root.state
                color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
            }
            Flow {
                width: parent.width; spacing: 8
                topPadding: 4; bottomPadding: 4
                AppButton {
                    visible: !!root.screen && root.screen.kind !== "virtual" && !root.screen.main
                    c: root.c; glyph: "panel-top"; label: "Make main"; tipAlign: "left"
                    tip: "Workspaces 1–9 on this display"; keys: "m"
                    onClicked: root.makeMain()
                }
                AppButton {
                    visible: !!root.screen && root.screen.kind === "virtual"
                    c: root.c; glyph: root.screen && root.screen.away ? "monitor" : "archive"; tipAlign: "left"
                    label: root.screen && root.screen.away ? "Bring back" : "Put away"
                    tip: root.screen && root.screen.away ? "Back beside your displays" : "Out of the pointer's reach"; keys: "a"
                    onClicked: root.toggleAway()
                }
            }

            // Why there is nothing to set
            Text {
                visible: !!root.screen && !root.settable
                width: parent.width; wrapMode: Text.Wrap; topPadding: 6
                text: !root.screen ? "" : root.screen.kind === "virtual"
                      ? "Its size is the device's: Settings › Other displays › " + root.screen.name + " › Size"
                      : !root.screen.on ? "Its resolution, scale and refresh rate show here while it is on" : "Reading its settings…"
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
            }

            Section { c: root.c; text: "Resolution"; visible: root.settable }
            OptionRow {
                visible: root.settable
                c: root.c; label: "Automatic"; note: "the display's own"
                current: root.settable && root.info.savedMode === null
                onPicked: root.ctl.setMode(root.screen.id, "auto")
            }
            Repeater {
                model: root.settable ? root.info.resolutions : []
                OptionRow {
                    required property string modelData
                    c: root.c; label: modelData.replace("x", " × ")
                    current: root.info.savedMode !== null && root.info.resolution === modelData
                    note: root.info.savedMode === null && root.info.resolution === modelData ? "now" : ""
                    onPicked: root.ctl.setMode(root.screen.id, modelData)
                }
            }

            Section { c: root.c; text: "Scale"; visible: root.settable && root.info.scales.length > 0 }
            Repeater {
                model: root.settable ? root.info.scales : []
                OptionRow {
                    required property var modelData
                    c: root.c; label: "Looks like " + modelData.size
                    note: "scale " + +modelData.value.toFixed(2)
                    current: Math.abs(modelData.value - root.info.scale) < 0.01
                    onPicked: root.ctl.setScale(root.screen.id, modelData.value)
                }
            }

            Section { c: root.c; text: "Refresh rate"; visible: root.settable && root.info.rates.hz.length > 1 }
            Repeater {
                model: root.settable && root.info.rates.hz.length > 1 ? root.info.rates.hz : []
                OptionRow {
                    required property real modelData
                    c: root.c; label: Math.round(modelData) + " Hz"
                    current: root.info.rates.chosen !== "auto" && Math.abs(modelData - root.info.rates.chosen) < 0.01
                    onPicked: root.ctl.setRate(root.screen.id, modelData)
                }
            }
            OptionRow {
                visible: root.settable && root.info.rates.hz.length > 1
                c: root.c; label: "Automatic"; note: "the display's preferred"
                current: root.settable && root.info.rates.chosen === "auto"
                onPicked: root.ctl.setRate(root.screen.id, "auto")
            }
        }
    }

    // A section's title, as the launcher's: small capitals in the theme's colour
    component Section: Text {
        required property QtObject c
        topPadding: 10
        font.family: c.font; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        color: c.primary
    }
}
