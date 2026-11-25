// MobilityLab GCS: console top bar in place of QGC's fly-view toolbar.
//
//   [≡ MOBILITY LAB ][상태][모드] [UAV 01 탠덤 헬기][UAV 02 X500][편대]  ( confirm )  [QGC 표시기][UTC][KST 시계]
//
// Keeps everything QGC needs from its toolbar: the main menu (logo), the
// main status (arming checks, messages), the flight-mode menu, the guided
// action confirm slider and its message, the indicator icons and the
// parameter download progress.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.Toolbar

import MobilityLab.Controls

Item {
    required property var guidedValueSlider
    property real leftWidth: 460 * MLTheme.u

    id:     control
    width:  parent.width
    height: 52 * MLTheme.u

    readonly property real u:               MLTheme.u
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _vehicles:              QGroundControl.multiVehicleManager.vehicles
    property bool   _communicationLost:     _activeVehicle ? _activeVehicle.vehicleLinkManager.communicationLost : false
    property var    _guidedController:      globals.guidedControllerFlyView
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2

    function dropMainStatusIndicatorTool() {
        mainStatusIndicator.dropMainStatusIndicator();
    }

    function _fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }

    Rectangle {
        anchors.fill:   parent
        color:          MLTheme.panelSolid
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
    }

    Row {
        id:     leftRow
        height: parent.height

        // ---- brand / main menu -------------------------------------------
        Item {
            width:  control.leftWidth
            height: parent.height
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            Rectangle { anchors.fill: parent; anchors.rightMargin: 1; color: brandMouse.containsMouse ? "#0F1418" : "transparent" }
            Row {
                anchors.left:           parent.left
                anchors.leftMargin:     20 * u
                anchors.verticalCenter: parent.verticalCenter
                spacing:                12 * u
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source:             "/MobilityLab/logo.svg"
                    sourceSize.height:  22 * u
                    fillMode:           Image.PreserveAspectFit
                }
                MLText {
                    anchors.verticalCenter: parent.verticalCenter
                    text:               "MOBILITY LAB"
                    font.pixelSize:     13 * u
                    font.weight:        Font.DemiBold
                    font.letterSpacing: 2.3 * u
                }
            }
            MLText {
                anchors.right:          parent.right
                anchors.rightMargin:    20 * u
                anchors.verticalCenter: parent.verticalCenter
                text:                   qsTr("메뉴")
                color:                  MLTheme.dim
                font.pixelSize:         MLTheme.fsLabel
                font.letterSpacing:     0.7 * u
            }
            MouseArea {
                id:             brandMouse
                objectName:     "toolbar_qgcLogo"
                anchors.fill:   parent
                hoverEnabled:   true
                cursorShape:    Qt.PointingHandCursor
                onClicked:      mainWindow.showToolSelectDialog()
            }
        }

        // ---- QGC main status + flight mode menu ---------------------------
        Item {
            width:  statusRow.implicitWidth + 24 * u
            height: parent.height
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            RowLayout {
                id:                     statusRow
                anchors.left:           parent.left
                anchors.leftMargin:     12 * u
                height:                 parent.height
                spacing:                ScreenTools.defaultFontPixelWidth * 1.5
                MainStatusIndicator {
                    id:                 mainStatusIndicator
                    objectName:         "toolbar_mainStatusIndicator"
                    Layout.fillHeight:  true
                }
                QGCButton {
                    text:       qsTr("연결 끊기")
                    onClicked:  _activeVehicle.closeVehicle()
                    visible:    _activeVehicle && _communicationLost
                }
                FlightModeIndicator {
                    objectName:         "toolbar_flightModeIndicator"
                    Layout.fillHeight:  true
                    visible:            !!_activeVehicle
                }
            }
        }

        // ---- vehicle tabs -------------------------------------------------
        Repeater {
            model: control._vehicles

            Item {
                id: tab
                required property var object
                readonly property bool _active: object === control._activeVehicle
                readonly property bool _lost:   object && object.vehicleLinkManager.communicationLost
                width:  196 * u
                height: leftRow.height
                Rectangle { anchors.fill: parent; color: tab._active ? "#11161B" : (tabMouse.containsMouse ? "#0D1115" : "transparent") }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
                Rectangle { visible: tab._active; anchors.bottom: parent.bottom; width: parent.width; height: 2 * u; color: MLTheme.accent }
                Column {
                    anchors.left:           parent.left
                    anchors.leftMargin:     18 * u
                    anchors.right:          parent.right
                    anchors.rightMargin:    10 * u
                    anchors.verticalCenter: parent.verticalCenter
                    spacing:                2 * u
                    Row {
                        spacing: 8 * u
                        Text {
                            text:           "UAV " + ("0" + (tab.object ? tab.object.id : 0)).slice(-2)
                            color:          tab._lost ? MLTheme.warning : (tab._active ? MLTheme.accent : MLTheme.label)
                            font.family:    MLTheme.mono
                            font.pixelSize: MLTheme.fsSmall
                        }
                        MLText {
                            text:           tab.object ? MLTheme.vehicleTypeName(tab.object) : ""
                            color:          tab._active ? MLTheme.bright : MLTheme.label
                            font.weight:    tab._active ? Font.DemiBold : Font.Normal
                        }
                    }
                    Text {
                        width:          parent.width
                        elide:          Text.ElideRight
                        text: {
                            var v = tab.object
                            if (!v) return ""
                            if (tab._lost) return qsTr("통신 두절")
                            var a = control._fv(v.altitudeRelative), s = control._fv(v.groundSpeed)
                            return v.flightMode + " · " + (isNaN(a) ? "—" : a.toFixed(0) + " m") + " · " + (isNaN(s) ? "—" : s.toFixed(1) + " m/s")
                        }
                        color:          tab._lost ? MLTheme.warning : MLTheme.dim
                        font.family:    MLTheme.mono
                        font.pixelSize: MLTheme.fsLabel
                    }
                }
                MouseArea {
                    id:             tabMouse
                    anchors.fill:   parent
                    hoverEnabled:   true
                    cursorShape:    Qt.PointingHandCursor
                    onClicked:      QGroundControl.multiVehicleManager.activeVehicle = tab.object
                }
            }
        }

        // fleet commands (2+ vehicles)
        Item {
            visible:    control._vehicles.count > 1
            width:      fleetText.implicitWidth + 32 * u
            height:     leftRow.height
            Rectangle { anchors.fill: parent; color: MLState.fleetOpen ? "#11161B" : (fleetMouse.containsMouse ? "#0D1115" : "transparent") }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            MLText { id: fleetText; anchors.centerIn: parent; text: qsTr("편대 명령"); color: MLState.fleetOpen ? MLTheme.accent : MLTheme.label; font.pixelSize: MLTheme.fsSmall }
            MouseArea { id: fleetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: MLState.fleetOpen = !MLState.fleetOpen }
        }
    }

    // ---- guided action confirm (centre) --------------------------------------
    Item {
        id:             centerPanel
        anchors.left:   leftRow.right
        anchors.right:  rightRow.left
        height:         parent.height

        GuidedActionConfirm {
            id:                         guidedActionConfirm
            height:                     parent.height
            anchors.horizontalCenter:   parent.horizontalCenter
            guidedController:           control._guidedController
            guidedValueSlider:          control.guidedValueSlider
            messageDisplay:             guidedActionMessageDisplay
        }
    }

    // ---- right: QGC indicators + clocks --------------------------------------
    Row {
        id:             rightRow
        anchors.right:  parent.right
        height:         parent.height

        FlyViewToolBarIndicators {
            id:     flyViewIndicators
            height: parent.height
        }
        Rectangle { width: 1; height: parent.height; color: MLTheme.line }

        Item {
            id:     clock
            width:  clockRow.implicitWidth + 40 * u
            height: parent.height
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
            Row {
                id:                     clockRow
                anchors.centerIn:       parent
                spacing:                22 * u
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    MLText { text: "UTC"; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.7 * u }
                    Text { text: Qt.formatTime(new Date(clock.now.getTime() + clock.now.getTimezoneOffset() * 60000), "hh:mm:ss"); color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.right: parent.right; text: Qt.formatTime(clock.now, "hh:mm:ss"); color: MLTheme.bright; font.family: MLTheme.mono; font.pixelSize: 19 * u; font.weight: Font.Medium }
                    Text { anchors.right: parent.right; text: Qt.formatDate(clock.now, "yyyy-MM-dd"); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                }
            }
        }
    }

    // The guided action message display is outside the confirm control so it is not clipped
    Rectangle {
        id:                         guidedActionMessageDisplay
        anchors.top:                control.bottom
        anchors.topMargin:          _margins
        x:                          control.mapFromItem(guidedActionConfirm.parent, guidedActionConfirm.x, 0).x + (guidedActionConfirm.width - guidedActionMessageDisplay.width) / 2
        width:                      messageLabel.contentWidth + (_margins * 2)
        height:                     messageLabel.contentHeight + (_margins * 2)
        color:                      MLTheme.panel
        border.color:               MLTheme.lineStrong
        radius:                     ScreenTools.defaultBorderRadius
        visible:                    guidedActionConfirm.visible

        QGCLabel {
            id:         messageLabel
            x:          _margins
            y:          _margins
            width:      ScreenTools.defaultFontPixelWidth * 30
            wrapMode:   Text.WordWrap
            text:       guidedActionConfirm.message
        }

        PropertyAnimation {
            id:         messageOpacityAnimation
            target:     guidedActionMessageDisplay
            property:   "opacity"
            from:       1
            to:         0
            duration:   500
        }

        Timer {
            id:             messageFadeTimer
            interval:       4000
            onTriggered:    messageOpacityAnimation.start()
        }
    }

    ParameterDownloadProgress {
        anchors.fill: parent
    }
}
