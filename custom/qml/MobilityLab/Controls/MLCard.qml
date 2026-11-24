import QtQuick

import QGroundControl
import QGroundControl.Controls

// Glass card used for every overlay panel: title row (optional collapse),
// then content placed in `contentItem`'s default slot.
//
//   ┌──────────────────────────────────┐
//   │ Title                 detail   ▾ │
//   │──────────────────────────────────│
//   │ content                          │
//   └──────────────────────────────────┘
Rectangle {
    id: root

    property string title
    property string detail
    property color  detailColor:    MLTheme.dim
    property bool   collapsible:    true
    property bool   collapsed:      false
    property real   padding:        ScreenTools.defaultFontPixelWidth * 1.2
    property alias  headerExtra:    headerExtraSlot.data

    default property alias content: body.data

    color:          MLTheme.panel
    radius:         MLTheme.radius
    border.color:   MLTheme.line
    border.width:   1
    clip:           true

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 36
    implicitHeight: header.height + (collapsed ? 0 : body.childrenRect.height + padding * 1.4)

    Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Item {
        id:             header
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.top:    parent.top
        height:         ScreenTools.defaultFontPixelHeight * 2.3

        QGCLabel {
            id:                     titleLabel
            anchors.left:           parent.left
            anchors.leftMargin:     root.padding
            anchors.verticalCenter: parent.verticalCenter
            text:                   root.title
            color:                  MLTheme.text
            font.pointSize:         ScreenTools.defaultFontPointSize
            font.bold:              true
        }

        Row {
            id:                     headerExtraSlot
            anchors.left:           titleLabel.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing:                ScreenTools.defaultFontPixelWidth * 0.6
        }

        QGCLabel {
            anchors.right:          chevron.visible ? chevron.left : parent.right
            anchors.rightMargin:    chevron.visible ? ScreenTools.defaultFontPixelWidth * 0.4 : root.padding
            anchors.left:           headerExtraSlot.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment:    Text.AlignRight
            elide:                  Text.ElideRight
            text:                   root.detail
            color:                  root.detailColor
            font.pointSize:         ScreenTools.smallFontPointSize
        }

        QGCColoredImage {
            id:                     chevron
            visible:                root.collapsible
            anchors.right:          parent.right
            anchors.rightMargin:    root.padding * 0.6
            anchors.verticalCenter: parent.verticalCenter
            width:                  ScreenTools.defaultFontPixelHeight * 1.2
            height:                 width
            source:                 "/MobilityLab/icons/collapse.svg"
            color:                  MLTheme.dim
            rotation:               root.collapsed ? -90 : 0
            Behavior on rotation { NumberAnimation { duration: 140 } }
        }

        MouseArea {
            anchors.fill:   parent
            enabled:        root.collapsible
            cursorShape:    root.collapsible ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked:      root.collapsed = !root.collapsed
        }
    }

    Rectangle {
        anchors.left:           parent.left
        anchors.right:          parent.right
        anchors.top:            header.bottom
        anchors.leftMargin:     root.padding
        anchors.rightMargin:    root.padding
        height:                 1
        color:                  MLTheme.line
        visible:                !root.collapsed
    }

    Item {
        id:                 body
        visible:            !root.collapsed
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        header.bottom
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.topMargin:  root.padding * 0.7
        height:             childrenRect.height
    }
}
