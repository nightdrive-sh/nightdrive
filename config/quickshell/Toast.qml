import QtQuick

// One toast card, shown in ToastStack below the top bar: a dark card without a border, which stands out from the bar
// and windows by itself. Osd (volume, brightness …) and DictationToast are its contents; Ask Claude (Dashboard #1895)
// will grow out of the dictation card, so a change of size while it's shown animates instead of jumping.
// It appears and goes at once, without a fade (the user's choice, #1911).
Rectangle {
    id: toast
    property bool shown: false
    property real cardWidth: 280
    property real cardHeight: 48
    // Written in (Ask Claude): ToastStack gives the keyboard to this card and closes it with a click beside it
    property bool takesKeys: false
    signal outsideClicked()
    // While it has the keys, ToastStack puts the cards this much lower (Ask Claude's, away from the bar)
    property int lowered: 0
    // Clicked, without the keyboard (Ask Claude's closed card, which opens it): only the card takes the click
    property bool clickable: false
    signal tapped()
    default property alias content: body.data

    // Column lays the cards out from the top; each one centres itself in the stack's width
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    visible: shown
    width: cardWidth
    height: cardHeight
    radius: 10
    color: Theme.bg
    clip: true

    // Only while shown: a card that appears takes its new size at once rather than growing from its last one.
    // instant: this change of size isn't animated either (Ask Claude opened from its small card)
    property bool instant: false
    Behavior on width { enabled: toast.shown && !toast.instant; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: toast.shown && !toast.instant; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // A click on the card isn't one beside it: ToastStack's catcher is under the cards
    MouseArea {
        anchors.fill: parent
        enabled: toast.takesKeys || toast.clickable
        cursorShape: toast.takesKeys ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!toast.takesKeys) toast.tapped()
    }

    Item {
        id: body
        anchors.fill: parent
    }
}
