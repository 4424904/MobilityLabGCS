import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Command button. tone: "normal" | "go" | "caution" | "active" (cyan) | "danger"
//
// Safety: with `twoStep` (default) the first press only arms the button — it
// fills with its colour, reads "한 번 더 누르면 실행" and a 3 s bar runs out —
// and the command is sent on the second press. Letting the bar run out
// cancels. (Deliberately not an OS double-click, which can happen by accident
// and gives no moment to read what is about to be sent.)
Rectangle {
    id: root

    property string text
    property string subText
    property string iconSource
    property string tone:           "normal"
    property string disabledReason
    property bool   available:      true
    property bool   twoStep:        true
    property int    confirmMs:      3000
    property bool   compact:        false
    property bool   selected:       false   // toggle buttons (e.g. 목표 조정 open)

    readonly property bool pending: _pending
    signal clicked()

    property bool _pending: false

    readonly property color _toneColor: tone === "go" ? MLTheme.active
                                       : tone === "caution" ? MLTheme.caution
                                       : tone === "active" ? MLTheme.accent
                                       : tone === "danger" ? MLTheme.warning
                                       : MLTheme.text
    readonly property bool _plain: tone === "normal"
    readonly property bool _hover: mouse.containsMouse && available

    function cancel() { _pending = false; countdown.stop() }
    onAvailableChanged: if (!available) cancel()
    onVisibleChanged:   if (!visible) cancel()

    implicitWidth:  Math.max((compact ? 88 : 132) * MLTheme.u, content.implicitWidth + (compact ? 20 : 28) * MLTheme.u)
    implicitHeight: (compact ? 38 : 52) * MLTheme.u

    radius:         MLTheme.radius
    color: {
        if (!available) return "#0D1115"
        if (_pending)   return Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.22)
        if (selected)   return Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.12)
        if (mouse.pressed) return "#1A2129"
        if (_hover)     return "#151B21"
        return _plain ? "#11161B" : Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, 0.06)
    }
    border.width:   _pending ? 2 : 1
    border.color:   !available ? MLTheme.line : (_pending ? _toneColor : (_plain ? (_hover ? "#3A4450" : MLTheme.lineStrong) : Qt.rgba(_toneColor.r, _toneColor.g, _toneColor.b, _hover || selected ? 0.9 : 0.45)))
    opacity:        available ? 1 : 0.45
    clip:           true

    Column {
        id:                 content
        anchors.centerIn:   parent
        spacing:            1
        MLText {
            anchors.horizontalCenter: parent.horizontalCenter
            text:               root.text
            color:              !root.available ? MLTheme.dim : (root._plain ? MLTheme.text : root._toneColor)
            font.pixelSize:     root.compact ? MLTheme.fsBody : MLTheme.fsValue
            font.weight:        Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible:            root._pending || (root.subText !== "" && !root.compact)
            text:               root._pending ? qsTr("한 번 더 누르면 실행") : root.subText
            color:              root._pending ? MLTheme.bright : MLTheme.dim
            font.family:        root._pending ? MLTheme.sans : MLTheme.mono
            font.pixelSize:     MLTheme.fsLabel - 1
        }
    }

    // countdown while waiting for the second press
    Rectangle {
        id:             countdownBar
        visible:        root._pending
        anchors.left:   parent.left
        anchors.bottom: parent.bottom
        height:         2 * MLTheme.u
        color:          root._toneColor
        width:          0
    }
    NumberAnimation { id: countdownAnim; target: countdownBar; property: "width"; from: root.width; to: 0; duration: root.confirmMs }
    Timer { id: countdown; interval: root.confirmMs; onTriggered: root._pending = false }

    MouseArea {
        id:             mouse
        anchors.fill:   parent
        hoverEnabled:   true
        cursorShape:    root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (!root.available) return
            if (!root.twoStep) { root.clicked(); return }
            if (root._pending) { root.cancel(); root.clicked() }
            else { root._pending = true; countdown.restart(); countdownAnim.restart() }
        }
    }

    ToolTip.visible:    mouse.containsMouse && !root.available && root.disabledReason !== ""
    ToolTip.text:       root.disabledReason
    ToolTip.delay:      400
}
