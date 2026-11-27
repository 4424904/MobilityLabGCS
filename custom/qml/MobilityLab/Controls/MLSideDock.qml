import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Side panel of the flight console: tab strip (choose what the panel shows), a collapse
// button, a drag handle on the inner edge to resize, and pages that are only built when
// first shown. Width and the chosen tab are saved by MLState (restored at start).
//
//   [ 계기 | 편대 ]                     ‹
//   page …
Item {
    id: root

    property string side:       "left"          // left · right
    property var    tabs:       []              // [{ key, label }]
    property string current:    tabs.length ? tabs[0].key : ""
    property bool   open:       true
    property real   openWidth:  400 * MLTheme.u
    property real   minWidth:   300 * MLTheme.u
    property real   maxWidth:   640 * MLTheme.u
    property bool   detachable: false
    default property alias pages: stack.data

    signal tabSelected(string key)
    signal closeRequested()
    signal widthDragged(real px)
    signal detachRequested()

    readonly property real u: MLTheme.u
    readonly property bool _left: side === "left"

    width:   open ? openWidth : 0
    visible: width > 1
    clip:    true
    Behavior on width { enabled: !handle.pressed; NumberAnimation { duration: MLTheme.anim; easing.type: Easing.OutCubic } }

    Rectangle {
        id:             frame
        anchors.fill:   parent
        color:          MLTheme.glass
        radius:         MLTheme.panelRadius
        border.color:   MLTheme.glassEdge

        // ---- tab strip --------------------------------------------------------
        Item {
            id:     strip
            x:      0; y: 0
            width:  root.width
            height: root.tabs.length > 1 || root.detachable ? 42 * u : 0
            visible: height > 0

            Row {
                id:                     tabRow
                anchors.left:           parent.left
                anchors.leftMargin:     10 * u
                anchors.verticalCenter: parent.verticalCenter
                spacing:                4 * u
                Repeater {
                    model: root.tabs
                    Rectangle {
                        readonly property bool on: root.current === modelData.key
                        width:  tabText.implicitWidth + 26 * u
                        height: 30 * u
                        radius: 6 * u
                        color:  on ? MLTheme.accentSoft : (tm.containsMouse ? MLTheme.hover : "transparent")
                        border.color: on ? MLTheme.alpha(MLTheme.accent, 0.55) : "transparent"
                        Behavior on color { ColorAnimation { duration: MLTheme.animFast } }
                        MLText {
                            id: tabText
                            anchors.centerIn: parent
                            text:           modelData.label
                            color:          parent.on ? MLTheme.accent : MLTheme.label
                            font.pixelSize: MLTheme.fsSmall
                            font.weight:    parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tabSelected(modelData.key) }
                    }
                }
            }
            Row {
                anchors.right:          parent.right
                anchors.rightMargin:    8 * u
                anchors.verticalCenter: parent.verticalCenter
                spacing:                2 * u
                MLIconButton {
                    visible:    root.detachable
                    glyph:      "⧉"
                    tip:        qsTr("새 창으로 분리")
                    onClicked:  root.detachRequested()
                }
                MLIconButton {
                    glyph:      root._left ? "‹" : "›"
                    tip:        qsTr("패널 접기")
                    onClicked:  root.closeRequested()
                }
            }
            Rectangle { anchors.bottom: parent.bottom; x: 10 * u; width: parent.width - 20 * u; height: 1; color: MLTheme.line }
        }

        // ---- pages -------------------------------------------------------------
        Item {
            id:             stack
            x:              0
            y:              strip.height
            width:          root.openWidth
            height:         root.height - strip.height
            onChildrenChanged: _sync()
            Component.onCompleted: _sync()
            function _sync() {
                for (var i = 0; i < children.length; i++) {
                    var c = children[i]
                    if (c.pageKey === undefined) continue
                    c.anchors.fill = stack
                    c.visible = (c.pageKey === root.current)
                }
            }
            Connections { target: root; function onCurrentChanged() { stack._sync() } }
        }
    }

    // ---- resize handle on the inner edge -------------------------------------------
    MouseArea {
        id:             handle
        width:          8 * u
        height:         parent.height
        x:              root._left ? root.width - width : 0
        cursorShape:    Qt.SplitHCursor
        hoverEnabled:   true
        preventStealing: true
        property real _startX
        property real _startW
        onPressed: (m) => { _startX = mapToItem(null, m.x, 0).x; _startW = root.openWidth }
        onPositionChanged: (m) => {
            if (!pressed) return
            var dx = mapToItem(null, m.x, 0).x - _startX
            var w = Math.max(root.minWidth, Math.min(root.maxWidth, _startW + (root._left ? dx : -dx)))
            root.widthDragged(w)
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter:   parent.verticalCenter
            width:  3 * u; height: 44 * u; radius: width / 2
            color:  handle.pressed ? MLTheme.accent : MLTheme.lineStrong
            opacity: handle.containsMouse || handle.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: MLTheme.animFast } }
        }
    }
}
