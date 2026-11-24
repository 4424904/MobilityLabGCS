import QtQuick

import QGroundControl
import QGroundControl.Controls

// One telemetry value: label, live value with unit, and a range bar showing
// the normal / caution / warning zones from tandem.json with a value marker.
//
//   냉각수 온도                       92 °C
//   [=========green=========|amber|red]  ▲
//
// The row hides itself until the value has been received at least once, so the
// panel only lists what this aircraft actually reports. If the value stops
// arriving it stays visible and says so.
Item {
    id: root

    property string key
    property bool   showWhenMissing: false

    readonly property var    _t:       typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var    _spec:    _t ? _t.spec(key) : ({})
    readonly property real   _value:   { var v = _t ? _t.values[key] : undefined; return v === undefined ? NaN : v }
    readonly property int    _level:   { var l = _t ? _t.levels[key] : undefined; return l === undefined ? 0 : l }
    readonly property bool   _seen:    _t ? _t.seenKeys[key] === true : false
    readonly property bool   _lost:    _seen && isNaN(_value)
    readonly property real   _min:     _spec.min !== undefined ? _spec.min : 0
    readonly property real   _max:     _spec.max !== undefined ? _spec.max : 100
    readonly property var    _zones:   _spec.zones !== undefined ? _spec.zones : []
    readonly property real   _frac:    isNaN(_value) ? 0 : Math.max(0, Math.min(1, (_value - _min) / Math.max(1e-6, _max - _min)))

    visible:        _seen || showWhenMissing
    implicitWidth:  ScreenTools.defaultFontPixelWidth * 30
    implicitHeight: visible ? ScreenTools.defaultFontPixelHeight * 2.1 : 0

    // Warning rows get a tinted background so they stand out in a glance
    Rectangle {
        anchors.fill:       parent
        anchors.leftMargin: -ScreenTools.defaultFontPixelWidth * 0.5
        anchors.rightMargin: -ScreenTools.defaultFontPixelWidth * 0.5
        radius:             ScreenTools.defaultFontPixelWidth * 0.4
        color:              root._level === 3 ? "#40ff4f4f" : (root._level === 2 ? "#30f5b331" : "transparent")
    }

    QGCLabel {
        id:                 label
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.topMargin:  ScreenTools.defaultFontPixelHeight * 0.15
        text:               root._spec.label !== undefined ? root._spec.label : root.key
        color:              MLTheme.dim
        font.pointSize:     ScreenTools.smallFontPointSize
    }

    Row {
        anchors.right:      parent.right
        anchors.baseline:   label.baseline
        spacing:            ScreenTools.defaultFontPixelWidth * 0.4

        QGCLabel {
            text:           root._lost ? qsTr("수신 끊김") : MLTheme.formatValue(root._value, root._spec.decimals)
            color:          root._lost ? MLTheme.caution : MLTheme.levelColor(root._level)
            font.family:    root._lost ? ScreenTools.normalFontFamily : ScreenTools.fixedFontFamily
            font.pointSize: root._lost ? ScreenTools.smallFontPointSize : ScreenTools.mediumFontPointSize
            font.bold:      true
        }
        QGCLabel {
            visible:        !root._lost
            text:           root._spec.unit !== undefined ? root._spec.unit : ""
            color:          MLTheme.dim
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    // Range bar
    Item {
        id:                 bar
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        anchors.bottomMargin: ScreenTools.defaultFontPixelHeight * 0.25
        height:             Math.max(4, ScreenTools.defaultFontPixelHeight * 0.3)

        Rectangle {
            anchors.fill:   parent
            radius:         height / 2
            color:          MLTheme.panelRaised
        }

        // Zones from tandem.json
        Repeater {
            model: root._zones
            Rectangle {
                readonly property real _from: Math.max(root._min, modelData[0])
                readonly property real _to:   Math.min(root._max, modelData[1])
                x:          (_from - root._min) / Math.max(1e-6, root._max - root._min) * bar.width
                width:      Math.max(0, (_to - _from) / Math.max(1e-6, root._max - root._min) * bar.width)
                height:     bar.height
                color:      MLTheme.zoneColor(modelData[2])
                opacity:    0.75
            }
        }

        // Plain fill when an item has no zones
        Rectangle {
            visible:    root._zones.length === 0 && !isNaN(root._value)
            width:      bar.width * root._frac
            height:     bar.height
            radius:     height / 2
            color:      "#4d8fa0"
        }

        // Value marker
        Rectangle {
            visible:    root._zones.length > 0 && !isNaN(root._value)
            width:      Math.max(3, ScreenTools.defaultFontPixelWidth * 0.3)
            height:     bar.height * 2.6
            radius:     width / 2
            anchors.verticalCenter: parent.verticalCenter
            x:          Math.max(0, Math.min(bar.width - width, bar.width * root._frac - width / 2))
            color:      "white"
            border.color: "black"
            border.width: 1
        }
    }
}
