import QtQuick

import QGroundControl
import QGroundControl.Controls

// Compact tile for one TandemTelemetry key (label / value + unit / zone bar).
// Hidden until the aircraft has reported the value at least once, so a grid of
// these only shows what this airframe actually sends.
//
//   ┌ 냉각수 온도 ─────────┐
//   │ 92 °C               │
//   │ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▮▬▬▬  │
//   └─────────────────────┘
Rectangle {
    id: root

    property string key

    readonly property var  _t:      typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _spec:   _t ? _t.spec(key) : ({})
    readonly property real _value:  { var v = _t ? _t.values[key] : undefined; return v === undefined ? NaN : v }
    readonly property int  _level:  { var l = _t ? _t.levels[key] : undefined; return l === undefined ? 0 : l }
    readonly property bool _seen:   _t ? _t.seenKeys[key] === true : false
    readonly property bool _lost:   _seen && isNaN(_value)
    readonly property real _min:    _spec.min !== undefined ? _spec.min : 0
    readonly property real _max:    _spec.max !== undefined ? _spec.max : 100
    readonly property var  _zones:  _spec.zones !== undefined ? _spec.zones : []
    readonly property real _frac:   isNaN(_value) ? 0 : Math.max(0, Math.min(1, (_value - _min) / Math.max(1e-6, _max - _min)))

    visible:        _seen
    implicitWidth:  ScreenTools.defaultFontPixelWidth * 13
    implicitHeight: ScreenTools.defaultFontPixelHeight * 2.75
    radius:         ScreenTools.defaultFontPixelWidth * 0.4
    color:          _level === 3 ? "#3a1416" : (_level === 2 ? "#33270f" : MLTheme.tile)
    border.width:   _level >= 2 || _lost ? 1 : 0
    border.color:   _lost ? MLTheme.caution : MLTheme.levelAccent(_level)

    QGCLabel {
        id:                 labelText
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.7
        anchors.rightMargin: anchors.leftMargin
        anchors.topMargin:  ScreenTools.defaultFontPixelHeight * 0.15
        text:               root._spec.label !== undefined ? root._spec.label : root.key
        color:              MLTheme.label
        elide:              Text.ElideRight
        font.pointSize:     ScreenTools.smallFontPointSize
    }

    Row {
        anchors.left:       labelText.left
        anchors.top:        labelText.bottom
        spacing:            ScreenTools.defaultFontPixelWidth * 0.3

        QGCLabel {
            id:             valueText
            text:           root._lost ? qsTr("수신 끊김") : MLTheme.formatValue(root._value, root._spec.decimals)
            color:          root._lost ? MLTheme.caution : MLTheme.levelColor(root._level)
            font.family:    root._lost ? ScreenTools.normalFontFamily : ScreenTools.fixedFontFamily
            font.pointSize: root._lost ? ScreenTools.defaultFontPointSize : ScreenTools.mediumFontPointSize
            font.bold:      true
        }
        QGCLabel {
            anchors.baseline: valueText.baseline
            visible:        !root._lost
            text:           root._spec.unit !== undefined ? root._spec.unit : ""
            color:          MLTheme.dim
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    // Zone bar along the bottom edge
    Item {
        id:                 bar
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.7
        anchors.rightMargin: anchors.leftMargin
        anchors.bottomMargin: ScreenTools.defaultFontPixelHeight * 0.25
        height:             Math.max(3, ScreenTools.defaultFontPixelHeight * 0.18)

        Rectangle {
            anchors.fill:   parent
            radius:         height / 2
            color:          MLTheme.panelRaised
        }
        Repeater {
            model: root._zones
            Rectangle {
                readonly property real _from: Math.max(root._min, modelData[0])
                readonly property real _to:   Math.min(root._max, modelData[1])
                x:          (_from - root._min) / Math.max(1e-6, root._max - root._min) * bar.width
                width:      Math.max(0, (_to - _from) / Math.max(1e-6, root._max - root._min) * bar.width)
                height:     bar.height
                color:      MLTheme.zoneColor(modelData[2])
                opacity:    0.7
            }
        }
        Rectangle {
            visible:    root._zones.length === 0 && !isNaN(root._value)
            width:      bar.width * root._frac
            height:     bar.height
            radius:     height / 2
            color:      "#4d8fa0"
        }
        Rectangle {
            visible:    root._zones.length > 0 && !isNaN(root._value)
            width:      Math.max(3, ScreenTools.defaultFontPixelWidth * 0.3)
            height:     bar.height * 2.6
            radius:     width / 2
            anchors.verticalCenter: parent.verticalCenter
            x:          Math.max(0, Math.min(bar.width - width, bar.width * root._frac - width / 2))
            color:      "white"
        }
    }
}
