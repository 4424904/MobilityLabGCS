import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Glare-shield style MASTER WARNING / MASTER CAUTION lamps with the active
// alert list underneath (CAS). Lamps flash until acknowledged; pressing either
// lamp acknowledges everything. The list stays while a condition is active.
Column {
    id: root

    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _alerts:     _t ? _t.alerts : []
    readonly property bool _warnLit:    _t ? _t.masterWarning : false
    readonly property bool _cautLit:    _t ? _t.masterCaution : false
    readonly property bool _warnLatched: _t ? _t.anyWarning : false
    readonly property bool _cautLatched: _t ? _t.anyCaution : false

    spacing: ScreenTools.defaultFontPixelHeight * 0.3

    component Lamp: Rectangle {
        id: lamp

        property string title
        property bool   lit:        false   // flashing, unacknowledged
        property bool   latched:    false   // acknowledged but still active
        property color  litColor
        property color  litText

        signal pressed()

        width:          ScreenTools.defaultFontPixelWidth * 13
        height:         ScreenTools.defaultFontPixelHeight * 2.4
        radius:         ScreenTools.defaultFontPixelWidth * 0.4
        color:          lit ? litColor : (latched ? Qt.rgba(litColor.r, litColor.g, litColor.b, 0.15) : MLTheme.tile)
        border.width:   Math.max(1, ScreenTools.defaultFontPixelWidth * 0.2)
        border.color:   (lit || latched) ? litColor : "#3d4e55"

        QGCLabel {
            anchors.centerIn:       parent
            horizontalAlignment:    Text.AlignHCenter
            text:                   lamp.title
            color:                  lamp.lit ? lamp.litText : (lamp.latched ? lamp.litColor : "#5f7076")
            font.pointSize:         ScreenTools.smallFontPointSize
            font.bold:              true
            lineHeight:             0.9
        }

        SequentialAnimation on opacity {
            running:    lamp.lit
            loops:      Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 1; to: 0.35; duration: 450 }
            NumberAnimation { from: 0.35; to: 1; duration: 450 }
        }

        MouseArea {
            anchors.fill:   parent
            cursorShape:    Qt.PointingHandCursor
            onClicked:      lamp.pressed()
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width:          lampRow.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2
        height:         lampRow.implicitHeight + ScreenTools.defaultFontPixelWidth * 1.2
        radius:         MLTheme.radius
        color:          MLTheme.panel
        border.color:   MLTheme.line
        border.width:   1

        Row {
            id:                 lampRow
            anchors.centerIn:   parent
            spacing:            ScreenTools.defaultFontPixelWidth

            Lamp {
                title:      "MASTER\nWARNING"
                lit:        root._warnLit
                latched:    root._warnLatched
                litColor:   MLTheme.warning
                litText:    "white"
                onPressed:  if (root._t) root._t.acknowledgeAll()
            }
            Lamp {
                title:      "MASTER\nCAUTION"
                lit:        root._cautLit
                latched:    root._cautLatched
                litColor:   MLTheme.caution
                litText:    "#1b1300"
                onPressed:  if (root._t) root._t.acknowledgeAll()
            }
        }
    }

    // Active alerts (most severe first)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        visible:        root._alerts.length > 0
        width:          ScreenTools.defaultFontPixelWidth * 44
        height:         alertColumn.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.6
        radius:         ScreenTools.defaultFontPixelWidth * 0.5
        color:          MLTheme.panel
        border.color:   MLTheme.line
        border.width:   1

        Column {
            id:                 alertColumn
            anchors.left:       parent.left
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.margins:    ScreenTools.defaultFontPixelHeight * 0.3
            spacing:            ScreenTools.defaultFontPixelHeight * 0.2

            Repeater {
                model: Math.min(5, root._alerts.length)

                Rectangle {
                    readonly property var alertItem: root._alerts[index] || ({ level: 0, text: "", time: "", acked: true })
                    width:      alertColumn.width
                    height:     ScreenTools.defaultFontPixelHeight * 1.8
                    radius:     ScreenTools.defaultFontPixelWidth * 0.3
                    color:      alertItem.acked ? "transparent" : (alertItem.level === 3 ? "#55ff4f4f" : "#45f5b331")

                    Rectangle {
                        width:  Math.max(3, ScreenTools.defaultFontPixelWidth * 0.4)
                        height: parent.height
                        color:  alertItem.level === 3 ? MLTheme.warning : MLTheme.caution
                    }
                    QGCLabel {
                        id:                     levelText
                        anchors.left:           parent.left
                        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 1.2
                        anchors.verticalCenter: parent.verticalCenter
                        text:                   alertItem.level === 3 ? qsTr("경고") : qsTr("주의")
                        color:                  alertItem.level === 3 ? MLTheme.warning : MLTheme.caution
                        font.bold:              true
                    }
                    QGCLabel {
                        anchors.left:           levelText.right
                        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
                        anchors.right:          timeText.left
                        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text:                   alertItem.text
                        color:                  MLTheme.text
                        elide:                  Text.ElideRight
                    }
                    QGCLabel {
                        id:                     timeText
                        anchors.right:          parent.right
                        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text:                   alertItem.time
                        color:                  MLTheme.dim
                        font.family:            ScreenTools.fixedFontFamily
                        font.pointSize:         ScreenTools.smallFontPointSize
                    }
                }
            }

            QGCLabel {
                visible:        root._alerts.length > 5
                text:           qsTr("외 %1건").arg(root._alerts.length - 5)
                color:          MLTheme.dim
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }
    }
}
