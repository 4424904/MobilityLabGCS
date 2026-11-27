import QtQuick

// Finish for a floating panel: glass sheen at the top, a lit top edge,
// accent corner ticks. Put it as the last child of the panel (it ignores input).
Item {
    id: root
    anchors.fill:   parent
    z:              100
    enabled:        false

    property color accent:  MLTheme.accent
    property real  radius:  MLTheme.panelRadius
    readonly property real u: MLTheme.u

    // sheen
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 1
        height: Math.min(parent.height, 90 * root.u)
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0FFFFFFF" }
            GradientStop { position: 1.0; color: "#00FFFFFF" }
        }
    }
    // lit top edge
    Rectangle {
        anchors.top: parent.top
        x: root.radius; width: parent.width - root.radius * 2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.18; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) }
            GradientStop { position: 0.6;  color: String(MLTheme.alpha(MLTheme.accent, 0.1)) }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }
    // corner ticks
    Rectangle { x: 6 * root.u; y: 6 * root.u; width: 12 * root.u; height: 1.5 * root.u; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.8) }
    Rectangle { x: 6 * root.u; y: 6 * root.u; width: 1.5 * root.u; height: 12 * root.u; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.8) }
    Rectangle { x: parent.width - 18 * root.u; y: parent.height - 7.5 * root.u; width: 12 * root.u; height: 1.5 * root.u; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) }
    Rectangle { x: parent.width - 7.5 * root.u; y: parent.height - 18 * root.u; width: 1.5 * root.u; height: 12 * root.u; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) }
}
