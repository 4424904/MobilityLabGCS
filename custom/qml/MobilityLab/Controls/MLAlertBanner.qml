import QtQuick

import QGroundControl
import QGroundControl.Controls

// Critical vehicle messages (QGC's yellow popup) as a console banner at the
// top of the map: severity stripe, source vehicle, message, [확인].
// Every message also goes to the event log. The banner folds away after a
// while on its own; the message stays in the log.
Item {
    id: root

    readonly property real u:   MLTheme.u
    property string message:    ""
    property int    vehicleId:  0
    property int    more:       0
    property bool   shown:      false
    property double _since:     0

    implicitHeight: card.height
    visible:        opacity > 0
    opacity:        shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    function push(raw) {
        var text = String(raw).replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim()
        var vid = 0
        var m = text.match(/^(?:Vehicle|기체)\s*(\d+)\s*:\s*/i)
        if (m) { vid = Number(m[1]); text = text.slice(m[0].length) }
        if (vid === 0 && QGroundControl.multiVehicleManager.activeVehicle) vid = QGroundControl.multiVehicleManager.activeVehicle.id
        if (!MLState.recentlyLogged(text, 6)) MLState.log(text, 3, vid, "FC")
        if (shown && text !== message) more++
        else if (!shown) more = 0
        message = text
        vehicleId = vid
        shown = true
        hideTimer.restart()
    }
    function acknowledge() {
        shown = false
        more = 0
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (v) v.resetErrorLevelMessages()
    }

    Timer { id: hideTimer; interval: 15000; onTriggered: root.shown = false }

    Rectangle {
        id:     card
        width:  parent.width
        height: Math.max(48 * u, msgText.implicitHeight + 26 * u)
        color:  "#F2120C0D"
        border.color: "#5A2A27"
        radius: 4 * u

        Rectangle { width: 3 * u; height: parent.height; radius: 1; color: MLTheme.warning }

        Column {
            id:                     tag
            x:                      16 * u
            anchors.verticalCenter: parent.verticalCenter
            spacing:                2 * u
            Text {
                text:           "FC ALERT"
                color:          MLTheme.warning
                font.family:    MLTheme.mono
                font.pixelSize: MLTheme.fsLabel
                font.letterSpacing: 1 * u
            }
            Text {
                text:           root.vehicleId > 0 ? "UAV " + ("0" + root.vehicleId).slice(-2) : ""
                color:          MLTheme.dim
                font.family:    MLTheme.mono
                font.pixelSize: MLTheme.fsLabel
            }
        }
        Rectangle { x: tag.x + 84 * u; y: 10 * u; width: 1; height: parent.height - 20 * u; color: "#3A2220" }

        MLText {
            id:                     msgText
            anchors.left:           parent.left
            anchors.leftMargin:     tag.x + 98 * u
            anchors.right:          moreText.visible ? moreText.left : ack.left
            anchors.rightMargin:    12 * u
            anchors.verticalCenter: parent.verticalCenter
            text:                   root.message
            color:                  MLTheme.bright
            font.pixelSize:         MLTheme.fsBody
            wrapMode:               Text.WordWrap
            maximumLineCount:       3
        }
        Text {
            id:                     moreText
            anchors.right:          ack.left
            anchors.rightMargin:    12 * u
            anchors.verticalCenter: parent.verticalCenter
            visible:                root.more > 0
            text:                   "+" + root.more
            color:                  MLTheme.caution
            font.family:            MLTheme.mono
            font.pixelSize:         MLTheme.fsSmall
        }
        Rectangle {
            id:                     ack
            anchors.right:          parent.right
            anchors.rightMargin:    10 * u
            anchors.verticalCenter: parent.verticalCenter
            width:                  56 * u
            height:                 28 * u
            radius:                 3 * u
            color:                  ackMouse.containsMouse ? "#2A1715" : "transparent"
            border.color:           "#6B3430"
            MLText { anchors.centerIn: parent; text: qsTr("확인"); font.pixelSize: MLTheme.fsSmall; color: MLTheme.text }
            MouseArea { id: ackMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.acknowledge() }
        }
    }
}
