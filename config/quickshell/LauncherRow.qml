import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.kit as Kit

// One row of the launcher's list (LauncherList.qml): its icon, name and description, tags, the shortcut or a
// keybinding's keys, a switch, a form's field, the value on the right, the open-app dot and a slider, and what the mouse
// does on it. Every level's rows are drawn by this one file, from the keys a row has (kind, glyph, sub, summary …).
Rectangle {
    id: row
    property var launcher: null
    readonly property var view: ListView.view   // LauncherList: the row heights it measures with
    required property var modelData
    required property int index
    readonly property bool isHeader: modelData.kind === "header"
    readonly property bool isNote: modelData.kind === "note"
    readonly property bool isQuote: modelData.kind === "quote"
    readonly property bool current: !isHeader && !isNote && !isQuote && !row.launcher.topFocused && index === row.launcher.selIndex
    readonly property bool noIcon: modelData.kind === "key" || modelData.kind === "hint" || isHeader || isNote || isQuote
    readonly property bool armedNow: (modelData.kind === "action" && modelData.confirm === true && row.launcher.armed === modelData.name)
                                    || (modelData.armKey !== undefined && row.launcher.armed === modelData.armKey)
    readonly property bool chevron: modelData.kind === "nav" || modelData.kind === "menu" || modelData.chevron === true
    width: row.view.width
    readonly property int extraLines: subText.visible ? Math.max(0, subText.lineCount - 1) : 0
    // A taller row keeps its icon and right side at the name and the first line, not in the middle
    readonly property bool plain: modelData.subPlain === true
    readonly property int lineH: plain ? row.view.plainLineHeight : row.view.subLineHeight
    readonly property real topShift: -extraLines * lineH / 2
    height: isQuote ? row.view.quoteHeight(modelData) : isHeader || isNote ? row.view.headerHeight : row.launcher.rowHeight + extraLines * lineH
    radius: 10
    color: current ? Theme.sel : isQuote ? Theme.card : "transparent"
    Text {      // a quote's lines, in the darker box
        visible: row.isQuote
        anchors { fill: parent; margins: row.view.quotePad; leftMargin: 16; rightMargin: 16 }
        text: row.isQuote ? row.modelData.name : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        lineHeightMode: Text.FixedHeight
        lineHeight: row.view.quoteLineHeight
        color: Theme.text
        font { family: Theme.font; pixelSize: row.launcher.fontSize - 3; weight: row.launcher.fontWeight }
    }

    // Icon: app = image, root item = Lucide glyph, keybinding = no icon
    Item {
        id: slot
        visible: !row.noIcon
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        width: row.launcher.iconSize; height: row.launcher.iconSize
        LevelRing {      // row.slider (Home's lights): the brightness as a ring around the bulb
            id: brightRing
            anchors.centerIn: parent
            visible: row.modelData.slider !== undefined
            size: row.launcher.iconSize + 12
            // while dragged the rows aren't rebuilt (Home.holdBright), so the ring follows the mouse itself
            value: rowArea.sliding ? rowArea.dragV : row.modelData.slider || 0
            strength: row.current ? 1 : 0.7
        }
        AppIcon {
            anchors.fill: parent
            visible: (row.modelData.kind === "app" || row.modelData.iconFile !== undefined) && row.modelData.glyph === undefined && source !== ""
            sourceSize: Qt.size(row.launcher.iconSize * 2, row.launcher.iconSize * 2)
            name: row.modelData.iconFile !== undefined ? row.modelData.iconFile    // Install › Software
                : row.modelData.kind === "app" ? (row.modelData.icon || "") : ""
        }
        Text {
            anchors.centerIn: parent
            visible: row.modelData.emoji !== undefined
            text: row.modelData.emoji !== undefined ? row.modelData.emoji : ""
            font.pixelSize: row.launcher.iconSize - 6
        }
        Rectangle {      // Theme › Color: swatch (selected = border)
            anchors.centerIn: parent
            visible: row.modelData.swatch !== undefined
            width: 20; height: 20; radius: 10
            color: row.modelData.swatch || "transparent"
            border.width: row.modelData.summary === "current" ? 2 : 0
            border.color: Theme.accent
        }
        Text {
            anchors.centerIn: parent
            visible: row.modelData.glyph !== undefined
            text: row.modelData.glyph !== undefined ? Icons.g(row.modelData.glyph) : ""
            color: row.modelData.glyphColor !== undefined ? row.modelData.glyphColor   // Home: a light that's on is yellow
                 : row.modelData.dimmed ? Theme.dim : row.current ? Theme.accent : Theme.text
            font { family: Icons.familyLight; pixelSize: row.launcher.iconSize - 2 }
        }
    }
    Text {
        id: nameText
        // A second line: an album's artist, or the description of an Install search result (row.modelData.sub)
        readonly property bool twoLines: !!row.modelData.artist || !!row.modelData.sub
        readonly property bool subLine: !!row.modelData.sub
        anchors {
            left: row.noIcon ? parent.left : slot.right; leftMargin: 16
            right: keyFrames.visible ? keyFrames.left : shortcut.visible ? shortcut.left : trailing.left; rightMargin: (row.modelData.kind === "key" ? 24 : 12) + (dot.visible ? 19 : 0) + (badge.visible ? badge.implicitWidth + 10 : 0) + (note.visible ? note.implicitWidth + 10 : 0)   // keybindings get more room before the keys (description is elided with …)
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: twoLines ? (subLine ? (row.plain ? -row.lineH / 2 : -9) - row.extraLines * row.lineH / 2 : -7) : 0
        }
        visible: !row.isQuote
        elide: Text.ElideRight
        // liveName: a name that changes often (Status' processes), bound here instead of rebuilding the rows
        text: row.modelData.liveName !== undefined ? row.launcher.levels.liveText(row.modelData.liveName)
            : row.isHeader ? row.modelData.name.toUpperCase()
            : row.modelData.name
        color: row.armedNow ? Theme.primary : (row.isHeader ? Theme.primary : row.modelData.kind === "hint" || row.isNote || row.modelData.dimmed ? Theme.dim : (row.current ? Theme.accent : Theme.text))
        font { family: Theme.font; pixelSize: row.isHeader ? row.launcher.fontSize - 5 : row.isNote ? row.launcher.fontSize - 4 : nameText.subLine && !row.plain ? row.launcher.fontSize - 2 : row.launcher.fontSize; weight: row.isHeader ? Font.Bold : row.launcher.fontWeight; letterSpacing: row.isHeader ? 1.5 : 0 }
        topPadding: row.isHeader ? 10 : 0
    }
    Text {      // a row that asks first, asked: what a second Enter does (armHint), after the name in smaller text
        id: armTag
        visible: row.armedNow
        anchors { left: nameText.left; leftMargin: nameText.contentWidth + 12; baseline: nameText.baseline }
        width: Math.max(0, nameText.width - nameText.contentWidth - 12)
        elide: Text.ElideRight
        text: "— " + row.launcher.keySpaced(row.modelData.armHint || "Enter again to confirm")
        color: Theme.primary
        font { family: Theme.font; pixelSize: row.launcher.fontSize - 4 }
    }
    Text {      // EXPERIMENTAL after a plugin's name (Install › Plugins)
        id: expTag
        visible: !!row.modelData.experimental && !row.armedNow
        anchors { left: nameText.left; leftMargin: nameText.contentWidth + 10; baseline: nameText.baseline }
        text: "EXPERIMENTAL"
        color: Theme.caution
        font { family: Theme.font; pixelSize: row.launcher.fontSize - 7; letterSpacing: 1 }
    }
    Text {      // EXTERNAL: a plugin from elsewhere (nightdrive plugins add), not one of Nightdrive's own
        id: extTag
        visible: !!row.modelData.external && !row.armedNow
        anchors { left: nameText.left; leftMargin: nameText.contentWidth + 10 + (expTag.visible ? expTag.implicitWidth + 10 : 0); baseline: nameText.baseline }
        text: "EXTERNAL"
        color: Theme.primary
        font { family: Theme.font; pixelSize: row.launcher.fontSize - 7; letterSpacing: 1 }
    }
    Text {      // the other group's row in a Plugins or Recommended search (RECOMMENDED / PLUGINS): here, so the
                // right side keeps its installed / off like the group's own rows
        visible: row.modelData.groupTag !== undefined && !row.armedNow
        anchors { left: nameText.left; baseline: nameText.baseline
                  leftMargin: nameText.contentWidth + 10 + (expTag.visible ? expTag.implicitWidth + 10 : 0) + (extTag.visible ? extTag.implicitWidth + 10 : 0) }
        text: visible ? row.modelData.groupTag.toUpperCase() : ""
        color: Theme.primary
        font { family: Theme.font; pixelSize: row.launcher.fontSize - 7; letterSpacing: 1 }
    }
    Text {      // the description wraps (subMaxLines at most): the row grows with it
        id: subText
        visible: nameText.twoLines
        anchors { left: nameText.left; right: nameText.right; top: nameText.bottom; topMargin: nameText.subLine ? 0 : -1 }
        wrapMode: nameText.subLine ? Text.Wrap : Text.NoWrap
        maximumLineCount: row.modelData.subMax || row.view.subMaxLines
        lineHeightMode: Text.FixedHeight
        lineHeight: row.lineH
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: row.launcher.keySpaced(row.modelData.sub || (row.modelData.artist || "").toUpperCase())
        color: row.plain ? nameText.color : row.modelData.sub ? Theme.dim : Theme.primary
        font { family: Theme.font; pixelSize: row.plain ? row.launcher.fontSize : nameText.subLine ? row.launcher.fontSize - 5 : row.launcher.fontSize - 6; weight: nameText.subLine ? row.launcher.fontWeight : Font.Normal
               letterSpacing: nameText.subLine ? 0 : 1 }
    }
    Row {            // the row's shortcut (shortcutFor) as key caps like the footer's, before the › of a submenu;
        id: shortcut     // not where the right side is taken. capKeys: a row's own keys (Settings › Apps › App shortcuts)
        readonly property string keys: row.modelData.capKeys !== undefined ? row.modelData.capKeys
            : !row.launcher.prefs.shortcuts || trailing.tag || row.modelData.keys !== undefined || row.armedNow
            || (row.modelData.summary !== undefined && row.modelData.summary !== "") ? "" : row.launcher.shortcuts.shortcutFor(row.modelData)
        // On a narrow card only where the whole name still fits beside it
        visible: keys !== "" && (!row.launcher.narrow || nameText.x + nameText.implicitWidth + width + trailing.width + 60 < row.width)
        anchors { right: trailing.left; rightMargin: trailing.text !== "" ? 18 : 0; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        spacing: 4
        Repeater {
            model: shortcut.keys.split(/\s+/).filter(k => k !== "")
            Kit.Key { required property string modelData; key: modelData; dim: !row.current }
        }
    }
    Row {            // Keybindings: a key's combinations as key caps like a row's shortcut (keyParts)
        id: keyFrames
        visible: row.modelData.keys !== undefined
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        spacing: 6
        Repeater {
            // On a narrow card only the first combination ("Hyper B / ⌘ B" → "Hyper B"): the name needs the room
            model: !keyFrames.visible ? [] : row.launcher.narrow ? row.launcher.shortcuts.keyParts(row.modelData.keys).slice(0, 1) : row.launcher.shortcuts.keyParts(row.modelData.keys)
            Row {
                id: part
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: part.modelData.caps || []
                    Kit.Key { required property string modelData; key: modelData; dim: !row.current }
                }
                Text {
                    visible: part.modelData.caps === undefined
                    anchors.verticalCenter: parent.verticalCenter
                    text: visible ? part.modelData.text : ""
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: row.launcher.fontSize - 5 }
                }
            }
        }
    }
    Toggle {         // row.switchOn: an on/off switch like the top bar menus' (MenuHeader), instead of "on"/"off"
        id: rowSwitch    // row.switchBusy: still changing (rowArea above takes the clicks; activate() refuses it)
        visible: row.modelData.switchOn !== undefined
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        checked: row.modelData.switchOn === true
        busy: row.modelData.switchBusy === true
    }
    FieldBox {
        visible: row.modelData.field === true
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        height: row.launcher.rowHeight - 20
        row: row.modelData
        current: row.current
        typed: row.current ? row.launcher.query : ""
        fontSize: row.launcher.fontSize - 3
    }
    Text {
        id: trailing
        visible: row.modelData.field !== true
        anchors { right: parent.right; rightMargin: 16 + (rowSwitch.visible ? 34 + 14 : 0); verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        width: Math.min(implicitWidth, row.width * 0.42)
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        // from = submenu a root-level search hit comes from (small violet tag)
        readonly property bool tag: row.modelData.from !== undefined
        // A row whose `copy` value was just copied (⌘C or Enter: RowCopy) says so for a moment
        readonly property bool copiedNow: row.modelData.copy !== undefined && row.launcher.rowCopy.copied !== "" && row.launcher.rowCopy.copied === row.modelData.copy
        readonly property bool glyphOnly: row.modelData.trailGlyph !== undefined
            || (!tag && row.modelData.keys === undefined && !(row.modelData.summary !== undefined && row.modelData.summary !== "" && !row.armedNow) && row.chevron)
        text: copiedNow ? "copied" : row.modelData.trailGlyph !== undefined ? Icons.g(row.modelData.trailGlyph)      // Top bar › Items: ✓ / – (hidden)
            : row.modelData.live !== undefined ? row.launcher.levels.liveText(row.modelData.live)   // updates without rebuilding the rows
            : tag ? row.modelData.from.toUpperCase() : row.modelData.keys !== undefined ? ""   // keyFrames
            : (row.modelData.summary !== undefined && row.modelData.summary !== "" && !row.armedNow ? row.modelData.summary
            : (row.chevron ? Icons.g("chevron-right") : ""))
        color: copiedNow ? Theme.primary : row.modelData.trailGlyph !== undefined ? (row.modelData.dimmed ? Theme.dim : row.current ? Theme.accent : Theme.text)
             : tag ? Theme.primary : (row.modelData.keys !== undefined && row.current ? Theme.accent : Theme.dim)
        font { family: glyphOnly && !copiedNow ? Icons.familyLight : Theme.font; pixelSize: glyphOnly && !copiedNow ? row.launcher.iconSize - 6 : tag ? row.launcher.fontSize - 6 : row.modelData.kind === "album" ? row.launcher.fontSize - 5 : row.launcher.fontSize - 3
               letterSpacing: tag ? 1 : 0 }   // tags: normal weight and spacing, the same as an album's artist
    }
    Rectangle {      // green dot right after the name: the app has a window open (including one hidden to the background by ⌘W)
        id: dot
        visible: row.launcher.appState.appRunning(row.modelData)
        x: nameText.x + Math.min(nameText.contentWidth, nameText.width) + 10
        anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: row.topShift
        width: 9; height: 9; radius: 5
        color: Theme.ok
        // ⌘Q pressed: pulses until the app is gone
        readonly property bool quitting: visible && row.launcher.appState.anyQuitting && row.launcher.appState.quitPending(row.modelData)
        SequentialAnimation on opacity {
            running: dot.quitting; loops: Animation.Infinite
            onRunningChanged: if (!running) dot.opacity = 1
            NumberAnimation { to: 0.15; duration: 350; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 350; easing.type: Easing.InOutSine }
        }
    }
    Text {           // row.modelData.note: small dim text after the name (Settings › Apps › Home Assistant: how many there are)
        id: note
        visible: row.modelData.note !== undefined
        x: nameText.x + Math.min(nameText.contentWidth, nameText.width) + 10
        anchors.baseline: nameText.baseline
        text: visible ? row.modelData.note : ""
        color: Theme.dim
        opacity: 0.55   // further back than the summaries on the right: a side note
        font { family: Theme.font; pixelSize: row.launcher.fontSize - 5 }
    }
    Text {           // a small mark after the name (and the dot): row.modelData.badge, a Lucide name (Home: "pin")
        id: badge
        visible: row.modelData.badge !== undefined
        x: nameText.x + Math.min(nameText.contentWidth, nameText.width) + 10 + (dot.visible ? 19 : 0)
        anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: row.topShift
        text: visible ? Icons.g(row.modelData.badge) : ""
        color: Theme.primary   // the theme colour, like section headers: it has to stand out
        font { family: Icons.family; pixelSize: row.launcher.fontSize - 2 }
    }
    Slider {         // Settings › Display › Brightness, Sound: above the row's MouseArea, so it gets the drag
        // Sound › Headphones › Battery: a meter (no knob, not draggable), green while charging, red when low
        visible: row.modelData.kind === "brightness" || row.modelData.kind === "slider" || row.modelData.kind === "battery"
        z: 1
        // after the name ("Screen" in Display, "Brightness" in a search), lined up while the name is short
        anchors { left: slot.right; leftMargin: Math.max(120, 16 + nameText.implicitWidth + 28); right: trailing.left; rightMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.topShift }
        value: row.modelData.kind === "slider" || row.modelData.kind === "battery" ? row.modelData.value : Math.max(0, row.modelData.key === "keys" ? row.launcher.levels.disp.keys : row.launcher.levels.disp.bright)
        readOnly: row.modelData.kind === "battery"
        fillColor: row.modelData.charging ? Theme.ok : row.modelData.low ? Theme.danger : Theme.accent
        dimmed: !!row.modelData.dimmed
        trackColor: Qt.rgba(1, 1, 1, 0.1)   // the same on and off the selected row (Theme.border nearly matches Theme.sel)
        onMoved: v => { row.launcher.select(row.index); row.modelData.kind === "slider" ? row.launcher.levels.sound.setSlider(row.modelData.key, v) : row.launcher.levels.disp.setBright(v, row.modelData.key) }
    }
    MouseArea {
        id: rowArea
        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        hoverEnabled: true
        enabled: !row.isHeader && !row.isNote
        // row.slider (Home's lights): a sideways drag sets the brightness, a click still turns it on/off
        property real pressX: -1
        property bool sliding: false
        property real dragV: 0
        onPressed: mouse => { pressX = mouse.x; sliding = false }
        onPositionChanged: mouse => {
            if (pressed && row.modelData.slider !== undefined && (sliding || Math.abs(mouse.x - pressX) > 8)) {
                if (!sliding) { sliding = true; row.launcher.select(row.index); Home.holdBright(true) }
                // the drag spans from the name to the right edge (the ring shows it)
                dragV = Math.max(0, Math.min(1, (mouse.x - nameText.x) / (row.width - 16 - nameText.x)))
                row.launcher.levels.home.slide(row.modelData, dragV)
                return
            }
            row.launcher.hover(rowArea, mouse, row.index)
        }
        onReleased: if (sliding) Home.holdBright(false)
        onCanceled: if (sliding) { sliding = false; Home.holdBright(false) }
        onClicked: { if (sliding) { sliding = false; return } row.launcher.activate(row.modelData) }
    }
}
