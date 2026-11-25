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
    property string tooltipText

    signal activated()

    property real   _progress:  0
    property bool   _sent:      false

    implicitWidth:  220 * MLTheme.u
    implicitHeight: 52 * MLTheme.u

    radius:         MLTheme.radius
    color:          "#1E0E0F"
    border.width:   1
    border.color:   available ? "#7A2A2A" : MLTheme.line
    opacity:        available ? 1 : 0.4
    clip:           true

    // Hold progress
    Rectangle {
        anchors.left:   parent.left
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        width:          parent.width * root._progress
        color:          "#7A2A2A"
    }

    Row {
        id:                 content
        anchors.centerIn:   parent
        spacing:            10 * MLTheme.u
        MLText {
            anchors.verticalCenter: parent.verticalCenter
            text:           root._sent ? qsTr("명령 전송됨") : (holdMouse.pressed && root.available ? qsTr("계속 누르세요") : root.text)
            color:          "#FF8A80"
            font.pixelSize: MLTheme.fsValue
            font.weight:    Font.DemiBold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:           "HOLD " + (root.holdMs / 1000) + "s"
            color:          "#B9807C"
            font.family:    MLTheme.mono
            font.pixelSize: MLTheme.fsLabel
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

    ToolTip.visible:    holdMouse.containsMouse && !holdMouse.pressed && ToolTip.text !== ""
    ToolTip.text:       root.available ? root.tooltipText + " " + qsTr("%1초간 누르면 전송됩니다.").arg(root.holdMs / 1000) : root.disabledReason
    ToolTip.delay:      400
}
