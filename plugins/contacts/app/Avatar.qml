import QtQuick
import Quickshell.Widgets

// A contact's picture in a circle, or the initials of the name when there is none (or it doesn't load)
Rectangle {
    id: av
    required property QtObject c
    property var person: ({})
    property int size: 30
    property int pixelSize: Math.round(size * 0.38)
    width: size; height: size; radius: size / 2
    color: Qt.rgba(c.primary.r, c.primary.g, c.primary.b, 0.18)
    Text {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        text: av.person.initials || ""
        color: av.c.title; font.family: av.c.font; font.pixelSize: av.pixelSize; font.weight: Font.Medium
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: av.radius
        color: "transparent"
        visible: img.status === Image.Ready
        Image {
            id: img
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(av.size * 2, av.size * 2)
            source: !av.person.photo ? "" : av.person.photo.startsWith("/") ? "file://" + av.person.photo : av.person.photo
        }
    }
}
