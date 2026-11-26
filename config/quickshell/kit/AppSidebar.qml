import QtQuick
import QtQuick.Layouts

// The sidebar on the window's left: the app's name (AppTitle) centred in the header's height, what it holds (AppNavRow
// rows, typically) in a column from contentTop down, and a line on its right. Put it first in the window's RowLayout and
// give it a Layout.preferredWidth. The title's line takes a few small things at its right (titleItems: a spinner, a
// badge, a button that shows only while the pointer is on the line, titleHovered); AppAccountBar goes at the foot.
Rectangle {
    id: root
    required property QtObject c
    property string title
    property int headerHeight: 62       // as high as the view's header beside it, so the two titles line up
    property int contentTop: headerHeight + 13
    property int bottomMargin: 18
    // A line under the header, level with the one under the view's header beside it: for a sidebar whose header line holds
    // a search (Notes' list), so the line runs on across the window under it
    property bool headerLine: false
    property alias spacing: column.spacing
    default property alias content: column.data
    property alias titleItems: titleRow.data
    readonly property alias titleHovered: titleHover.hovered
    Layout.fillHeight: true
    color: "transparent"
    // Without a title (a second sidebar beside the first, as Notes' list), none: its first item can take the line
    AppTitle { visible: root.title !== ""; x: 28; y: (root.headerHeight - height) / 2; c: root.c; text: root.title }
    // Over the title, the line's full width so the hover covers it all; above the column (z), so a card one of the
    // items opens under it (Mail's "Not sent") lies over the rows
    Item {
        width: parent.width; height: root.headerHeight
        z: 2
        HoverHandler { id: titleHover }
        Row {
            id: titleRow
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
        }
    }
    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.topMargin: root.contentTop
        anchors.bottomMargin: root.bottomMargin
        spacing: 2
    }
    Rectangle { visible: root.headerLine; y: root.headerHeight - 1; width: parent.width; height: 1; color: root.c.divider }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.c.divider }
}
