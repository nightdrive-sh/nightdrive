import QtQuick
import Quickshell.Io
import qs

// The editor's photo: the contact's picture (or initials); a click on it (or Return on it, Shift+Tab from the first
// name) picks a new one, and Remove under it takes it away. A picture is picked with the desktop's file picker (zenity,
// as Mail's attachments) and shown as it will be, its middle square; draft.newPhoto holds the choice (a file, "" to
// remove, null to keep the card's) and lib/edit.py makes it the card's photo on Save.
Column {
    id: root
    required property QtObject c
    property var draft: null
    property int size: 72
    spacing: 8

    // What the avatar shows: the picked picture, none once removed, else the card's own
    property string shown: ""
    onDraftChanged: shown = draft ? (draft.newPhoto !== null && draft.newPhoto !== undefined ? draft.newPhoto : draft.photo || "") : ""

    function set(picture) {
        // In place, as the fields edit the draft (the editor tells a change by the draft's text)
        root.draft.newPhoto = picture
        root.shown = picture
    }
    function pick() { if (!picker.running) picker.running = true }

    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=Choose a photo",
                  "--file-filter=Pictures | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.tif *.tiff *.JPG *.JPEG *.PNG"]
        stdout: StdioCollector { id: picked }
        // Cancelled: nothing printed, nothing changes
        onExited: { const p = picked.text.trim(); if (p) root.set(p) }
    }

    Avatar {
        id: avatar
        anchors.horizontalCenter: parent.horizontalCenter
        c: root.c; size: root.size; pixelSize: Math.round(root.size / 3)
        activeFocusOnTab: true
        border.width: activeFocus ? 2 : 0
        border.color: root.c.primary
        Keys.onPressed: e => {
            if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return
            root.pick()
            e.accepted = true
        }
        person: root.draft ? {
            initials: ((root.draft.given || "").charAt(0) + (root.draft.family || root.draft.company || "").charAt(0)).toUpperCase(),
            photo: root.shown
        } : {}
        HoverHandler { id: avatarHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.pick() }
        // Under the pointer (or with the focus) it says what a click does
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: avatarHover.hovered || avatar.activeFocus
            color: Qt.rgba(0, 0, 0, 0.6)
            Text {
                anchors.centerIn: parent
                text: Icons.g("camera"); font.family: Icons.family; font.pixelSize: 18
                color: "white"
            }
        }
    }

    Link {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.shown !== ""
        text: "Remove"
        onClicked: root.set("")
    }

    // A word to click, or to reach with Tab and press with Return or Space
    component Link: Text {
        id: link
        signal clicked()
        activeFocusOnTab: visible
        color: activeFocus ? root.c.primary : linkHover.hovered ? root.c.title : root.c.dim
        font.family: root.c.font; font.pixelSize: 11
        font.underline: activeFocus
        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: link.clicked() }
        Keys.onPressed: e => {
            if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return
            link.clicked()
            e.accepted = true
        }
    }
}
