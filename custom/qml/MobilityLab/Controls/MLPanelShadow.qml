import QtQuick

// Soft shadow under a floating panel (three stacked rounded rects).
Item {
    id: root
    property Item target
    readonly property real u: MLTheme.u
    visible: !!target && target.visible
    x: target ? target.x : 0
    y: target ? target.y : 0
    width: target ? target.width : 0
    height: target ? target.height : 0

    Repeater {
        model: 3
        Rectangle {
            required property int index
            readonly property real g: (index + 1) * 4 * root.u
            x: -g / 2; y: -g / 2 + 4 * root.u
            width: root.width + g; height: root.height + g
            radius: MLTheme.panelRadius + g / 2
            color: "#000000"
            opacity: 0.16 - index * 0.04
        }
    }
}
