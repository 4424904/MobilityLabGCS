import QtQuick

import QGroundControl
import QGroundControl.Controls

// One row per battery reported by the vehicle (BATTERY_STATUS / SYS_STATUS):
//
//   [■■■■■■■□□□]  72 %        24.8 V   12.1 A   1,240 mAh   18:20
Column {
    id: root

    property var vehicle

    readonly property var _batteries: vehicle ? vehicle.batteries : null

    spacing: ScreenTools.defaultFontPixelHeight * 0.4

    function _v(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined) ? NaN : v
    }

    QGCLabel {
        visible:        !root._batteries || root._batteries.count === 0
        text:           qsTr("배터리 정보 수신 대기")
        color:          MLTheme.faint
        font.pointSize: ScreenTools.smallFontPointSize
    }

    Repeater {
        model: root._batteries

        Item {
            id: row

            readonly property var  _b:       object
            readonly property real _pct:     root._v(_b.percentRemaining)
            readonly property int  _state:   isNaN(root._v(_b.chargeState)) ? 0 : root._v(_b.chargeState)
            // MAV_BATTERY_CHARGE_STATE: 2 low, 3 critical, 4 emergency, 5 failed, 6 unhealthy
            readonly property int  _level:   _state >= 3 ? 3 : (_state === 2 ? 2 : (isNaN(_pct) ? 1 : (_pct < 15 ? 3 : (_pct < 30 ? 2 : 1))))
            readonly property color _fill:   _level === 3 ? MLTheme.warning : (_level === 2 ? MLTheme.caution : MLTheme.ok)

            width:  root.width
            height: Math.max(cell.height, details.implicitHeight)

            // Battery glyph
            Item {
                id:         cell
                width:      ScreenTools.defaultFontPixelWidth * 7.5
                height:     ScreenTools.defaultFontPixelHeight * 2
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    id:             shell
                    width:          parent.width - ScreenTools.defaultFontPixelWidth * 0.5
                    height:         parent.height
                    radius:         ScreenTools.defaultFontPixelWidth * 0.4
                    color:          "transparent"
                    border.color:   MLTheme.lineStrong
                    border.width:   Math.max(1, ScreenTools.defaultFontPixelWidth * 0.15)

                    Rectangle {
                        anchors.left:   parent.left
                        anchors.top:    parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: Math.max(2, ScreenTools.defaultFontPixelWidth * 0.25)
                        width:          isNaN(row._pct) ? 0 : (parent.width - anchors.margins * 2) * Math.max(0, Math.min(1, row._pct / 100))
                        radius:         ScreenTools.defaultFontPixelWidth * 0.2
                        color:          row._fill
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
                Rectangle {
                    anchors.left:           shell.right
                    anchors.verticalCenter: shell.verticalCenter
                    width:                  ScreenTools.defaultFontPixelWidth * 0.4
                    height:                 shell.height * 0.4
                    radius:                 width / 2
                    color:                  MLTheme.lineStrong
                }
            }

            QGCLabel {
                id:                     pctText
                anchors.left:           cell.right
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
                anchors.verticalCenter: parent.verticalCenter
                text:                   isNaN(row._pct) ? "—" : Math.round(row._pct) + "%"
                color:                  row._level >= 2 ? row._fill : MLTheme.text
                font.family:            ScreenTools.fixedFontFamily
                font.pointSize:         ScreenTools.largeFontPointSize
                font.bold:              true
            }

            Column {
                id:                     details
                anchors.right:          parent.right
                anchors.left:           pctText.right
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
                anchors.verticalCenter: parent.verticalCenter

                QGCLabel {
                    width:                  parent.width
                    horizontalAlignment:    Text.AlignRight
                    text: {
                        var v = root._v(row._b.voltage), a = root._v(row._b.current)
                        return (isNaN(v) ? "— V" : v.toFixed(1) + " V") + "   " + (isNaN(a) ? "— A" : a.toFixed(1) + " A")
                    }
                    color:                  MLTheme.text
                    font.family:            ScreenTools.fixedFontFamily
                    font.pointSize:         ScreenTools.defaultFontPointSize
                }
                QGCLabel {
                    width:                  parent.width
                    horizontalAlignment:    Text.AlignRight
                    text: {
                        var mah = root._v(row._b.mahConsumed)
                        var t   = row._b.timeRemainingStr ? row._b.timeRemainingStr.valueString : ""
                        var id  = root._batteries.count > 1 ? qsTr("배터리 %1 · ").arg(root._v(row._b.id) + 1) : ""
                        return id + (isNaN(mah) ? "" : Math.round(mah) + " mAh") + (t && t !== "--:--:--" ? "  ·  " + t : "")
                    }
                    color:                  MLTheme.dim
                    font.pointSize:         ScreenTools.smallFontPointSize
                }
            }
        }
    }
}
