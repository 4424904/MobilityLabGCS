// MobilityLab GCS: QGC's guided-action confirm (top bar centre), restyled.
// Same API as upstream GuidedActionConfirm.qml; the slider button is replaced
// by a press-and-hold button that fills while held (0.8 s).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

import MobilityLab.Controls

Item {
    id:         control
    width:      mainLayout.width
    visible:    false

    property var    guidedController
    property var    guidedValueSlider
    property var    messageDisplay
    property string title
    property string message
    property int    action
    property var    actionData
    property bool   hideTrigger:        false
    property var    mapIndicator
    property alias  optionText:         optionCheckBox.text
    property alias  optionChecked:      optionCheckBox.checked

    readonly property real u:       MLTheme.u
    property bool _emergencyAction: action === guidedController.actionEmergencyStop
    readonly property color _tone:  _emergencyAction ? MLTheme.warning : MLTheme.caution

    Component.onCompleted: guidedController.confirmDialog = this

    onHideTriggerChanged: {
        if (hideTrigger) {
            confirmCancelled()
        }
    }

    function show(immediate) {
        if (immediate) {
            _reallyShow()
        } else {
            visibleTimer.restart()
        }
    }

    function reset() {
        visible = false
        guidedValueSlider.visible = false
        hideTrigger = false
        visibleTimer.stop()
        holdAnim.stop()
        holdFill.progress = 0
        messageDisplay.opacity = 1.0
        messageFadeTimer.stop()
        messageOpacityAnimation.stop()
    }

    function confirmCancelled(incomingIndicator) {
        reset()
        if (mapIndicator && mapIndicator !== incomingIndicator) {
            mapIndicator.actionCancelled()
        }
        mapIndicator = undefined
    }

    function _reallyShow() {
        visible = true
        messageDisplay.opacity = 1.0
        messageFadeTimer.start()
    }

    function _activate() {
        control.visible = false
        var sliderOutputValue = 0
        if (guidedValueSlider.visible) {
            sliderOutputValue = guidedValueSlider.getOutputValue()
            guidedValueSlider.visible = false
        }
        hideTrigger = false
        MLState.command(control.title)
        // pilot / operator authority first: a command to a vehicle the ACACT guard is flying hands it back
        // to the operator at once (the guard then leaves it alone until its mission is resumed)
        var av = QGroundControl.multiVehicleManager.activeVehicle
        if (av && typeof mlGuard !== "undefined" && mlGuard.running && mlGuard.owns(av.id)) {
            mlGuard.operatorCommand(av.id, control.title)
        }
        let success = guidedController.executeAction(control.action, control.actionData, sliderOutputValue, control.optionChecked)
        if (mapIndicator) {
            if (success) {
                mapIndicator.actionConfirmed()
            } else {
                mapIndicator.actionCancelled()
            }
            mapIndicator = undefined
        }
    }

    Timer {
        id:             visibleTimer
        interval:       1000
        repeat:         false
        onTriggered:    _reallyShow()
    }

    QGCPalette { id: qgcPal }

    RowLayout {
        id:                     mainLayout
        anchors.verticalCenter: parent.verticalCenter
        height:                 parent.height - 14 * u
        spacing:                10 * u

        Column {
            Layout.alignment:   Qt.AlignVCenter
            spacing:            1 * u
            Text {
                text:           qsTr("확인 필요")
                color:          control._tone
                font.family:    MLTheme.sans
                font.pixelSize: MLTheme.fsLabel
                font.letterSpacing: 0.8 * u
            }
            Text {
                text:           qsTr("길게 눌러 실행")
                color:          MLTheme.dim
                font.family:    MLTheme.sans
                font.pixelSize: MLTheme.fsLabel
            }
        }

        // press-and-hold button
        Rectangle {
            id:                     holdButton
            objectName:             "guidedActionConfirm_button"
            Layout.preferredWidth:  Math.max(150 * u, titleText.implicitWidth + 40 * u)
            Layout.fillHeight:      true
            radius:                 4 * u
            color:                  "#12100B"
            border.color:           holdMouse.containsMouse ? control._tone : Qt.darker(control._tone, 1.8)
            clip:                   true

            Rectangle {
                id:     holdFill
                property real progress: 0
                width:  parent.width * progress
                height: parent.height
                color:  Qt.rgba(control._tone.r, control._tone.g, control._tone.b, 0.28)
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width * holdFill.progress; height: 2 * u; color: control._tone }
            MLText {
                id:                 titleText
                anchors.centerIn:   parent
                text:               control.title
                color:              MLTheme.bright
                font.pixelSize:     MLTheme.fsBody
                font.weight:        Font.DemiBold
            }
            NumberAnimation {
                id:         holdAnim
                target:     holdFill
                property:   "progress"
                to:         1
                duration:   800 * (1 - holdFill.progress)
                onFinished: if (holdFill.progress >= 1) { holdFill.progress = 0; control._activate() }
            }
            MouseArea {
                id:             holdMouse
                anchors.fill:   parent
                hoverEnabled:   true
                cursorShape:    Qt.PointingHandCursor
                onPressed:      holdAnim.restart()
                onReleased:     { if (holdFill.progress < 1) { holdAnim.stop(); holdFill.progress = 0 } }
                onCanceled:     { holdAnim.stop(); holdFill.progress = 0 }
            }
        }

        QGCCheckBox {
            id:                 optionCheckBox
            visible:            text !== ""
        }

        Rectangle {
            Layout.preferredWidth:  28 * u
            Layout.preferredHeight: 28 * u
            radius:                 3 * u
            color:                  closeMouse.containsMouse ? MLTheme.panelRaised : "transparent"
            border.color:           MLTheme.line
            Text { anchors.centerIn: parent; text: "✕"; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: confirmCancelled() }
        }
    }
}
