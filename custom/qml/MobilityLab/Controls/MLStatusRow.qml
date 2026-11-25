import QtQuick

import QGroundControl
import QGroundControl.Controls

// One line of a status list:  ● 라벨 ........ 값 단위  ▂▄▆█
// level: 0 no data, 1 normal, 2 caution, 3 warning. bars: -1 hides the
// signal-strength bars, otherwise 0..4 filled bars.
Item {
    id: root

    property string label
    property string value:  "—"
    property string unit
    property int    level:  1
    property int    bars:   -1

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 30
    implicitHeight: ScreenTools.defaultFontPixelHeight * 1.75

    readonly property color _c: MLTheme.levelAccent(level)

    Rectangle {
        id:                     dot
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        width:                  ScreenTools.defaultFontPixelHeight * 0.45
        height:                 width
        radius:                 width / 2
        color:                  root.level === 0 ? "transparent" : root._c
        border.width:           root.level === 0 ? 1 : 0
        border.color:           MLTheme.faint
    }

    QGCLabel {
        anchors.left:           dot.right
        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.8
        anchors.right:          valueRow.left
        anchors.verticalCenter: parent.verticalCenter
        text:                   root.label
        color:                  MLTheme.label
        elide:                  Text.ElideRight
    }

    Row {
        id:                     valueRow
        anchors.right:          barsItem.visible ? barsItem.left : parent.right
        anchors.rightMargin:    barsItem.visible ? ScreenTools.defaultFontPixelWidth * 0.8 : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing:                ScreenTools.defaultFontPixelWidth * 0.3

        QGCLabel {
            id:             valueText
            text:           root.value
            color:          root.level === 0 ? MLTheme.faint : (root.level === 1 ? MLTheme.text : root._c)
            font.family:    ScreenTools.fixedFontFamily
            font.bold:      true
        }
        QGCLabel {
            anchors.baseline: valueText.baseline
            visible:        root.unit !== ""
            text:           root.unit
            color:          MLTheme.dim
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    Row {
        id:                     barsItem
        visible:                root.bars >= 0
        anchors.right:          parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing:                2

        Repeater {
            model: 4
            Rectangle {
                anchors.bottom: parent.bottom
                width:          Math.max(3, ScreenTools.defaultFontPixelWidth * 0.4)
                height:         ScreenTools.defaultFontPixelHeight * (0.35 + index * 0.2)
                radius:         1
                color:          index < root.bars ? root._c : MLTheme.panelRaised
            }
        }
    }

    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        height:         1
        color:          MLTheme.line
        opacity:        0.6
    }
}
