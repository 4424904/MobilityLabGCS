import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Right-hand systems panel (EICAS-style) for the tandem helicopter:
// rotors, engine/ECU, drivetrain, fuel and power.
// Groups whose data has never been received show a short "waiting" line
// instead of a list of empty values.
Rectangle {
    id: root

    property bool collapsed: false

    readonly property var  _t:      typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property real _pad:    ScreenTools.defaultFontPixelWidth * 1.2

    function anySeen(seenKeys, keys) {
        for (var i = 0; i < keys.length; i++) {
            if (seenKeys[keys[i]] === true) return true
        }
        return false
    }

    readonly property var _engineKeys:  [ "eng.rpm", "coolant", "eng.cht", "eng.egt", "oil.temp", "oil.press", "eng.thr", "eng.fuelPress" ]
    readonly property var _driveKeys:   [ "gb.front", "gb.rear" ]
    readonly property var _fuelKeys:    [ "fuel.pct", "fuel.L", "eng.flow", "fuel.endurance" ]
    readonly property var _powerKeys:   [ "pwr.main", "pwr.aux", "pwr.genA" ]

    readonly property var  _seenKeys:   _t ? _t.seenKeys : ({})
    readonly property bool _engineSeen: anySeen(_seenKeys, _engineKeys)
    readonly property bool _driveSeen:  anySeen(_seenKeys, _driveKeys)
    readonly property bool _fuelSeen:   anySeen(_seenKeys, _fuelKeys)
    readonly property bool _powerSeen:  anySeen(_seenKeys, _powerKeys)
    readonly property real _ecuHealth:  { var v = _t ? _t.values["eng.health"] : undefined; return v === undefined ? NaN : v }

    color:          MLTheme.panel
    radius:         ScreenTools.defaultFontPixelWidth * 0.6
    border.color:   MLTheme.line
    border.width:   1
    clip:           true

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 36
    implicitHeight: header.height + (collapsed ? 0 : content.implicitHeight + _pad * 2)

    // ---- Header -----------------------------------------------------------
    Rectangle {
        id:             header
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.top:    parent.top
        height:         ScreenTools.defaultFontPixelHeight * 2.4
        color:          "transparent"

        QGCLabel {
            id:                     headerTitle
            anchors.left:           parent.left
            anchors.leftMargin:     root._pad
            anchors.verticalCenter: parent.verticalCenter
            text:                   qsTr("탠덤 계통")
            color:                  MLTheme.text
            font.pointSize:         ScreenTools.mediumFontPointSize
            font.bold:              true
        }

        Rectangle {
            visible:                !!root._t && root._t.provisionalLimits
            anchors.left:           headerTitle.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            width:                  provisionalText.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2
            height:                 provisionalText.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.2
            radius:                 height / 2
            color:                  "transparent"
            border.color:           MLTheme.lineStrong
            border.width:           1

            QGCLabel {
                id:                 provisionalText
                anchors.centerIn:   parent
                text:               qsTr("임계값 임시")
                color:              MLTheme.dim
                font.pointSize:     ScreenTools.smallFontPointSize
            }

            ToolTip.visible:    provisionalMouse.containsMouse
            ToolTip.text:       qsTr("경고 임계값은 ICD·비행교범 확정 전 임시값입니다 (tandem.json)")
            MouseArea { id: provisionalMouse; anchors.fill: parent; hoverEnabled: true }
        }

        QGCColoredImage {
            anchors.right:          parent.right
            anchors.rightMargin:    root._pad * 0.6
            anchors.verticalCenter: parent.verticalCenter
            width:                  ScreenTools.defaultFontPixelHeight * 1.4
            height:                 width
            source:                 "/MobilityLab/icons/collapse.svg"
            color:                  MLTheme.dim
            rotation:               root.collapsed ? -90 : 0
        }

        MouseArea {
            anchors.fill:   parent
            cursorShape:    Qt.PointingHandCursor
            onClicked:      root.collapsed = !root.collapsed
        }

        Rectangle {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            height:         1
            color:          MLTheme.line
            visible:        !root.collapsed
        }
    }

    // ---- Content ----------------------------------------------------------
    QGCFlickable {
        id:                 flick
        visible:            !root.collapsed
        anchors.top:        header.bottom
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        anchors.margins:    root._pad
        contentHeight:      content.implicitHeight
        clip:               true

        Column {
            id:         content
            width:      flick.width
            spacing:    ScreenTools.defaultFontPixelHeight * 0.15

            MLRotorSync { width: parent.width }

            MLSectionHeader {
                width:          parent.width
                title:          qsTr("엔진 · ECU")
                detail:         isNaN(root._ecuHealth) ? "ROTAX 916 iS" : (root._ecuHealth > 0 ? qsTr("ECU 정상") : qsTr("ECU 이상"))
                detailColor:    isNaN(root._ecuHealth) ? MLTheme.dim : (root._ecuHealth > 0 ? MLTheme.ok : MLTheme.warning)
            }
            QGCLabel {
                visible:        !root._engineSeen
                text:           qsTr("ECU 데이터 수신 대기 (EFI_STATUS)")
                color:          MLTheme.faint
                font.pointSize: ScreenTools.smallFontPointSize
            }
            MLGaugeRow { width: parent.width; key: "eng.rpm" }
            MLGaugeRow { width: parent.width; key: "coolant" }
            MLGaugeRow { width: parent.width; key: "eng.cht" }
            MLGaugeRow { width: parent.width; key: "eng.egt" }
            MLGaugeRow { width: parent.width; key: "oil.temp" }
            MLGaugeRow { width: parent.width; key: "oil.press" }
            MLGaugeRow { width: parent.width; key: "eng.thr" }
            MLGaugeRow { width: parent.width; key: "eng.fuelPress" }

            MLSectionHeader {
                width:          parent.width
                title:          qsTr("동력전달")
                visible:        root._driveSeen
            }
            MLGaugeRow { width: parent.width; key: "gb.front" }
            MLGaugeRow { width: parent.width; key: "gb.rear" }

            MLSectionHeader {
                width:          parent.width
                title:          qsTr("연료")
            }
            QGCLabel {
                visible:        !root._fuelSeen
                text:           qsTr("연료 데이터 수신 대기")
                color:          MLTheme.faint
                font.pointSize: ScreenTools.smallFontPointSize
            }
            MLGaugeRow { width: parent.width; key: "fuel.pct" }
            MLGaugeRow { width: parent.width; key: "fuel.L" }
            MLGaugeRow { width: parent.width; key: "eng.flow" }
            MLGaugeRow { width: parent.width; key: "fuel.endurance" }

            MLSectionHeader {
                width:          parent.width
                title:          qsTr("전원")
            }
            QGCLabel {
                visible:        !root._powerSeen
                text:           qsTr("전원 데이터 수신 대기")
                color:          MLTheme.faint
                font.pointSize: ScreenTools.smallFontPointSize
            }
            MLGaugeRow { width: parent.width; key: "pwr.main" }
            MLGaugeRow { width: parent.width; key: "pwr.aux" }
            MLGaugeRow { width: parent.width; key: "pwr.genA" }
        }
    }
}
