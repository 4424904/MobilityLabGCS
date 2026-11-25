import QtQuick

// Numbers: IBM Plex Mono (tabular), with an optional unit in smaller grey.
Row {
    id: root

    property string text
    property string unit
    property color  color:      MLTheme.text
    property real   size:       MLTheme.fsValue
    property bool   bold:       false

    spacing: 3 * MLTheme.u

    Text {
        id:                 value
        text:               root.text
        color:              root.color
        font.family:        MLTheme.mono
        font.pixelSize:     root.size
        font.weight:        root.bold ? Font.Medium : Font.Normal
        textFormat:         Text.PlainText
    }
    Text {
        anchors.baseline:   value.baseline
        visible:            root.unit !== ""
        text:               root.unit
        color:              MLTheme.dim
        font.family:        MLTheme.sans
        font.pixelSize:     MLTheme.fsLabel
        textFormat:         Text.PlainText
    }
}
