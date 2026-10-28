import QtQuick
import Quickshell
import Quickshell.Widgets

// The launcher's details card for a package (Install › Software, Remove) or a plugin (Install › Recommended, Plugins):
// header (icon, name, summary, the plugin's on/off switch, the Install / Remove / Run installer again and Set up with Claude buttons), facts, screenshot and
// description, from hypr/scripts/pkg-info or plugin-info. The results stay as they were behind it.
// Enter installs or removes in a terminal (confirm), Tab takes the app from the other source or turns a plugin off or on
// (switchSource), C runs a plugin's setup with Claude (setup), the arrows scroll (scroll). Launcher.qml shows it in place of the list while `item` is set, widens the
// card and shows `footer`.
Flickable {
    id: card
    property var launcher: null
    property var item: null                   // the row whose details are shown ({ name, summary, src, id, cmd, remove, rerun, alt }), null = closed
    property var info: null                   // its details (null = still loading)
    readonly property var pkg: item || ({})
    signal pluginToggled()                    // a plugin was turned off or on: its list is read again

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property string footer: item === null ? ""
        : (item.remove ? "Enter: remove" : item.rerun ? (info && info.installed ? "Enter: run the installer again" : "Enter: install in a terminal")
                                                      : info && info.installed ? "Already installed" : "Enter: install")
          + (item.alt ? "  ·  Tab: get it from " + (item.alt.src === "flatpak" ? "Flathub" : "Fedora") : "")
          + (item.src === "plugin" && info && info.installed ? "  ·  Tab: turn " + (info.off ? "on" : "off") : "")
          + (canSetup ? "  ·  C: set up with Claude" : "")
          + "  ·  Esc: back"
    // A plugin whose plugin.conf has `setup` (a command that sets it up with Claude, e.g. Mail's account), once installed
    readonly property bool canSetup: item !== null && item.src === "plugin" && info !== null && info.installed && !!info.setup

    visible: item !== null
    height: visible ? Math.min(contentHeight, Math.min(launcher.maxRows * launcher.rowHeight, launcher.listRoom) + 60) : 0
    contentHeight: detailCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    TouchScroll { view: card; step: launcher.rowHeight }

    function show(row) {
        item = row; info = null; launcher.armed = ""
        contentY = 0
        if (!detailProc.running) run()                // otherwise the running one notices it's stale and starts again
    }
    function close() { item = null; info = null }
    function run() {
        detailProc.forId = item.src + ":" + item.id
        detailProc.command = item.src === "plugin" ? [scripts + "/plugin-info", item.id] : [scripts + "/pkg-info", item.src, item.id]
        detailProc.running = true
    }
    // Enter: installs / removes in a terminal (an installed package can't be installed again, a plugin's installer can run again)
    function confirm() {
        if (!item.remove && !item.rerun && info && info.installed) { launcher.shakeNow(); return }
        launcher.open = false
        Quickshell.execDetached(item.cmd)
    }
    // C: plugin.conf's setup, run in the plugin's folder (it opens Claude Code in a terminal)
    function setup() {
        if (!canSetup) { launcher.shakeNow(); return }
        launcher.open = false
        Quickshell.execDetached(info.setup)
    }
    // Tab: the same app from the other source (Fedora ↔ Flathub); on a plugin's page, turns it off or on
    function switchSource() {
        if (item.src === "plugin") { pluginToggle(); return }
        const a = item.alt
        if (!a) { launcher.shakeNow(); return }
        show(Object.assign({}, item, { src: a.src, id: a.id, alt: { src: item.src, id: item.id }, cmd: launcher.installCmd(a.src, a.id) }))
    }
    function scroll(dy) { contentY = Math.max(0, Math.min(contentHeight - height, contentY + dy)) }
    // A plugin's switch: `nightdrive plugins off|on`, which hides it from the desktop and stops its services, or brings them
    // back. The switch moves at once; the page and the list are read again when it's done.
    function pluginToggle() {
        if (!info || !info.installed || toggleProc.running) { launcher.shakeNow(); return }
        toggleProc.command = [Quickshell.env("HOME") + "/.local/bin/nightdrive", "plugins", info.off ? "on" : "off", item.id]
        info = Object.assign({}, info, { off: !info.off })
        toggleProc.running = true
    }
    Sh {
        id: toggleProc
        onResult: {
            if (detailProc.running) detailProc.forId = ""      // the running one read the old state: it starts again
            else if (card.item !== null) card.run()
            card.pluginToggled()
        }
    }
    Sh {
        id: detailProc
        property string forId: ""
        onResult: text => {
            const it = card.item
            if (it === null) return
            if (it.src + ":" + it.id !== forId) { card.run(); return }
            try { card.info = JSON.parse(text) }
            catch (e) { card.info = { name: it.name, summary: it.summary, installed: false, icon: "", screenshot: "", paragraphs: [], fields: [["Details", "not available"]] } }
        }
    }

    // The header's buttons: grey and still when `off` (already installed)
    component CardButton: Rectangle {
        id: cb
        property bool off: false
        property string glyph: ""
        property string label: ""
        signal clicked()
        width: cbRow.implicitWidth + 32
        height: 40
        radius: 10
        color: off ? "transparent" : cbArea.containsMouse ? Theme.primary : Theme.sel
        border.width: off ? 1 : 0
        border.color: Theme.border
        Row {
            id: cbRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.g(cb.glyph)
                color: cb.off ? Theme.dim : cbArea.containsMouse ? Theme.bg : Theme.accent
                font { family: Icons.family; pixelSize: 17 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: cb.label
                color: cb.off ? Theme.dim : cbArea.containsMouse ? Theme.bg : Theme.accent
                font { family: Theme.font; pixelSize: launcher.fontSize - 1; weight: Font.Normal }
            }
        }
        MouseArea {
            id: cbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: cb.off ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }

    Column {
        id: detailCol
        width: card.width
        spacing: 18
        topPadding: 4
        bottomPadding: 6

        Item {      // header
            width: parent.width
            // the name sits lower than the top (headText's topMargin): counted, with room under the buttons
            height: Math.max(72, headText.anchors.topMargin + headText.implicitHeight + 10)
            Item {
                id: headIcon
                width: 64; height: 64
                anchors { left: parent.left; leftMargin: 10; top: parent.top }      // the name beside its middle (headText), the buttons below
                Image {
                    id: headImg
                    // as big as the glyph below looks (an app's picture fills its square, a glyph doesn't), so both sit
                    // the same beside the name
                    anchors { fill: parent; margins: 8 }
                    source: card.info && card.info.icon ? "file://" + card.info.icon
                          : card.pkg.iconFile ? "file://" + card.pkg.iconFile : ""
                    sourceSize: Qt.size(128, 128)
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    anchors.centerIn: parent
                    visible: headImg.status !== Image.Ready
                    text: Icons.g(card.pkg.glyph || "package")
                    color: Theme.primary
                    font { family: Icons.family; pixelSize: 44 }
                }
            }
            Column {
                id: headText
                anchors { left: headIcon.right; leftMargin: 20; right: onSwitch.visible ? onSwitch.left : parent.right; rightMargin: 20; top: parent.top
                          topMargin: Math.max(0, (headIcon.height - headName.height) / 2) }      // the name on the icon's middle
                spacing: 4
                Text {
                    id: headName
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: card.info ? card.info.name : (card.pkg.name || "")
                    color: Theme.accent
                    font { family: Theme.font; pixelSize: launcher.fontSize + 7; weight: Font.Normal }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: launcher.keySpaced(card.info && card.info.summary ? card.info.summary : (card.pkg.summary || card.pkg.sub || ""))
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: launcher.fontSize - 2; weight: launcher.fontWeight }
                }
                // Under the text, where a longer label fits: Install / Remove / Run installer again (= Enter), and a
                // plugin's Set up with Claude (= C, plugin.conf's setup)
                Row {
                    topPadding: 10
                    spacing: 10
                    CardButton {
                        id: button
                        readonly property bool installed: !card.pkg.remove && card.info !== null && card.info.installed
                        readonly property bool again: installed && !!card.pkg.rerun
                        off: installed && !again
                        glyph: off ? "check" : again ? "rotate-cw" : card.pkg.remove ? "trash-2" : "download"
                        label: off ? "Installed" : again ? "Run installer again" : card.pkg.remove ? "Remove" : "Install"
                        onClicked: card.confirm()
                    }
                    CardButton {
                        visible: card.canSetup
                        glyph: "sparkles"
                        label: "Set up with Claude"
                        onClicked: card.setup()
                    }
                }
            }
            Item {      // an installed plugin's on/off switch (= Tab), like a launcher row's
                id: onSwitch
                readonly property bool on: card.info !== null && !card.info.off
                visible: card.pkg.src === "plugin" && card.info !== null && card.info.installed
                anchors { right: parent.right; rightMargin: 6 }
                y: headText.y + headName.y + (headName.height - height) / 2      // level with the name (not a sibling: no anchor)
                width: switchRow.implicitWidth; height: 40
                Row {
                    id: switchRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: onSwitch.on ? "On" : "Off"
                        color: onSwitch.on ? Theme.text : Theme.dim
                        font { family: Theme.font; pixelSize: launcher.fontSize - 1; weight: launcher.fontWeight }
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 20; radius: 10
                        color: onSwitch.on ? Theme.accent : Theme.border
                        Rectangle {
                            width: 14; height: 14; radius: 7; y: 3
                            x: onSwitch.on ? 17 : 3
                            color: onSwitch.on ? Theme.bg : Theme.text
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.pluginToggle()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        Text {
            visible: card.info === null
            leftPadding: 10
            text: "Loading details…"
            color: Theme.dim
            font { family: Theme.font; pixelSize: launcher.fontSize - 3; weight: launcher.fontWeight }
        }

        Grid {      // facts: label on the left, value on the right; the homepage opens in the browser
            id: facts
            visible: card.info !== null
            x: 10
            width: parent.width - 20
            columns: 2
            columnSpacing: 20
            rowSpacing: 7
            readonly property int labelWidth: 120
            Repeater {
                model: card.info ? card.info.fields.reduce((a, f) => a.concat([{ label: true, t: f[0] }, { label: false, t: f[1], link: f[0] === "Homepage" }]), []) : []
                Text {
                    id: fact
                    required property var modelData
                    width: modelData.label ? facts.labelWidth : facts.width - facts.labelWidth - facts.columnSpacing
                    wrapMode: modelData.label ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                    textFormat: Text.PlainText
                    text: modelData.label ? modelData.t.toUpperCase() : modelData.t
                    color: modelData.label ? Theme.primary : modelData.link ? (linkArea.containsMouse ? Theme.accent : Theme.text) : Theme.text
                    font {
                        family: Theme.font; pixelSize: modelData.label ? launcher.fontSize - 6 : launcher.fontSize - 3
                        weight: launcher.fontWeight; letterSpacing: modelData.label ? 1 : 0; underline: !!modelData.link && linkArea.containsMouse
                    }
                    topPadding: modelData.label ? 3 : 0
                    MouseArea {
                        id: linkArea
                        enabled: !!fact.modelData.link
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { launcher.open = false; Quickshell.execDetached(["xdg-open", fact.modelData.t]) }
                    }
                }
            }
        }

        ClippingRectangle {      // screenshot (from the internet; left out until it has loaded)
            id: shotFrame
            readonly property real ratio: shotImg.implicitWidth > 0 ? shotImg.implicitHeight / shotImg.implicitWidth : 0
            visible: shotImg.status === Image.Ready
            height: visible ? Math.min(360, parent.width * ratio) : 0
            width: ratio > 0 ? Math.min(parent.width, height / ratio) : 0
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 8
            color: "transparent"
            Image {
                id: shotImg
                anchors.fill: parent
                source: card.info && card.info.screenshot ? card.info.screenshot : ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }
        }

        Column {      // description
            visible: card.info !== null && card.info.paragraphs.length > 0
            x: 10
            width: parent.width - 20
            spacing: 10
            Repeater {
                // A paragraph is a string, a README's code block, { code: [line] }, or a ## heading, { heading } (plugin-info)
                model: card.info ? card.info.paragraphs : []
                Item {
                    id: para
                    required property var modelData
                    readonly property bool isCode: typeof modelData === "object" && modelData !== null && modelData.code !== undefined
                    readonly property bool isHeading: typeof modelData === "object" && modelData !== null && modelData.heading !== undefined
                    width: parent.width
                    height: isCode ? codeBox.height : isHeading ? headText.y + headText.height : paraText.height
                    // A heading: a section title, as in the menus (MenuSection), a little apart from the text above
                    Text {
                        id: headText
                        visible: para.isHeading
                        y: 8
                        width: parent.width
                        elide: Text.ElideRight
                        text: para.isHeading ? String(para.modelData.heading).toUpperCase() : ""
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: launcher.fontSize - 5; weight: Font.Medium; letterSpacing: 1.2 }
                    }
                    Text {
                        id: paraText
                        visible: !para.isCode && !para.isHeading
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        lineHeight: 1.15
                        text: para.isCode || para.isHeading ? "" : launcher.keySpaced(String(para.modelData))
                        color: Theme.text
                        font { family: Theme.font; pixelSize: launcher.fontSize - 3; weight: launcher.fontWeight }
                    }
                    // A code block: a line each, in a box. A "command   # comment" line has the comment
                    // dimmed beside it, the comments in a column, so a command isn't wrapped in the middle;
                    // without room for both, the comment goes under its command
                    Rectangle {
                        id: codeBox
                        visible: para.isCode
                        width: parent.width
                        height: visible ? codeCol.height + 2 * pad : 0
                        radius: 8
                        color: Theme.hover
                        readonly property int pad: 10
                        readonly property var lines: para.isCode ? Array.from(para.modelData.code, l => {
                            const m = /^(.*?\S)\s{2,}(#\s.*)$/.exec(l)
                            return m ? { cmd: m[1], note: m[2] } : { cmd: String(l), note: "" }
                        }) : []
                        readonly property real gap: codeFm.advanceWidth("  ")
                        readonly property real cmdWidth: Math.max(0, ...lines.filter(l => l.note).map(l => codeFm.advanceWidth(l.cmd)))
                        // beside: the commands and at least 24 characters of comment fit side by side
                        readonly property bool beside: cmdWidth + gap + codeFm.advanceWidth("m".repeat(24)) <= codeCol.width
                        FontMetrics { id: codeFm; font: codeSample.font }
                        Text { id: codeSample; visible: false; font { family: Theme.font; pixelSize: launcher.fontSize - 4; weight: launcher.fontWeight } }
                        Column {
                            id: codeCol
                            x: codeBox.pad
                            y: codeBox.pad
                            width: codeBox.width - 2 * codeBox.pad
                            spacing: 3
                            Repeater {
                                model: codeBox.lines
                                Item {
                                    id: codeLine
                                    required property var modelData
                                    width: codeCol.width
                                    height: codeBox.beside ? Math.max(cmdText.height, noteText.height)
                                                           : cmdText.height + (noteText.visible ? noteText.height : 0)
                                    Text {
                                        id: cmdText
                                        width: codeBox.beside && codeLine.modelData.note ? codeBox.cmdWidth + 1 : parent.width
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: codeLine.modelData.cmd
                                        color: Theme.accent
                                        font: codeSample.font
                                    }
                                    Text {
                                        id: noteText
                                        visible: codeLine.modelData.note !== ""
                                        x: codeBox.beside ? codeBox.cmdWidth + codeBox.gap : codeBox.gap
                                        y: codeBox.beside ? 0 : cmdText.height
                                        width: parent.width - x
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: codeLine.modelData.note
                                        color: Theme.dim
                                        font: codeSample.font
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
