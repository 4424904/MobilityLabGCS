import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Section title inside the systems panel: "엔진 · ECU ............ ROTAX 916 iS"
Item {
    id: root

    property string title
    property string detail
    property color  detailColor: MLTheme.dim

    implicitHeight: ScreenTools.defaultFontPixelHeight * 1.9
    implicitWidth:  ScreenTools.defaultFontPixelWidth * 30

    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.top:    parent.top
        height:         1
        color:          MLTheme.line
    }

    QGCLabel {
        id:                     titleLabel
        anchors.left:           parent.left
        anchors.bottom:         parent.bottom
        anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 0.2
        text:                   root.title
        color:                  MLTheme.accent
        font.pointSize:         ScreenTools.defaultFontPointSize
        font.bold:              true
    }

    QGCLabel {
        anchors.right:          parent.right
        anchors.left:           titleLabel.right
        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
        anchors.baseline:       titleLabel.baseline
        horizontalAlignment:    Text.AlignRight
        elide:                  Text.ElideRight
        text:                   root.detail
        color:                  root.detailColor
        font.pointSize:         ScreenTools.smallFontPointSize
    }
}
