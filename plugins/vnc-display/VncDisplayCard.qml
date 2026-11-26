import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// VNC Display's connect card (Settings › Other displays › a device › Show QR code, VncDisplayLevels.qml): in the middle of the
// screen, over everything, as Ferry's Add Device. The QR code is a vnc:// link with the address (`vnc-display qr`),
// which the device's camera opens in its VNC app; the user name and password are beside it, to type into the app once. Only while asked for: the launcher closes for it, and Esc, × or a click outside closes it and removes the
// QR code's file.
PanelWindow {
    id: c
    property var info: null                   // the device's show --json
    property string qr: ""                    // the QR code's SVG once made
    property string fail: ""                  // why there isn't one
    property string copied: ""                // the value just copied: its line says so for a moment
    readonly property string cmdPath: Qt.resolvedUrl("bin/vnc-display").toString().replace(/^file:\/\//, "")

    function show(i) { info = i; qr = ""; fail = ""; qrProc.command = [cmdPath, "qr", i.name]; qrProc.running = true; visible = true }
    function close() {
        visible = false
        if (qr !== "") Quickshell.execDetached(["rm", "-f", qr])
        qr = ""; info = null; copied = ""
    }
    // A click on a value, or ⌘C for the password (Hyprland sends Ctrl+Insert). The password past the clipboard history
    // and cleared after 45 s, as the launcher's password row (RowCopy.copyText)
    function copy(v, sensitive) {
        if (sensitive) clipper.createObject(c, { input: v })
        else Quickshell.execDetached(["wl-copy", v])
        copied = v
        copiedTimer.restart()
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: c.copied = "" }

    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0, 0, 0, 0.6)   // the dim behind, as Ferry's card
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    onVisibleChanged: if (visible) keys.forceActiveFocus()
    MouseArea { anchors.fill: parent; onClicked: c.close() }
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: c.close()
        Keys.onReturnPressed: c.close()
        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_C || event.key === Qt.Key_Insert) && c.info) {
                c.copy(c.info.password, true); event.accepted = true
            }
        }
    }

    // The password on the shell's stdin, kept in its variable, not in its arguments: a command line is readable by every
    // user in /proc/PID/cmdline, for the 45 s it waits (#1926). printf and [ are builtins, so it's in no other's either.
    // One per copy, gone once it has cleared (or found the clipboard changed)
    Component {
        id: clipper
        Process {
            property string input
            running: true
            stdinEnabled: true
            command: ["bash", "-c", 'IFS= read -r -d "" p; printf %s "$p" | wl-copy --sensitive; sleep 45; [ "$(wl-paste -n 2>/dev/null)" = "$p" ] && wl-copy --clear']
            onStarted: { write(input); input = ""; stdinEnabled = false }   // the end of stdin ends the read
            onExited: destroy()
        }
    }

    Sh {
        id: qrProc
        onResult: text => {
            const t = text.trim()
            if (t.startsWith("/")) c.qr = t; else c.fail = t.replace(/^vnc-display: /, "") || "No QR code: is qrencode installed?"
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 760
        height: Math.max(qrBox.height, steps.height) + 56
        radius: 18
        color: Theme.bg
        border { width: 1; color: Theme.border }
        MouseArea { anchors.fill: parent }   // a click on the card doesn't close it
        // Dark modules on white: a phone's camera reads it from the screen
        Rectangle {
            id: qrBox
            x: 28; y: 28
            width: 240; height: 240; radius: 14
            color: "white"
            Image {
                anchors { fill: parent; margins: 14 }
                source: c.qr !== "" ? "file://" + c.qr : ""
                sourceSize: Qt.size(424, 424)
                smooth: false
                cache: false
            }
            Text {
                anchors { fill: parent; margins: 20 }
                visible: c.qr === ""
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: c.fail !== "" ? c.fail : "…"
                color: Theme.bg   // dark on the white box
                font { family: Theme.font; pixelSize: 13 }
            }
        }
        // Bigger text than a menu's: it's read from across the desk, device in hand
        Column {
            id: steps
            anchors { left: qrBox.right; leftMargin: 28; right: parent.right; rightMargin: 28; top: qrBox.top }
            spacing: 14
            Text {
                text: "CONNECT " + (c.info ? c.info.name.toUpperCase() : "")
                color: Theme.primary
                font { family: Theme.font; pixelSize: 15; weight: Font.Medium; letterSpacing: 1.2 }
            }
            Repeater {
                model: ["Scan the code with the device's camera, and open it in the VNC app",
                        "Or add the connection by hand with the address below",
                        "Type the user and password when it asks, and let it remember them (a click copies them, ⌘C the password)"]
                delegate: Row {
                    required property string modelData
                    required property int index
                    width: parent.width
                    spacing: 12
                    Text {
                        text: index + 1
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: 15; weight: Font.Medium }
                    }
                    Text {
                        width: parent.width - 24
                        wrapMode: Text.Wrap
                        text: modelData
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 15 }
                    }
                }
            }
            Item { width: 1; height: 2 }
            Repeater {
                model: !c.info ? [] : [["Address", c.info.tailscale + ":" + c.info.port],
                                       ["User", c.info.username], ["Password", c.info.password]]
                // A click copies the value: a copy icon on hover, "copied" for a moment after
                delegate: Row {
                    id: line
                    required property var modelData
                    readonly property bool secret: modelData[0] === "Password"
                    spacing: 16
                    Text {
                        width: 100
                        text: line.modelData[0]
                        color: Theme.dim
                        font { family: Theme.font; pixelSize: 15 }
                    }
                    Text {
                        id: value
                        text: line.modelData[1]
                        color: valueArea.containsMouse ? Theme.primary : Theme.accent
                        font { family: Theme.font; pixelSize: 20; weight: Font.Medium; letterSpacing: line.secret ? 2 : 0 }
                        MouseArea {
                            id: valueArea
                            anchors { fill: parent; margins: -6 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: c.copy(line.modelData[1], line.secret)
                        }
                    }
                    Text {
                        anchors.baseline: value.baseline
                        visible: c.copied === line.modelData[1] || valueArea.containsMouse
                        text: c.copied === line.modelData[1] ? "copied" : Icons.g("copy")
                        color: c.copied === line.modelData[1] ? Theme.primary : Theme.dim
                        font { family: c.copied === line.modelData[1] ? Theme.font : Icons.family; pixelSize: 15 }
                    }
                }
            }
        }
        Text {
            anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 18 }
            text: Icons.g("x")
            color: closeArea.containsMouse ? Theme.accent : Theme.dim
            font { family: Icons.family; pixelSize: 16 }
            MouseArea {
                id: closeArea
                anchors { fill: parent; margins: -8 }
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: c.close()
            }
        }
    }
}
