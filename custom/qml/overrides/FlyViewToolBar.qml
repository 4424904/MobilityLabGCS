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
    // MainStatusIndicator writes its state colour here (ready / not ready / armed / comms lost)
    property color  _mainStatusBGColor:     qgcPal.brandingPurple
    property bool   _indicatorsOpen:        false

    QGCPalette { id: qgcPal }

    function dropMainStatusIndicatorTool() {
        mainStatusIndicator.dropMainStatusIndicator();
    }

    function _fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }

    Rectangle {
        anchors.fill:   parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: String(MLTheme.panelHeader) }
            GradientStop { position: 1.0; color: String(MLTheme.panelSolid) }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
        // lit seam under the bar, brightest over the map
        Rectangle {
            anchors.bottom: parent.bottom
            x: parent.width * 0.18; width: parent.width * 0.64; height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: String(MLTheme.alpha(MLTheme.accent, 0.6)) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    Row {
        id:     leftRow
        height: parent.height

        // ---- brand / main menu -------------------------------------------
        Item {
            width:  control.leftWidth
            height: parent.height
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            Rectangle { anchors.fill: parent; anchors.rightMargin: 1; color: brandMouse.containsMouse ? String(MLTheme.hover) : "transparent" }
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
            // operating mode chip: SIM (cyan) / FIELD (red); amber and blinking when the fleet does not match
            Rectangle {
                id: modeChip
                readonly property bool   _g:       typeof mlGuard !== "undefined"
                readonly property bool   field:    _g && mlGuard.opMode === "field"
                readonly property bool   demo:     typeof mlDemo !== "undefined" && mlDemo.active
                readonly property bool   problem:  _g && mlGuard.opModeProblem !== ""
                readonly property color  tone:     demo ? MLTheme.demo : (problem ? MLTheme.caution : (field ? MLTheme.warning : String(MLTheme.accent)))
                z:      2
                anchors.right:          parent.right
                anchors.rightMargin:    16 * u
                anchors.verticalCenter: parent.verticalCenter
                width:  modeText.implicitWidth + 16 * u
                height: 20 * u
                radius: 3 * u
                color:  Qt.rgba(tone.r, tone.g, tone.b, 0.14)
                border.color: tone
                visible: _g
                MLText {
                    id: modeText
                    anchors.centerIn: parent
                    text: modeChip.demo ? "DEMO" : (modeChip.field ? "FIELD" : "SIM")
                    color: modeChip.tone
                    font.family: MLTheme.mono
                    font.pixelSize: MLTheme.fsLabel
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2 * u
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4 * u
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MLState.demoOpen = !MLState.demoOpen
                }
                SequentialAnimation on opacity {
                    running: modeChip.problem && !modeChip.demo
                    loops: Animation.Infinite
                    onStopped: modeChip.opacity = 1
                    NumberAnimation { to: 0.35; duration: 450 }
                    NumberAnimation { to: 1.0; duration: 450 }
                }
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
            Rectangle { anchors.bottom: parent.bottom; width: parent.width - 1; height: 2 * u; color: control._mainStatusBGColor }
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
                Rectangle { anchors.fill: parent; color: tab._active ? String(MLTheme.hover) : (tabMouse.containsMouse ? String(MLTheme.tile) : "transparent") }
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
            Rectangle { anchors.fill: parent; color: MLState.fleetOpen ? String(MLTheme.hover) : (fleetMouse.containsMouse ? String(MLTheme.tile) : "transparent") }
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
    }
    // In the bar when there is room; otherwise it drops just below it
    Rectangle {
        id:         confirmHost
        readonly property bool _fits:   centerPanel.width >= guidedActionConfirm.width + 24 * u
        readonly property bool _shown:  guidedActionConfirm.visible
        width:      guidedActionConfirm.width + (_fits ? 0 : 28 * u)
        height:     _fits ? control.height : 56 * u
        x:          _fits ? centerPanel.x + (centerPanel.width - width) / 2 : (control.width - width) / 2
        y:          _fits ? 0 : control.height + 8 * u
        z:          QGroundControl.zOrderTopMost
        radius:     _fits ? 0 : MLTheme.panelRadius
        color:      _shown && !_fits ? MLTheme.glassStrong : "transparent"
        border.color: _shown && !_fits ? String(MLTheme.alpha(MLTheme.caution, 0.55)) : "transparent"

        GuidedActionConfirm {
            id:                         guidedActionConfirm
            height:                     confirmHost._fits ? control.height : 44 * u
            anchors.centerIn:           parent
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

        // ---- status strip: LINK · GNSS · BATT · FC -------------------------
        component StatusCell: Item {
            property string label
            property string value
            property string sub
            property color  valueColor: MLTheme.text
            property color  ledColor:   "transparent"
            width:  Math.max(84 * u, cellCol.implicitWidth + 30 * u)
            height: rightRow.height
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            Column {
                id:                     cellCol
                x:                      16 * u
                anchors.verticalCenter: parent.verticalCenter
                spacing:                1 * u
                Row {
                    spacing: 6 * u
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 5 * u; height: 5 * u; radius: width / 2; color: ledColor; visible: ledColor.a > 0 }
                    Text { text: label; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.9 * u }
                }
                Text { text: value; color: valueColor; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.Medium }
                Text { text: sub; visible: sub !== ""; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
            }
        }

        readonly property bool _has:   !!control._activeVehicle
        readonly property var  _bat:   _has && control._activeVehicle.batteries.count > 0 ? control._activeVehicle.batteries.get(0) : null
        readonly property real _pct:   _bat ? control._fv(_bat.percentRemaining) : NaN
        readonly property real _volt:  _bat ? control._fv(_bat.voltage) : NaN
        readonly property real _lock:  _has ? control._fv(control._activeVehicle.gps.lock) : NaN
        readonly property real _sats:  _has ? control._fv(control._activeVehicle.gps.count) : NaN
        readonly property real _hdop:  _has ? control._fv(control._activeVehicle.gps.hdop) : NaN
        readonly property real _rssi:  _has ? control._fv(control._activeVehicle.radioStatus.lrssi) : NaN
        readonly property var  _fw:    MLTheme.fwInfo(control._activeVehicle)

        StatusCell {
            label:      "LINK"
            value:      !rightRow._has ? "—" : (control._communicationLost ? qsTr("두절") : (!isNaN(rightRow._rssi) && rightRow._rssi !== 0 ? rightRow._rssi.toFixed(0) + " dBm" : "OK"))
            valueColor: control._communicationLost ? MLTheme.warning : MLTheme.text
            ledColor:   !rightRow._has ? MLTheme.faint : (control._communicationLost ? MLTheme.warning : MLTheme.active)
        }
        StatusCell {
            label:      "GNSS"
            value:      isNaN(rightRow._lock) ? "—" : (rightRow._lock >= 6 ? "RTK FIX" : (rightRow._lock === 5 ? "RTK FLT" : (rightRow._lock >= 3 ? "3D" : (rightRow._lock === 2 ? "2D" : "NO FIX")))) + (isNaN(rightRow._sats) ? "" : "  " + rightRow._sats.toFixed(0))
            valueColor: !isNaN(rightRow._lock) && rightRow._lock < 3 ? MLTheme.warning : MLTheme.text
            ledColor:   isNaN(rightRow._lock) ? MLTheme.faint : (rightRow._lock < 3 ? MLTheme.warning : (!isNaN(rightRow._hdop) && rightRow._hdop > 2.5 ? MLTheme.caution : MLTheme.active))
        }
        StatusCell {
            label:      "BATT"
            value:      isNaN(rightRow._pct) ? "—" : rightRow._pct.toFixed(0) + "%" + (isNaN(rightRow._volt) ? "" : "  " + rightRow._volt.toFixed(1) + "V")
            valueColor: isNaN(rightRow._pct) ? MLTheme.text : (rightRow._pct < 15 ? MLTheme.warning : (rightRow._pct < 30 ? MLTheme.caution : MLTheme.text))
            ledColor:   isNaN(rightRow._pct) ? MLTheme.faint : (rightRow._pct < 15 ? MLTheme.warning : (rightRow._pct < 30 ? MLTheme.caution : MLTheme.active))
        }
        StatusCell {
            label:      "FC"
            value:      !rightRow._has ? "—" : rightRow._fw.name + (rightRow._fw.known ? " " + rightRow._fw.version : "")
            valueColor: rightRow._has && (!rightRow._fw.ok || rightRow._fw.modeUnknown) ? MLTheme.caution : MLTheme.text
            ledColor:   !rightRow._has ? MLTheme.faint : (!rightRow._fw.ok || rightRow._fw.modeUnknown ? MLTheme.caution : MLTheme.active)
        }

        // display: theme (day / night) and the layout menu
        Item {
            width:  viewRow.implicitWidth + 20 * u
            height: parent.height
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            Row {
                id: viewRow
                anchors.centerIn: parent
                spacing: 4 * u
                // alert centre: bell with the number of unacknowledged alerts, coloured by the worst
                MLIconButton {
                    id:         bell
                    readonly property var c: MLState.alertCenter
                    readonly property int n: c ? c.unacked : 0
                    readonly property int w: c ? c.worst : 0
                    size:       34 * u
                    glyph:      "🔔"
                    tip:        qsTr("통합 경고 센터")
                    checked:    alertPop.opened
                    tone:       w >= 3 ? MLTheme.warning : (w === 2 ? MLTheme.caution : MLTheme.accent)
                    onClicked:  alertPop.opened ? alertPop.close() : alertPop.open()
                    Rectangle {
                        visible:    bell.n > 0
                        anchors.right: parent.right; anchors.top: parent.top
                        anchors.rightMargin: -3 * u; anchors.topMargin: -3 * u
                        width:      Math.max(18 * u, cnt.implicitWidth + 8 * u); height: 18 * u; radius: 9 * u
                        color:      bell.w >= 3 ? MLTheme.warning : (bell.w === 2 ? MLTheme.caution : MLTheme.info)
                        Text { id: cnt; anchors.centerIn: parent; text: bell.n; color: "white"; font.family: MLTheme.mono; font.pixelSize: 11 * u; font.weight: Font.Bold }
                        SequentialAnimation on opacity {
                            running: bell.w >= 3 && bell.n > 0; loops: Animation.Infinite
                            onStopped: parent.opacity = 1
                            NumberAnimation { to: 0.4; duration: 400 } NumberAnimation { to: 1; duration: 400 }
                        }
                    }
                    MLAlertCenterPanel { id: alertPop; y: parent.height + 10 * u; x: parent.width - width }
                }
                MLIconButton {
                    size:       34 * u
                    glyph:      "☑"
                    tip:        qsTr("비행 전 통합 점검")
                    checked:    MLState.preflightOpen
                    onClicked:  MLState.preflightOpen = !MLState.preflightOpen
                }
                MLIconButton {
                    size:       34 * u
                    glyph:      MLTheme.day ? "☀" : "☾"
                    tip:        MLTheme.day ? qsTr("주간 테마 — 눌러서 야간으로") : qsTr("야간 테마 — 눌러서 주간으로")
                    onClicked:  MLTheme.setDay(!MLTheme.day)
                }
                MLIconButton {
                    id:         layoutBtn
                    size:       34 * u
                    glyph:      "▦"
                    tip:        qsTr("화면 구성 · 레이아웃")
                    checked:    layoutMenu.opened
                    onClicked:  layoutMenu.opened ? layoutMenu.close() : layoutMenu.open()
                    MLLayoutMenu { id: layoutMenu; y: parent.height + 10 * u; x: parent.width - width }
                }
            }
        }

        // QGC's own indicators (RTK, gimbal, remote ID, …) in a drop-down
        Item {
            width:  moreText.implicitWidth + 28 * u
            height: parent.height
            Rectangle { anchors.fill: parent; color: control._indicatorsOpen ? MLTheme.panelRaised : (moreMouse.containsMouse ? String(MLTheme.tile) : "transparent") }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            MLText { id: moreText; anchors.centerIn: parent; text: qsTr("상세 ▾"); color: control._indicatorsOpen ? MLTheme.accent : MLTheme.label; font.pixelSize: MLTheme.fsSmall }
            MouseArea { id: moreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: control._indicatorsOpen = !control._indicatorsOpen }
        }

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
        y:                          confirmHost._fits ? control.height + _margins : confirmHost.y + confirmHost.height + _margins
        x:                          confirmHost.x + (confirmHost.width - guidedActionMessageDisplay.width) / 2
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

    Rectangle {
        id:             indicatorDrop
        visible:        control._indicatorsOpen
        anchors.top:    control.bottom
        anchors.right:  control.right
        anchors.rightMargin: clock.width
        width:          flyViewIndicators.implicitWidth + 16 * u
        height:         46 * u
        color:          MLTheme.panelSolid
        border.color:   MLTheme.lineStrong
        z:              QGroundControl.zOrderTopMost
        FlyViewToolBarIndicators {
            id:             flyViewIndicators
            anchors.left:   parent.left
            anchors.leftMargin: 8 * u
            height:         parent.height
        }
    }

    ParameterDownloadProgress {
        anchors.fill: parent
    }
}
