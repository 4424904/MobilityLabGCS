import QtQuick

// Section heading inside a panel: title, optional detail on the right, hairline below.
Item {
    id: root
    property string text
    property string detail
    width:  parent ? parent.width : 100
    height: 28 * MLTheme.u
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * MLTheme.u
        text: root.text
        color: MLTheme.label
        font.family: MLTheme.sans
        font.pixelSize: MLTheme.fsSmall
        font.weight: Font.DemiBold
        font.letterSpacing: 0.4 * MLTheme.u
    }
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * MLTheme.u
        text: root.detail
        color: MLTheme.dim
        font.family: MLTheme.sans
        font.pixelSize: MLTheme.fsLabel
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
}
