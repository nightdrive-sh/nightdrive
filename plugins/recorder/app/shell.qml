import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Recorder, Nightdrive's window for recording from a microphone into ~/Recordings (lib/capture.py does the recording,
// as a process of its own, so it goes on with the window closed). While a recording is made the window is a low wide
// strip (RecordPane: the time, the level, the mic, Pause / Save / New); otherwise it is taller, with the recordings
// under the strip (RecordingList) and the picked one beside them (RecordingView), or in a narrow window on a page of its
// own. Record makes it the strip, Save tall again (WindowSize). This file holds the window together: the layout, the
// keys (their sheet: KeyHelp.qml) and the IPC the recorder command calls when something changed elsewhere.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Recorder"
        implicitWidth: size.tallW
        implicitHeight: size.tallH
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        Store {
            id: store
            onFailed: text => toast.show(text, { danger: true })
            onSaved: name => toast.show("Saved " + name)
        }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c

        // The strip while recording or paused, unless l showed the recordings (expanded, until the recording ends)
        property bool expanded: false
        readonly property bool strip: !store.idle && !expanded
        Connections { target: store; function onIdleChanged() { if (store.idle) win.expanded = false } }
        WindowSize { id: size; strip: win.strip }
        Component.onCompleted: if (win.strip) size.apply()

        // Wide (twoPaneMin and up): the list and the picked recording side by side. Narrow: the list, and the picked
        // one on a page of its own (⏎, a click), Esc back.
        readonly property int twoPaneMin: 720
        readonly property bool onePane: width < twoPaneMin
        property bool viewOpen: false
        onOnePaneChanged: viewOpen = false
        readonly property bool listFocused: !onePane || !viewOpen
        function open() { if (onePane && store.current) viewOpen = true }
        // The panel needs the tall window: from a paused strip, the recordings show (as l) first
        function pickMic() { if (store.recording) return; if (strip) expanded = true; mics.open() }

        IpcHandler {
            target: "recorder"
            function refresh(): void { store.refresh() }
            function pick(name: string): void { store.picked = name; store.refresh() }
        }

        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

        ColumnLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            focus: true

            Keys.onPressed: e => {
                const k = e.key
                win.look.moved(e)                  // Tab and the arrows show the keys' frame (AppPointer)
                sheet.pressed(e)
                if (e.accepted) return
                const enter = k === Qt.Key_Return || k === Qt.Key_Enter
                if (k === Qt.Key_Space) store.toggle()
                else if (enter && !store.idle) store.save()
                else if (e.text === "n") store.newOne()
                else if (e.text === "m") win.pickMic()
                else if (e.text === "l" && !store.idle) win.expanded = !win.expanded
                else if (win.strip) return         // the rest are the recordings', which the strip doesn't show
                else if (k === Qt.Key_Down || k === Qt.Key_J) store.step(1)
                else if (k === Qt.Key_Up || k === Qt.Key_K) store.step(-1)
                else if (k === Qt.Key_Home) store.pickAt(0)
                else if (k === Qt.Key_End) store.pickAt(store.recordings.length - 1)
                else if (enter) win.open()
                else if (k === Qt.Key_Escape && win.viewOpen) win.viewOpen = false
                else return
                e.accepted = true
            }

            RecordPane {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                c: win.look
                store: store
                mics: mics
                strip: win.strip
                canExpand: !store.idle
                expanded: win.expanded
                onPickMic: win.pickMic()
                onToggleList: win.expanded = !win.expanded
            }
            Rectangle { visible: !win.strip; Layout.fillWidth: true; implicitHeight: 1; color: win.look.divider }

            RowLayout {
                visible: !win.strip
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                AppPointer { c: win.look }         // the pointer hides the keys' frame

                RecordingList {
                    visible: !win.onePane || !win.viewOpen
                    Layout.preferredWidth: win.onePane ? -1 : win.width < 1000 ? 300 : 340
                    Layout.fillWidth: win.onePane
                    Layout.fillHeight: true
                    c: win.look
                    app: win
                    store: store
                }
                Rectangle { visible: !win.onePane; Layout.fillHeight: true; implicitWidth: 1; color: win.look.divider }
                RecordingView {
                    visible: !win.onePane || win.viewOpen
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    c: win.look
                    store: store
                    onePane: win.onePane
                    onBack: win.viewOpen = false
                }
            }
        }

        MicPicker {
            id: mics
            behind: content
            c: win.look
            current: store.mic
            onPicked: node => store.pickMic(node)
            onVisibleChanged: if (!visible) content.forceActiveFocus()
        }
        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
        AppToast { id: toast; c: win.look }
    }
}
