import QtQuick

// Keeps the task list where it was through a read of the files (#3249). Every change (done, edit, snooze, trash, one
// from Claude or the `tasks` command, the minute's timer) reads them again and gives the ListView a new array, and a
// ListView whose model is replaced starts again from the top: the picked row then jumped to an edge of the view (Contain),
// a moment after a tick far down. mark() notes the picked row's place on screen before the model changes, restore()
// puts the row picked after it (the same task, or the one now in its place) back there.
QtObject {
    required property ListView view
    required property var app            // the window: current

    // { row: the picked row's distance from the view's top, or null when it is out of sight; y: the scroll }
    function mark() {
        const item = view.itemAtIndex(app.current)
        const seen = item && item.y + item.height > view.contentY && item.y < view.contentY + view.height
        return { row: seen ? item.y - view.contentY : null, y: view.contentY }
    }
    // show: the picked row is brought into sight when it was out of it (a task just added or brought back by Undo)
    function restore(place, show) {
        view.forceLayout()
        if (place.row !== null) {
            // The row is made first (only those near the top exist after the reset), then the view moved under it
            view.positionViewAtIndex(app.current, ListView.Beginning)
            const item = view.itemAtIndex(app.current)
            if (item) view.contentY = item.y - place.row
        } else {
            view.contentY = place.y          // scrolled away from the picked row: the same rows stay on show
        }
        // Within the list's ends: a row gone near the end leaves less to scroll
        const top = view.originY - view.topMargin
        const end = view.originY + view.contentHeight + view.bottomMargin - view.height
        view.contentY = Math.max(top, Math.min(view.contentY, Math.max(top, end)))
        if (show) view.positionViewAtIndex(app.current, ListView.Contain)
    }
}
