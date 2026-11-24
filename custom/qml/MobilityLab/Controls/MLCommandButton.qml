import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Large labelled command button for the bottom bar.
// tone: "normal" | "go" | "caution" | "active" (magenta, RTL)
Rectangle {
    id: root

    property string text
    property string subText
    property string iconSource
    property string tone:           "normal"
    property string disabledReason
    property bool   available:      true   // not `enabled`, so the tooltip still works when unavailable

    signal clicked()

    readonly property color _toneColor: tone === "go" ? MLTheme.ok
                                       : tone === "caution" ? MLTheme.caution
                                       : tone === "active" ? MLTheme.active
                                       : MLTheme.accent
    readonly property bool _hover: mouse.containsMouse && available

    implicitWidth:  Math.max(ScreenTools.defaultFontPixelWidth * 11, content.implicitWidth + ScreenTools.defaultFontPixelWidth * 2.4)
    implicitHeight: ScreenTools.defaultFontPixelHeight * 3.2

    radius:         ScreenTools.defaultFontPixelWidth * 0.5
    color:          mouse.pressed && available ? Qt.darker(_toneColor, 2.6) : (_hover ? "#24343a" : "#1a2328")
    border.width:   Math.max(1, ScreenTools.defaultFontPixelWidth * 0.15)
    border.color:   available ? (_hover ? _toneColor : Qt.darker(_toneColor, 1.6)) : MLTheme.line
    opacity:        available ? 1 : 0.38

    Row {
        id:                 content
        anchors.centerIn:   parent
        spacing:            ScreenTools.defaultFontPixelWidth * 0.8

        QGCColoredImage {
            anchors.verticalCenter: parent.verticalCenter
            visible:        root.iconSource !== ""
            width:          ScreenTools.defaultFontPixelHeight * 1.5
            height:         width
            source:         root.iconSource
            color:          root.available ? root._toneColor : MLTheme.dim
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            QGCLabel {
                text:           root.text
                color:          MLTheme.text
                font.pointSize: ScreenTools.defaultFontPointSize
                font.bold:      true
            }
            QGCLabel {
                visible:        root.subText !== ""
                text:           root.subText
                color:          MLTheme.dim
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }
    }

    MouseArea {
        id:             mouse
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked:      if (root.available) root.clicked()
    }

    ToolTip.visible:    mouse.containsMouse && !root.available && root.disabledReason !== ""
    ToolTip.text:       root.disabledReason
    ToolTip.delay:      400
}
