import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Press-and-hold button for irreversible commands (engine kill).
// The fill runs left to right while held; releasing early cancels.
Rectangle {
    id: root

    property string text
    property string subText
    property string iconSource
    property int    holdMs:     2000
    property bool   available:  true
    property string disabledReason

    signal activated()

    property real   _progress:  0
    property bool   _sent:      false

    implicitWidth:  Math.max(ScreenTools.defaultFontPixelWidth * 17, content.implicitWidth + ScreenTools.defaultFontPixelWidth * 2.4)
    implicitHeight: ScreenTools.defaultFontPixelHeight * 3.2

    radius:         ScreenTools.defaultFontPixelWidth * 0.5
    color:          "#2a0d10"
    border.width:   Math.max(2, ScreenTools.defaultFontPixelWidth * 0.25)
    border.color:   available ? MLTheme.warning : MLTheme.line
    opacity:        available ? 1 : 0.38
    clip:           true

    // Hazard stripes
    Item {
        anchors.fill:   parent
        opacity:        0.18
        clip:           true
        Repeater {
            model: Math.ceil(root.width / (ScreenTools.defaultFontPixelWidth * 2)) + 4
            Rectangle {
                width:      ScreenTools.defaultFontPixelWidth
                height:     root.height * 2
                x:          index * ScreenTools.defaultFontPixelWidth * 2 - root.height
                y:          -root.height / 2
                rotation:   35
                color:      MLTheme.warning
            }
        }
    }

    // Hold progress
    Rectangle {
        anchors.left:   parent.left
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        width:          parent.width * root._progress
        color:          MLTheme.warning
        opacity:        0.85
    }

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
            color:          "white"
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            QGCLabel {
                text:           root._sent ? qsTr("명령 전송됨") : root.text
                color:          "white"
                font.pointSize: ScreenTools.defaultFontPointSize
                font.bold:      true
            }
            QGCLabel {
                text:           root._sent ? qsTr("기체 응답은 메시지 창 확인") : (holdMouse.pressed && root.available ? qsTr("계속 누르고 있으세요") : root.subText)
                color:          "#ffc9c9"
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }
    }

    NumberAnimation {
        id:         holdAnim
        target:     root
        property:   "_progress"
        from:       0
        to:         1
        duration:   root.holdMs
        onFinished: {
            if (root._progress >= 1) {
                root._sent = true
                root.activated()
                sentTimer.restart()
            }
        }
    }

    NumberAnimation {
        id:         releaseAnim
        target:     root
        property:   "_progress"
        to:         0
        duration:   180
    }

    Timer {
        id:         sentTimer
        interval:   2500
        onTriggered: {
            root._sent = false
            releaseAnim.start()
        }
    }

    MouseArea {
        id:             holdMouse
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: {
            if (root.available && !root._sent) {
                releaseAnim.stop()
                holdAnim.start()
            }
        }
        onReleased: {
            if (holdAnim.running) {
                holdAnim.stop()
                releaseAnim.start()
            }
        }
        onCanceled: {
            if (holdAnim.running) {
                holdAnim.stop()
                releaseAnim.start()
            }
        }
    }

    ToolTip.visible:    holdMouse.containsMouse && !holdMouse.pressed
    ToolTip.text:       root.available ? qsTr("엔진을 즉시 정지합니다 (MAV_CMD_DO_ENGINE_CONTROL). %1초간 누르면 전송됩니다.").arg(root.holdMs / 1000) : root.disabledReason
    ToolTip.delay:      400
}
