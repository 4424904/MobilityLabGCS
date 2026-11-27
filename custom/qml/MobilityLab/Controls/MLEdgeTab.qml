import QtQuick

// Pull tab on the screen edge that re-opens a folded side panel.
Rectangle {
    id: root
    property string side: "left"
    property string text
    signal clicked()

    readonly property real u: MLTheme.u
    width:  30 * u
    height: label.implicitWidth + 44 * u
    radius: 8 * u
    color:  ma.containsMouse ? MLTheme.hover : MLTheme.glassStrong
    border.color: MLTheme.glassEdge
    // flat against the screen edge
    Rectangle { width: parent.radius; height: parent.height; color: parent.color; x: root.side === "left" ? 0 : parent.width - width }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8 * u
        text: root.side === "left" ? "›" : "‹"
        color: MLTheme.accent
        font.pixelSize: 18 * u
    }
    Text {
        id: label
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 8 * u
        rotation: root.side === "left" ? 90 : -90
        text: root.text
        color: MLTheme.label
        font.family: MLTheme.sans
        font.pixelSize: MLTheme.fsSmall
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
