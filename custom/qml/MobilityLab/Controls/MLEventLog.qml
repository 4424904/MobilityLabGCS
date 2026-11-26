import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 이벤트 기록: flight controller messages (STATUSTEXT), mode and arming
// changes, and every command sent from this console, newest first.
// One list for all vehicles; [경고만] keeps caution / warning rows.
Item {
    id: root

    readonly property real u:   MLTheme.u
    property bool warningsOnly: false
    readonly property bool _multi: QGroundControl.multiVehicleManager.vehicles.count > 1

    function _levelColor(level) {
        if (level === 3) return MLTheme.warning
        if (level === 2) return MLTheme.caution
        if (level === 4) return MLTheme.target
        if (level === 1) return MLTheme.active
        return MLTheme.faint
    }

    MLSection {
        id:         header
        width:      parent.width
        title:      qsTr("이벤트 기록")
        detail:     ""
    }
    Row {
        anchors.right:          parent.right
        anchors.rightMargin:    14 * u
        anchors.bottom:         header.bottom
        anchors.bottomMargin:   5 * u
        spacing:                2 * u
        Repeater {
            model: [qsTr("전체"), qsTr("경고만")]
            Rectangle {
                required property int index
                required property string modelData
                readonly property bool _on: (index === 1) === root.warningsOnly
                width:  fText.implicitWidth + 14 * u
                height: 20 * u
                radius: 3 * u
                color:  _on ? MLTheme.panelRaised : "transparent"
                border.color: _on ? MLTheme.lineStrong : "transparent"
                MLText { id: fText; anchors.centerIn: parent; text: parent.modelData; font.pixelSize: MLTheme.fsLabel; color: parent._on ? MLTheme.text : MLTheme.dim }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.warningsOnly = (parent.index === 1) }
            }
        }
    }

    ListView {
        id:                 list
        anchors.top:        header.bottom
        anchors.topMargin:  4 * u
        anchors.bottom:     parent.bottom
        width:              parent.width
        clip:               true
        model:              MLState.events
        boundsBehavior:     Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 * u }

        delegate: Item {
            required property string t
            required property string text
            required property int    level
            required property int    vid
            required property string src
            readonly property bool _shown: !root.warningsOnly || level === 2 || level === 3
            width:      list.width
            height:     _shown ? Math.max(24 * u, msg.implicitHeight + 8 * u) : 0
            visible:    _shown

            Rectangle {
                x: 20 * u; y: 7 * u
                width: 3 * u; height: 10 * u
                color: root._levelColor(parent.level)
            }
            Text {
                id:     timeText
                x:      30 * u; y: 4 * u
                text:   parent.t
                color:  MLTheme.faint
                font.family:    MLTheme.mono
                font.pixelSize: MLTheme.fsLabel
            }
            Text {
                id:         uav
                anchors.left:       timeText.right
                anchors.leftMargin: 8 * u
                y:          4 * u
                visible:    root._multi && parent.vid > 0
                text:       ("0" + parent.vid).slice(-2)
                color:      MLTheme.vehicleColor(parent.vid)
                font.family:    MLTheme.mono
                font.pixelSize: MLTheme.fsLabel
            }
            MLText {
                id:                 msg
                anchors.left:       uav.visible ? uav.right : timeText.right
                anchors.leftMargin: 8 * u
                anchors.right:      parent.right
                anchors.rightMargin: 16 * u
                y:                  3 * u
                text:               (parent.level === 4 ? "▸ " : "") + parent.text
                wrapMode:           Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount:   2
                elide:              Text.ElideRight
                font.pixelSize:     MLTheme.fsSmall
                color: parent.level === 3 ? MLTheme.warning : (parent.level === 2 ? MLTheme.caution : (parent.level === 4 ? MLTheme.target : MLTheme.label))
            }
        }

        MLText {
            anchors.centerIn:   parent
            visible:            list.count === 0
            text:               qsTr("기록 없음")
            color:              MLTheme.faint
            font.pixelSize:     MLTheme.fsSmall
        }
    }
}
