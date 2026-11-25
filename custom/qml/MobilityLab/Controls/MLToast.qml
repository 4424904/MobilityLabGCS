import QtQuick

import QGroundControl
import QGroundControl.Controls

// Short non-blocking notice that fades out by itself (no OK button).
Rectangle {
    id: root

    property color tone: MLTheme.accent

    function show(message, color) {
        label.text = message
        root.tone = color !== undefined ? color : MLTheme.accent
        fade.stop()
        root.opacity = 1
        root.visible = true
        hideTimer.restart()
    }

    visible:        false
    width:          label.implicitWidth + ScreenTools.defaultFontPixelWidth * 4
    height:         label.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.9
    radius:         height / 2
    color:          "#e60e151c"
    border.width:   1.5
    border.color:   tone

    Rectangle {
        anchors.left:           parent.left
        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 1.2
        anchors.verticalCenter: parent.verticalCenter
        width:                  ScreenTools.defaultFontPixelHeight * 0.5
        height:                 width
        radius:                 width / 2
        color:                  root.tone
    }
    QGCLabel {
        id:                 label
        anchors.centerIn:   parent
        anchors.horizontalCenterOffset: ScreenTools.defaultFontPixelWidth * 0.6
        color:              MLTheme.text
        font.bold:          true
    }
    MouseArea {
        anchors.fill:   parent
        onClicked:      { hideTimer.stop(); fade.start() }
    }

    Timer {
        id:             hideTimer
        interval:       4000
        onTriggered:    fade.start()
    }
    SequentialAnimation {
        id: fade
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 400 }
        ScriptAction    { script: root.visible = false }
    }
}
