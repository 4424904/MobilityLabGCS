import QtQuick

// Section header inside a column: letter-spaced title on the left, a small
// detail on the right, hairline above (unless first).
Item {
    id: root

    property string title
    property string detail
    property color  detailColor:    MLTheme.dim
    property bool   rule:           true

    implicitHeight: 38 * MLTheme.u

    Rectangle {
        visible:        root.rule
        anchors.top:    parent.top
        width:          parent.width
        height:         1
        color:          MLTheme.line
    }
    MLText {
        anchors.left:           parent.left
        anchors.leftMargin:     20 * MLTheme.u
        anchors.bottom:         parent.bottom
        anchors.bottomMargin:   8 * MLTheme.u
        text:                   root.title
        color:                  MLTheme.label
        font.pixelSize:         MLTheme.fsSmall
        font.weight:            Font.DemiBold
        font.letterSpacing:     1.4 * MLTheme.u
    }
    Text {
        anchors.right:          parent.right
        anchors.rightMargin:    20 * MLTheme.u
        anchors.bottom:         parent.bottom
        anchors.bottomMargin:   9 * MLTheme.u
        text:                   root.detail
        color:                  root.detailColor
        font.family:            MLTheme.mono
        font.pixelSize:         MLTheme.fsLabel
    }
}
