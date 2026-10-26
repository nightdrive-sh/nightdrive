import QtQuick
import qs
import qs.kit

// What the page shows before there is a VM: what one is, in a line, and the button to make one. Deck's empty views say
// it in quiet text alone; a first VM is the one thing to do here, so it gets its button too.
Column {
    id: root
    required property QtObject c
    signal newVm()
    width: 420
    spacing: 10

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Icons.g("monitor"); font.family: Icons.familyThin; font.pixelSize: 44
        color: root.c.faint
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "No VMs yet"
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "A computer of its own in a window: try another Linux without touching yours."
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 12; lineHeight: 1.3
    }
    Item { width: 1; height: 6 }
    AppButton {
        anchors.horizontalCenter: parent.horizontalCenter
        c: root.c; glyph: "plus"; label: "New machine"; strong: true; keys: "⌘N"; tip: "From a ready-made image or an ISO"
        onClicked: root.newVm()
    }
}
