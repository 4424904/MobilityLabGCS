import QtQuick

import QGroundControl
import QGroundControl.Controls

// Tandem rotor synchronisation display.
//
//      ( 520 )  ──── Δ 0.3 % ────  ( 518 )
//       전방                         후방
//
// Each disc spins while its rotor turns; the link between them shows the
// front/rear speed split and takes the caution/warning colour from tandem.json.
Item {
    id: root

    readonly property var  _t:      typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _values: _t ? _t.values : ({})
    readonly property var  _seenKeys: _t ? _t.seenKeys : ({})
    readonly property real _front:  _values["rot.front"] !== undefined ? _values["rot.front"] : NaN
    readonly property real _rear:   _values["rot.rear"]  !== undefined ? _values["rot.rear"]  : NaN
    readonly property real _split:  _values["rot.split"] !== undefined ? _values["rot.split"] : NaN
    readonly property int  _splitLevel: { var l = _t ? _t.levels["rot.split"] : undefined; return l === undefined ? 0 : l }
    readonly property bool _anySeen: _seenKeys["rot.front"] === true || _seenKeys["rot.rear"] === true

    readonly property real _disc:   ScreenTools.defaultFontPixelHeight * 4.6

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 30
    implicitHeight: _anySeen ? _disc + ScreenTools.defaultFontPixelHeight * 1.6 : waiting.implicitHeight + ScreenTools.defaultFontPixelHeight

    QGCLabel {
        id:                 waiting
        visible:            !root._anySeen
        anchors.centerIn:   parent
        text:               qsTr("로터 RPM 수신 대기")
        color:              MLTheme.faint
        font.pointSize:     ScreenTools.smallFontPointSize
    }

    component RotorDisc: Item {
        id: disc

        property real   rpm: NaN
        property string title
        property color  ringColor: MLTheme.ok
        property real   size: 100

        width:  disc.size
        height: disc.size + titleLabel.height

        Rectangle {
            id:             ring
            width:          disc.size
            height:         width
            radius:         width / 2
            color:          "#0c1214"
            border.width:   Math.max(2, ScreenTools.defaultFontPixelWidth * 0.35)
            border.color:   isNaN(disc.rpm) ? MLTheme.faint : disc.ringColor

            // Blades, rotating while the rotor turns
            Item {
                id:             blades
                anchors.fill:   parent
                opacity:        0.35
                Repeater {
                    model: 3
                    Rectangle {
                        width:      Math.max(2, ring.width * 0.04)
                        height:     ring.height * 0.46
                        x:          (ring.width - width) / 2
                        y:          ring.height / 2 - height
                        color:      MLTheme.dim
                        antialiasing: true
                        transform: Rotation { origin.x: width / 2; origin.y: height; angle: index * 120 }
                    }
                }
                RotationAnimator on rotation {
                    from:       0
                    to:         360
                    duration:   900
                    loops:      Animation.Infinite
                    running:    !isNaN(disc.rpm) && disc.rpm > 30
                }
            }

            Column {
                anchors.centerIn: parent
                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:           MLTheme.formatValue(disc.rpm, 0)
                    color:          MLTheme.text
                    font.family:    ScreenTools.fixedFontFamily
                    font.pointSize: ScreenTools.largeFontPointSize
                    font.bold:      true
                }
                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:           "rpm"
                    color:          MLTheme.dim
                    font.pointSize: ScreenTools.smallFontPointSize
                }
            }
        }

        QGCLabel {
            id:                         titleLabel
            anchors.top:                ring.bottom
            anchors.topMargin:          ScreenTools.defaultFontPixelHeight * 0.15
            anchors.horizontalCenter:   ring.horizontalCenter
            text:                       disc.title
            color:                      MLTheme.label
            font.pointSize:             ScreenTools.smallFontPointSize
        }
    }

    RotorDisc {
        id:             frontDisc
        visible:        root._anySeen
        anchors.left:   parent.left
        anchors.top:    parent.top
        rpm:            root._front
        title:          qsTr("전방 로터")
        size:           root._disc
        ringColor:      MLTheme.levelAccent(Math.max(1, root._splitLevel))
    }

    RotorDisc {
        id:             rearDisc
        visible:        root._anySeen
        anchors.right:  parent.right
        anchors.top:    parent.top
        rpm:            root._rear
        title:          qsTr("후방 로터")
        size:           root._disc
        ringColor:      MLTheme.levelAccent(Math.max(1, root._splitLevel))
    }

    // Link between the discs with the split value
    Item {
        visible:            root._anySeen
        anchors.left:       frontDisc.right
        anchors.right:      rearDisc.left
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.5
        anchors.rightMargin: ScreenTools.defaultFontPixelWidth * 0.5
        y:                  root._disc / 2 - height / 2
        height:             splitColumn.implicitHeight

        Rectangle {
            anchors.left:           parent.left
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            height:                 Math.max(2, ScreenTools.defaultFontPixelWidth * 0.25)
            color:                  isNaN(root._split) ? MLTheme.line : MLTheme.levelAccent(root._splitLevel)
            opacity:                0.8
        }

        Column {
            id:                 splitColumn
            anchors.centerIn:   parent

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width:          splitText.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.4
                height:         splitText.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.3
                radius:         height / 2
                color:          "#0c1214"
                border.width:   1
                border.color:   isNaN(root._split) ? MLTheme.line : MLTheme.levelAccent(root._splitLevel)

                QGCLabel {
                    id:                 splitText
                    anchors.centerIn:   parent
                    text:               "Δ " + MLTheme.formatValue(root._split, 1) + " %"
                    color:              isNaN(root._split) ? MLTheme.faint : MLTheme.levelColor(root._splitLevel)
                    font.family:        ScreenTools.fixedFontFamily
                    font.pointSize:     ScreenTools.defaultFontPointSize
                    font.bold:          true
                }
            }
            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           qsTr("전·후방 편차")
                color:          MLTheme.label
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }
    }
}
