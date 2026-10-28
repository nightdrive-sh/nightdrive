import QtQuick

// One module in the top bar: an icon and/or a text in a rounded box (the box lights up while its menu is open).
// The icon is an SVG in a size × size square (adjust.conf) centred by its box, and the text is centred by its digits.
// Positions are snapped to whole device pixels.
Item {
    id: mod
    required property var def             // the module's entry in modules.jsonc
    property bool open: false               // its menu is open
    property bool hasMenu: false
    property real dpr: 1
    signal leftClicked(real centerX)
    signal dragOver(real centerX)           // files dragged over a module with "drop": its menu opens (Bar.qml)
    property real cmdAt: 0                  // when ⌘ was last pressed with the left button (Bar.qml)
    signal moveStarted(real pointerX)       // ⌘+drag moves the module (Bar.qml); x in the window
    signal moveTo(real pointerX)
    signal moveEnded()

    readonly property string name: def.name
    readonly property var st: TopBar.states[name] || null
    readonly property string icon: st && st.icon ? st.icon : ""
    // Several icons separated by | are an animation (wifi while connecting): one frame after another, and the module
    // asks for its state every second meanwhile, so the animation ends soon after
    readonly property var frames: icon.split("|")
    property int frame: 0
    readonly property string shownIcon: frames[frame % frames.length]
    Timer { running: mod.frames.length > 1; interval: 350; repeat: true; onTriggered: mod.frame++ }
    Timer { running: mod.frames.length > 1 || mod.pulsing; interval: 1000; repeat: true; onTriggered: TopBar.refresh(mod.name) }
    readonly property string label: st && st.text ? st.text : ""
    readonly property string cls: st && st.class ? st.class : ""
    // "pulse" is active whose icon fades in and out, smoothly (a VM booting in Garage): asked for every second meanwhile too
    readonly property bool pulsing: cls === "pulse"
    readonly property bool active: cls === "active" || pulsing
    property real pulse: 1
    SequentialAnimation on pulse {
        running: mod.pulsing
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) mod.pulse = 1
    }
    // present: it has something to show; tucked: it didn't fit and is in the "…" menu instead (Bar.qml lays out by
    // present, so tucking it away doesn't change the layout it came from)
    readonly property bool present: icon !== "" || label !== ""
    property bool tucked: false
    visible: present && !tucked

    readonly property bool isMic: name === "microphone" && icon !== ""
    MicLevel { id: micLevel; active: mod.isMic; steps: Math.round(mod.isz.size * mod.dpr) }

    readonly property var isz: TopBar.size(name)
    readonly property int pad: 8
    readonly property int gap: 5
    readonly property color fg: open || active ? TopBar.c("hlFg")
                              : cls === "off" ? TopBar.c("off")
                              : cls === "warning" ? Theme.warning
                              : cls === "critical" ? Theme.danger
                              : TopBar.c("fg")
    function snap(v) { return Math.round(v * dpr) / dpr }

    height: 27
    width: present ? Math.max(icon && !label ? 34 : 0, pad + (icon ? isz.size : 0) + (icon && label ? gap : 0) + (label ? txt.implicitWidth : 0) + pad) : 0

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: mod.open || ma.moving ? TopBar.c("hlBg") : mod.active ? TopBar.c("actBg") : "transparent"
    }

    Item {
        anchors.fill: parent
        opacity: mod.cls === "stale" ? 0.6 : 1

        Image {
            id: img
            visible: mod.icon !== ""
            width: mod.isz.size; height: mod.isz.size
            x: mod.snap(mod.label ? mod.pad : (mod.width - width) / 2)
            y: mod.snap((mod.height - height) / 2)
            sourceSize: Qt.size(Math.ceil(width * mod.dpr), Math.ceil(height * mod.dpr))
            source: TopBar.iconUrl(mod.shownIcon, mod.fg)
            opacity: mod.fg.a * mod.pulse * (mod.isMic ? 0.45 : 1)   // the microphone's level fills it at full colour
            smooth: true
            cache: false
        }

        // Microphone in use: the icon fills up from the bottom with the input level (MicLevel), as in macOS's Control Centre
        Item {
            visible: mod.isMic
            clip: true
            x: img.x; width: img.width
            height: mod.snap(img.height * micLevel.level)
            y: img.y + img.height - height
            Image {
                y: parent.height - height
                width: img.width; height: img.height
                sourceSize: img.sourceSize
                source: mod.isMic ? img.source : ""
                opacity: mod.fg.a
                smooth: true
                cache: false
            }
        }

        // A red dot on the icon: the status asks for it ("dot": true), or for Claude while a session that finished in the
        // background waits for you (Claude.qml)
        Rectangle {
            visible: mod.icon !== "" && (!!(mod.st && mod.st.dot) || (mod.name === "claude" && Claude.wanting > 0))
            width: 7; height: 7; radius: 3.5
            x: mod.snap(img.x + img.width - 7); y: mod.snap(img.y + 1)
            color: Theme.danger   // red like a critical module (the Dashboard's tasks); no ring around it: the bar's background can be see-through
        }

        BarText {
            id: txt
            visible: mod.label !== ""
            text: mod.label
            color: mod.fg
            dpr: mod.dpr
            font.letterSpacing: mod.def.spacing || 0   // modules.jsonc "spacing"
            x: mod.snap(mod.icon ? img.x + img.width + mod.gap : (mod.width - implicitWidth) / 2)
        }
    }

    // modules.jsonc "drop": files dropped on the icon go to its command and its menu opens (Ferry's says "Sent"); lingering
    // over it opens the menu too, as the shelf opens under a drag (Shelf.qml)
    DropArea {
        id: drop
        anchors.fill: parent
        enabled: !!mod.def.drop
        keys: ["text/uri-list"]
        onEntered: drag => { drag.accepted = true; dragOpen.restart() }
        onExited: dragOpen.stop()
        onDropped: d => {
            dragOpen.stop()
            const paths = Array.from(d.urls, u => u.toString()).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)))
            if (!paths.length) return
            TopBar.run(mod.def.drop, mod.name, paths)
            d.acceptProposedAction()
            mod.dragOver(mod.mapToItem(null, mod.width / 2, 0).x)
        }
    }
    Timer { id: dragOpen; interval: 300; onTriggered: if (drop.containsDrag) mod.dragOver(mod.mapToItem(null, mod.width / 2, 0).x) }
    Rectangle {   // the icon takes the drop: a ring while files are over it
        anchors.fill: parent
        radius: 8
        visible: drop.containsDrag
        color: "transparent"
        border { width: 1.5; color: TopBar.c("hlFg") }
    }

    // ⌘+drag moves the module. ⌘ comes from Hyprland just before or after the press, so the move starts on the first
    // drag, when both are in; a ⌘-click opens nothing.
    MouseArea {
        id: ma
        property real pressX: 0
        property real pressAt: 0
        property bool moving: false
        readonly property bool cmd: Math.abs(mod.cmdAt - pressAt) < 500
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: moving ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => { pressX = mouse.x; pressAt = Date.now() }
        onPositionChanged: mouse => {
            if (!moving && (pressedButtons & Qt.LeftButton) && cmd && Math.abs(mouse.x - pressX) > 3) {
                moving = true
                mod.moveStarted(mapToItem(null, pressX, 0).x)   // the module hasn't moved yet
            }
            if (moving) mod.moveTo(mapToItem(null, mouse.x, 0).x)
        }
        onReleased: if (moving) { moving = false; mod.moveEnded() }
        onCanceled: if (moving) { moving = false; mod.moveEnded() }
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) { if (mod.hasMenu && !cmd) mod.leftClicked(mod.mapToItem(null, mod.width / 2, 0).x) }
            else if (mouse.button === Qt.RightButton && mod.def.right) TopBar.run(mod.def.right, mod.name)
            else if (mouse.button === Qt.MiddleButton && mod.def.middle) TopBar.run(mod.def.middle, mod.name)
        }
    }
}
