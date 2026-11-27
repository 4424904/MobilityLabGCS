import QtQuick
import QtQuick.Controls

import QGroundControl.Controls

// Small square button with a glyph (or an svg icon) and a tooltip, for panel headers and
// map tools. checked: lit in the accent colour.
Rectangle {
    id: root
    property string glyph
    property url    icon
    // glyphs used across the console map to the MOBILITY LAB line-icon set (res/icons/ui)
    readonly property var _iconOf: ({ "⤢": "fit", "◎": "target", "⌖": "follow", "★": "star", "↔": "ruler", "▱": "area", "◫": "layers",
        "+": "plus", "−": "minus", "✕": "close", "‹": "left", "›": "right", "⧉": "detach", "↻": "refresh", "⇩": "download", "↶": "undo",
        "⌫": "trash", "✓": "check", "▣": "console", "≡": "timeline", "◭": "cube", "⟲": "refresh", "🔔": "bell", "☑": "checklist",
        "☀": "sun", "☾": "moon", "▦": "layout", "⌕": "search", "⚠": "bell",
        "⚙": "gear", "?": "help", "⌨": "keyboard", "▶": "play", "⛶": "fullscreen", "⤡": "exitfull", "⛨": "shield", "∿": "pulse" })
    readonly property string _svg: icon.toString() !== "" ? icon.toString() : (_iconOf[glyph] ? "/MobilityLab/ui/" + _iconOf[glyph] + ".svg" : "")
    property string tip
    property bool   checked:    false
    property bool   enabledState: true
    property color  tone:       MLTheme.accent
    property real   size:       30 * MLTheme.u
    property string label                   // optional text after the glyph
    signal clicked()

    width:          label === "" ? size : row.implicitWidth + 20 * MLTheme.u
    height:         size
    radius:         6 * MLTheme.u
    opacity:        enabledState ? 1 : 0.4
    color:          checked ? MLTheme.alpha(tone, 0.16) : (ma.pressed ? MLTheme.pressed : (ma.containsMouse ? MLTheme.hover : "transparent"))
    border.color:   checked ? MLTheme.alpha(tone, 0.6) : "transparent"
    Behavior on color { ColorAnimation { duration: MLTheme.animFast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6 * MLTheme.u
        QGCColoredImage {
            visible:            root._svg !== ""
            anchors.verticalCenter: parent.verticalCenter
            source:             root._svg
            width:              root.size * 0.56
            height:             width
            sourceSize.height:  height * 2
            fillMode:           Image.PreserveAspectFit
            color:              root.checked ? root.tone : MLTheme.label
        }
        Text {
            visible:        root.glyph !== "" && root._svg === ""
            anchors.verticalCenter: parent.verticalCenter
            text:           root.glyph
            color:          root.checked ? root.tone : MLTheme.label
            font.family:    MLTheme.sans
            font.pixelSize: root.size * 0.52
        }
        Text {
            visible:        root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:           root.label
            color:          root.checked ? root.tone : MLTheme.text
            font.family:    MLTheme.sans
            font.pixelSize: MLTheme.fsSmall
        }
    }
    MouseArea {
        id: ma
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    root.enabledState ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked:      if (root.enabledState) root.clicked()
    }
    ToolTip.visible:    MLState.helpTips && root.tip !== "" && ma.containsMouse
    ToolTip.delay:      500
    ToolTip.text:       root.tip
}
