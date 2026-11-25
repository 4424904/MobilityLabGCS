import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 경고 · 알림 panel: MASTER WARNING / MASTER CAUTION lamps and the active
// alert list (CAS). Lists the powertrain alerts from TandemTelemetry plus
// conditions any airframe can have (link lost, battery, GPS).
// Lamps flash for new powertrain alerts until pressed (acknowledge).
MLPanel {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property bool _commLost:   !!vehicle && vehicle.vehicleLinkManager.communicationLost

    function _v(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined) ? NaN : v
    }

    // Alerts every airframe can raise, computed from QGC's vehicle data
    readonly property var _generic: {
        var list = []
        if (!vehicle) return list
        if (_commLost) {
            list.push({ level: 3, text: qsTr("통신 두절"), time: "", acked: true })
        }
        var bats = vehicle.batteries
        for (var i = 0; bats && i < bats.count; i++) {
            var b = bats.get(i)
            if (!b) continue
            var state = _v(b.chargeState), pct = _v(b.percentRemaining)
            var name = bats.count > 1 ? qsTr("배터리 %1").arg(_v(b.id) + 1) : qsTr("배터리")
            if (state >= 3 || (!isNaN(pct) && pct < 15)) {
                list.push({ level: 3, text: qsTr("%1 잔량 위험").arg(name), time: "", acked: true })
            } else if (state === 2 || (!isNaN(pct) && pct < 30)) {
                list.push({ level: 2, text: qsTr("%1 잔량 낮음").arg(name), time: "", acked: true })
            }
        }
        var lock = _v(vehicle.gps.lock)
        if (vehicle.armed && !isNaN(lock) && lock < 3) {
            list.push({ level: vehicle.flying ? 3 : 2, text: qsTr("GPS 위치 고정 안 됨"), time: "", acked: true })
        }
        return list
    }

    readonly property var _alerts: {
        var all = _generic.concat(_t ? _t.alerts : [])
        all.sort(function(a, b) { return b.level - a.level })
        return all
    }
    readonly property bool _anyWarn: _alerts.some(function(a) { return a.level === 3 })
    readonly property bool _anyCaut: _alerts.some(function(a) { return a.level === 2 })

    title:          qsTr("경고 · 알림")
    tag:            "CAS"
    detail:         _alerts.length > 0 ? qsTr("%1건").arg(_alerts.length) : ""
    detailColor:    _anyWarn ? MLTheme.warning : MLTheme.caution

    component Lamp: Rectangle {
        id: lamp

        property string title
        property bool   lit:        false   // flashing, unacknowledged
        property bool   latched:    false   // acknowledged but still active
        property color  litColor
        property color  litText

        signal pressed()

        height:         ScreenTools.defaultFontPixelHeight * 2.1
        radius:         ScreenTools.defaultFontPixelWidth * 0.4
        color:          lit ? litColor : (latched ? Qt.rgba(litColor.r, litColor.g, litColor.b, 0.16) : MLTheme.tile)
        border.width:   Math.max(1, ScreenTools.defaultFontPixelWidth * 0.2)
        border.color:   (lit || latched) ? litColor : MLTheme.lineStrong

        QGCLabel {
            anchors.centerIn:   parent
            text:               lamp.title
            color:              lamp.lit ? lamp.litText : (lamp.latched ? lamp.litColor : MLTheme.faint)
            font.pointSize:     ScreenTools.smallFontPointSize
            font.bold:          true
            font.letterSpacing: 1
        }

        SequentialAnimation on opacity {
            running:        lamp.lit
            loops:          Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 1; to: 0.35; duration: 450 }
            NumberAnimation { from: 0.35; to: 1; duration: 450 }
        }

        MouseArea {
            anchors.fill:   parent
            cursorShape:    Qt.PointingHandCursor
            onClicked:      lamp.pressed()
        }

        ToolTip.visible:    lamp.lit && hoverArea.containsMouse
        ToolTip.text:       qsTr("눌러서 확인")
        MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }

    Row {
        id:         lampRow
        width:      parent.width
        spacing:    ScreenTools.defaultFontPixelWidth * 0.6

        Lamp {
            width:      (lampRow.width - lampRow.spacing) / 2
            title:      "MASTER WARNING"
            lit:        !!root._t && root._t.masterWarning
            latched:    root._anyWarn
            litColor:   MLTheme.warning
            litText:    "white"
            onPressed:  if (root._t) root._t.acknowledgeAll()
        }
        Lamp {
            width:      (lampRow.width - lampRow.spacing) / 2
            title:      "MASTER CAUTION"
            lit:        !!root._t && root._t.masterCaution
            latched:    root._anyCaut
            litColor:   MLTheme.caution
            litText:    "#1b1300"
            onPressed:  if (root._t) root._t.acknowledgeAll()
        }
    }

    // No active alerts: one green status line
    Rectangle {
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        lampRow.bottom
        anchors.topMargin:  ScreenTools.defaultFontPixelHeight * 0.45
        visible:            root._alerts.length === 0
        height:             ScreenTools.defaultFontPixelHeight * 1.9
        radius:             ScreenTools.defaultFontPixelWidth * 0.3
        color:              root.vehicle ? "#163325" : MLTheme.tile
        border.width:       1
        border.color:       root.vehicle ? "#2c7a4c" : MLTheme.line

        QGCLabel {
            id:                     okIcon
            anchors.left:           parent.left
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            text:                   root.vehicle ? "✓" : "…"
            color:                  root.vehicle ? MLTheme.ok : MLTheme.faint
            font.bold:              true
            font.pointSize:         ScreenTools.mediumFontPointSize
        }
        QGCLabel {
            anchors.left:           okIcon.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            text:                   root.vehicle ? qsTr("모든 시스템 정상") : qsTr("기체 연결 대기")
            color:                  root.vehicle ? MLTheme.ok : MLTheme.faint
            font.bold:              true
        }
    }

    ListView {
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        lampRow.bottom
        anchors.bottom:     parent.bottom
        anchors.topMargin:  ScreenTools.defaultFontPixelHeight * 0.45
        visible:            root._alerts.length > 0
        clip:               true
        spacing:            ScreenTools.defaultFontPixelHeight * 0.2
        model:              root._alerts.length
        boundsBehavior:     Flickable.StopAtBounds

        delegate: Rectangle {
            readonly property var alertItem: root._alerts[index] || ({ level: 0, text: "", time: "", acked: true })

            width:      ListView.view.width
            height:     ScreenTools.defaultFontPixelHeight * 1.7
            radius:     ScreenTools.defaultFontPixelWidth * 0.3
            color:      alertItem.acked ? MLTheme.tile : (alertItem.level === 3 ? "#55ff4f4f" : "#45f5b331")

            Rectangle {
                width:  Math.max(3, ScreenTools.defaultFontPixelWidth * 0.35)
                height: parent.height
                radius: width / 2
                color:  alertItem.level === 3 ? MLTheme.warning : MLTheme.caution
            }
            QGCLabel {
                id:                     levelText
                anchors.left:           parent.left
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 1.1
                anchors.verticalCenter: parent.verticalCenter
                text:                   alertItem.level === 3 ? qsTr("경고") : qsTr("주의")
                color:                  alertItem.level === 3 ? MLTheme.warning : MLTheme.caution
                font.bold:              true
                font.pointSize:         ScreenTools.smallFontPointSize
            }
            QGCLabel {
                anchors.left:           levelText.right
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.8
                anchors.right:          timeText.left
                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.5
                anchors.verticalCenter: parent.verticalCenter
                text:                   alertItem.text
                color:                  MLTheme.text
                elide:                  Text.ElideRight
            }
            QGCLabel {
                id:                     timeText
                anchors.right:          parent.right
                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.7
                anchors.verticalCenter: parent.verticalCenter
                text:                   alertItem.time || ""
                color:                  MLTheme.dim
                font.family:            ScreenTools.fixedFontFamily
                font.pointSize:         ScreenTools.smallFontPointSize
            }
        }
    }
}
