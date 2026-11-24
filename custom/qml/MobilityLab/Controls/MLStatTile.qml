import QtQuick

import QGroundControl
import QGroundControl.Controls

// Small labelled number used in tile grids (GPS, link, vibration ...)
Rectangle {
    id: root

    property string label
    property string value:  "—"
    property string unit
    property int    level:  1       // 0 no data, 1 normal, 2 caution, 3 warning

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 10
    implicitHeight: col.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.6
    radius:         ScreenTools.defaultFontPixelWidth * 0.5
    color:          root.level === 3 ? "#3a1416" : (root.level === 2 ? "#33270f" : MLTheme.tile)
    border.width:   root.level >= 2 ? 1 : 0
    border.color:   MLTheme.levelAccent(root.level)

    Column {
        id:                 col
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.8
        anchors.verticalCenter: parent.verticalCenter

        QGCLabel {
            width:          parent.width
            text:           root.label
            color:          MLTheme.label
            elide:          Text.ElideRight
            font.pointSize: ScreenTools.smallFontPointSize
        }
        Row {
            spacing: ScreenTools.defaultFontPixelWidth * 0.3
            QGCLabel {
                id:             valueLabel
                text:           root.value
                color:          root.level === 0 ? MLTheme.faint : MLTheme.levelColor(root.level)
                font.family:    ScreenTools.fixedFontFamily
                font.pointSize: ScreenTools.mediumFontPointSize
                font.bold:      true
            }
            QGCLabel {
                anchors.baseline: valueLabel.baseline
                text:           root.unit
                color:          MLTheme.dim
                font.pointSize: ScreenTools.smallFontPointSize
            }
        }
    }
}
