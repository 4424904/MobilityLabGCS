import QtQuick

import QGroundControl
import QGroundControl.Controls

// Round dial (240° arc) for RPM-type values: zone colours on the outer rim,
// a filled value arc with a needle, the number in the middle and a title below.
//
//        ╭───────╮
//      ╱  5,448   ╲
//     │    rpm     │
//          엔진
//
// Bind either `key` (TandemTelemetry value with zones from tandem.json) or
// value/min/max directly.
Item {
    id: root

    property string key
    property string title
    property real   value:      _keyValue
    property real   min:        _spec.min !== undefined ? _spec.min : 0
    property real   max:        _spec.max !== undefined ? _spec.max : 100
    property var    zones:      _spec.zones !== undefined ? _spec.zones : []
    property string unit:       _spec.unit !== undefined ? _spec.unit : ""
    property int    decimals:   _spec.decimals !== undefined ? _spec.decimals : 0
    property int    level:      _keyLevel
    property real   size:       ScreenTools.defaultFontPixelHeight * 6

    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _spec:       (_t && key !== "") ? _t.spec(key) : ({})
    readonly property real _keyValue:   { var v = (_t && key !== "") ? _t.values[key] : undefined; return v === undefined ? NaN : v }
    readonly property int  _keyLevel:   { var l = (_t && key !== "") ? _t.levels[key] : undefined; return l === undefined ? (isNaN(value) ? 0 : 1) : l }
    readonly property color _color:     level === 3 ? MLTheme.warning : (level === 2 ? MLTheme.caution : MLTheme.ok)

    implicitWidth:  size
    implicitHeight: size * 0.86 + titleText.implicitHeight

    onValueChanged: dial.requestPaint()
    onLevelChanged: dial.requestPaint()
    onZonesChanged: dial.requestPaint()

    Canvas {
        id:             dial
        width:          root.size
        height:         root.size * 0.86
        antialiasing:   true
        onWidthChanged: requestPaint()

        onPaint: {
            var c = getContext("2d")
            c.reset()
            var W = width, cx = W / 2, cy = W / 2, R = W / 2 - Math.max(3, W * 0.05)
            var a0 = 150 * Math.PI / 180, sweep = 240 * Math.PI / 180
            function ang(v) { return a0 + sweep * Math.max(0, Math.min(1, (v - root.min) / Math.max(1e-6, root.max - root.min))) }

            // track
            c.lineCap = "butt"
            c.lineWidth = Math.max(4, W * 0.075)
            c.strokeStyle = "#18232c"
            c.beginPath(); c.arc(cx, cy, R - c.lineWidth / 2, a0, a0 + sweep); c.stroke()

            // zones on the outer rim
            var zw = Math.max(2, W * 0.025)
            for (var i = 0; i < root.zones.length; i++) {
                var z = root.zones[i]
                c.strokeStyle = z[2] === "warning" ? "#ff4f4f" : (z[2] === "caution" ? "#f5b331" : "#2c7a4c")
                c.lineWidth = zw
                c.beginPath(); c.arc(cx, cy, R + zw * 0.2, ang(z[0]), ang(z[1])); c.stroke()
            }

            // ticks
            c.strokeStyle = "#5f7076"; c.lineWidth = 1
            for (var t = 0; t <= 10; t++) {
                var ta = a0 + sweep * t / 10
                var r1 = R - W * 0.16, r2 = R - W * (t % 5 === 0 ? 0.22 : 0.19)
                c.beginPath(); c.moveTo(cx + Math.cos(ta) * r1, cy + Math.sin(ta) * r1); c.lineTo(cx + Math.cos(ta) * r2, cy + Math.sin(ta) * r2); c.stroke()
            }

            if (isNaN(root.value)) return

            // value arc
            var lw = Math.max(4, W * 0.075)
            c.strokeStyle = root._color; c.lineWidth = lw; c.lineCap = "round"
            c.beginPath(); c.arc(cx, cy, R - lw / 2, a0, ang(root.value)); c.stroke()

            // needle
            var va = ang(root.value)
            c.strokeStyle = "white"; c.lineWidth = Math.max(2, W * 0.02); c.lineCap = "round"
            c.beginPath()
            c.moveTo(cx + Math.cos(va) * R * 0.5, cy + Math.sin(va) * R * 0.5)
            c.lineTo(cx + Math.cos(va) * (R - lw * 0.2), cy + Math.sin(va) * (R - lw * 0.2))
            c.stroke()
        }
    }

    Column {
        anchors.horizontalCenter:   dial.horizontalCenter
        y:                          dial.width / 2 - height / 2

        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           MLTheme.formatValue(root.value, root.decimals)
            color:          isNaN(root.value) ? MLTheme.faint : (root.level >= 2 ? root._color : MLTheme.text)
            font.family:    ScreenTools.fixedFontFamily
            font.pointSize: root.size > ScreenTools.defaultFontPixelHeight * 6 ? ScreenTools.largeFontPointSize : ScreenTools.mediumFontPointSize
            font.bold:      true
        }
        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           root.unit
            color:          MLTheme.dim
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    QGCLabel {
        id:                         titleText
        anchors.top:                dial.bottom
        anchors.horizontalCenter:   dial.horizontalCenter
        text:                       root.title !== "" ? root.title : (root._spec.label !== undefined ? root._spec.label : "")
        color:                      MLTheme.label
        font.pointSize:             ScreenTools.smallFontPointSize
        font.bold:                  true
    }
}
