import QtQuick

import QGroundControl
import QGroundControl.Controls

// Fixed-size console panel: header strip (Korean title, small English tag,
// optional extras, right-aligned detail) and a clipped body that the content
// fills. Used for every block of the single-screen console.
//
//   ┌ 추진 계통  PROPULSION ─────────────── 임계값 임시 ┐
//   │ content                                          │
//   └──────────────────────────────────────────────────┘
Rectangle {
    id: root

    property string title
    property string tag
    property string detail
    property color  detailColor:    MLTheme.dim
    property real   padding:        ScreenTools.defaultFontPixelWidth * 1.1
    property alias  headerExtra:    extraRow.data
    readonly property alias body:   bodyItem

    default property alias content: bodyItem.data

    color:          MLTheme.panelSolid
    radius:         ScreenTools.defaultFontPixelWidth * 0.5
    border.color:   MLTheme.line
    border.width:   1
    clip:           true

    Rectangle {
        id:             header
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.top:    parent.top
        anchors.margins: 1
        height:         ScreenTools.defaultFontPixelHeight * 1.9
        color:          MLTheme.panelHeader
        radius:         root.radius

        // square off the bottom corners of the header strip
        Rectangle {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            height:         parent.radius
            color:          parent.color
        }

        Rectangle {
            id:                     accentBar
            anchors.left:           parent.left
            anchors.leftMargin:     root.padding * 0.6
            anchors.verticalCenter: parent.verticalCenter
            width:                  Math.max(2, ScreenTools.defaultFontPixelWidth * 0.25)
            height:                 parent.height * 0.42
            radius:                 width / 2
            color:                  MLTheme.accent
        }

        QGCLabel {
            id:                     titleLabel
            anchors.left:           accentBar.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.7
            anchors.verticalCenter: parent.verticalCenter
            text:                   root.title
            color:                  MLTheme.text
            font.bold:              true
        }

        QGCLabel {
            id:                     tagLabel
            anchors.left:           titleLabel.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.7
            anchors.baseline:       titleLabel.baseline
            visible:                root.tag !== ""
            text:                   root.tag
            color:                  MLTheme.faint
            font.pointSize:         ScreenTools.smallFontPointSize
            font.letterSpacing:     1
        }

        Row {
            id:                     extraRow
            anchors.left:           tagLabel.visible ? tagLabel.right : titleLabel.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing:                ScreenTools.defaultFontPixelWidth * 0.6
        }

        QGCLabel {
            anchors.left:           extraRow.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.right:          parent.right
            anchors.rightMargin:    root.padding
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment:    Text.AlignRight
            elide:                  Text.ElideRight
            text:                   root.detail
            color:                  root.detailColor
            font.pointSize:         ScreenTools.smallFontPointSize
            font.bold:              true
        }
    }

    Item {
        id:                 bodyItem
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        header.bottom
        anchors.bottom:     parent.bottom
        anchors.margins:    root.padding
        anchors.topMargin:  root.padding * 0.8
    }
}
