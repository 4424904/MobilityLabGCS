import QtQuick

import QGroundControl
import QGroundControl.Controls

// Round dial (240°): dark track, tick marks, red limit band from the
// warning zone, value arc (grey when normal, amber/red when not), number in
// the middle and the name underneath. Drawn in a 132 × 100 design box.
// Bind `key` (TandemTelemetry value with zones from tandem.json) or set
// value/min/max/zones directly.
Item {
    id: root

    property string key
    property string title
    property string unitText:   "RPM"
    property real   value:      _keyValue
    property real   min:        _spec.min !== undefined ? _spec.min : 0
    property real   max:        _spec.max !== undefined ? _spec.max : 100
    property var    zones:      _spec.zones !== undefined ? _spec.zones : []
    property int    decimals:   _spec.decimals !== undefined ? _spec.decimals : 0
    property int    level:      _keyLevel
    property real   size:       132 * MLTheme.u

    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _spec:       (_t && key !== "") ? _t.spec(key) : ({})
    readonly property real _keyValue:   { var v = (_t && key !== "") ? _t.values[key] : undefined; return v === undefined ? NaN : v }
    readonly property int  _keyLevel:   { var l = (_t && key !== "") ? _t.levels[key] : undefined; return l === undefined ? (isNaN(value) ? 0 : 1) : l }
    readonly property color _color:     level === 3 ? MLTheme.warning : (level === 2 ? MLTheme.caution : String(MLTheme.label))

    implicitWidth:  size
    implicitHeight: size * 100 / 132 + titleText.implicitHeight

    onValueChanged: dial.requestPaint()
    onLevelChanged: dial.requestPaint()
    onZonesChanged: dial.requestPaint()
    onSizeChanged:  dial.requestPaint()

    Canvas {
        id:             dial
        width:          root.size
        height:         root.size * 100 / 132
        antialiasing:   true

        onPaint: {
            var c = getContext("2d")
            c.reset()
            var k = width / 132
            c.scale(k, k)
            var cx = 66, cy = 56, R = 48
            var a0 = 150 * Math.PI / 180, sweep = 240 * Math.PI / 180
            function frac(v) { return Math.max(0, Math.min(1, (v - root.min) / Math.max(1e-6, root.max - root.min))) }
            function ang(v) { return a0 + sweep * frac(v) }

            c.lineCap = "butt"
            c.lineWidth = 7; c.strokeStyle = String(MLTheme.line)
            c.beginPath(); c.arc(cx, cy, R, a0, a0 + sweep); c.stroke()

            // limit band (caution amber-dark, warning red) outside the track
            for (var i = 0; i < root.zones.length; i++) {
                var z = root.zones[i]
                if (z[2] === "normal") continue
                c.strokeStyle = z[2] === "warning" ? String(MLTheme.alpha(MLTheme.warning, 0.6)) : String(MLTheme.alpha(MLTheme.caution, 0.55))
                c.lineWidth = 3
                c.beginPath(); c.arc(cx, cy, R + 5, ang(z[0]), ang(Math.min(z[1], root.max))); c.stroke()
            }

            c.strokeStyle = String(MLTheme.faint); c.lineWidth = 1.2
            for (var t = 0; t <= 10; t++) {
                var ta = a0 + sweep * t / 10, r2 = t % 5 === 0 ? 32 : 35
                c.beginPath(); c.moveTo(cx + Math.cos(ta) * 40, cy + Math.sin(ta) * 40); c.lineTo(cx + Math.cos(ta) * r2, cy + Math.sin(ta) * r2); c.stroke()
            }

            if (isNaN(root.value)) return
            c.lineWidth = 7; c.strokeStyle = root._color
            c.beginPath(); c.arc(cx, cy, R, a0, ang(root.value)); c.stroke()
            var va = ang(root.value)
            c.strokeStyle = String(MLTheme.bright); c.lineWidth = 2
            c.beginPath(); c.moveTo(cx + Math.cos(va) * (R - 4), cy + Math.sin(va) * (R - 4)); c.lineTo(cx + Math.cos(va) * (R + 4), cy + Math.sin(va) * (R + 4)); c.stroke()
        }
    }

    Column {
        anchors.horizontalCenter:   dial.horizontalCenter
        y:                          dial.height * 0.42
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           MLTheme.formatValue(root.value, root.decimals)
            color:          isNaN(root.value) ? MLTheme.faint : (root.level >= 2 ? root._color : MLTheme.bright)
            font.family:    MLTheme.mono
            font.pixelSize: 21 * root.size / 132
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           root.unitText
            color:          MLTheme.dim
            font.family:    MLTheme.mono
            font.pixelSize: 10 * root.size / 132
        }
    }

    MLText {
        id:                         titleText
        anchors.top:                dial.bottom
        anchors.topMargin:          -4 * MLTheme.u
        anchors.horizontalCenter:   dial.horizontalCenter
        text:                       root.title !== "" ? root.title : (root._spec.label !== undefined ? root._spec.label : "")
        color:                      MLTheme.label
        font.pixelSize:             MLTheme.fsSmall
    }
}
