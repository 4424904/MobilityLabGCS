import QtQuick

// Calm "waiting" mark: three dots that pulse in turn (vehicle / map / data not there yet).
Row {
    id: root
    property color tone: MLTheme.accent
    spacing: 8 * MLTheme.u
    Repeater {
        model: 3
        Rectangle {
            width: 8 * MLTheme.u; height: width; radius: width / 2
            color: root.tone
            opacity: 0.25
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.visible
                PauseAnimation { duration: index * 180 }
                NumberAnimation { to: 1; duration: 360 }
                NumberAnimation { to: 0.25; duration: 360 }
                PauseAnimation { duration: (2 - index) * 180 }
            }
        }
    }
}
