import QtQuick

import QGroundControl
import QGroundControl.Controls

// 항목 · 최근 10분 · 값 — a small table of the values worth watching, each
// with a sparkline of the last ten minutes (one sample every 6 s), so a slow
// rise shows before it turns into a caution.
// Engine aircraft: coolant / oil / cylinder head / exhaust / gearbox.
// Others: battery voltage and current, vibration, altitude.
Column {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property real u:       MLTheme.u
    readonly property var  _t:      typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _seen:   _t ? _t.seenKeys : ({})

    function fv(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined || v === null) ? NaN : Number(v)
    }
    function battery(field) {
        if (!vehicle || !vehicle.batteries || vehicle.batteries.count === 0) return NaN
        var b = vehicle.batteries.get(0)
        return b ? fv(b[field]) : NaN
    }

    // Row definitions: id, label, unit, decimals, read(), level()
    readonly property var rows: {
        var list = []
        var keys = [ "coolant", "oil.temp", "eng.cht", "eng.egt", "gb.rear", "gb.front" ]
        for (var i = 0; i < keys.length && list.length < 5; i++) {
            var k = keys[i]
            if (_seen[k] === true) {
                var spec = _t.spec(k)
                list.push({ id: k, label: spec.label || k, unit: spec.unit || "", dec: spec.decimals || 0, tandem: true })
            }
        }
        if (list.length === 0 && vehicle) {
            list.push({ id: "batV", label: qsTr("배터리 전압"), unit: "V",    dec: 1 })
            list.push({ id: "batA", label: qsTr("배터리 전류"), unit: "A",    dec: 1 })
            list.push({ id: "vib",  label: qsTr("진동"),       unit: "m/s²", dec: 0 })
            list.push({ id: "alt",  label: qsTr("고도"),       unit: "m",    dec: 0 })
        }
        return list
    }

    function read(row) {
        if (row.tandem) { var v = _t.values[row.id]; return v === undefined ? NaN : v }
        if (!vehicle) return NaN
        if (row.id === "batV") return battery("voltage")
        if (row.id === "batA") return battery("current")
        if (row.id === "vib")  return Math.max(fv(vehicle.vibration.xAxis), fv(vehicle.vibration.yAxis), fv(vehicle.vibration.zAxis))
        if (row.id === "alt")  return fv(vehicle.altitudeRelative)
        return NaN
    }
    function level(row) {
        if (row.tandem) { var l = _t.levels[row.id]; return l === undefined ? 1 : l }
        if (row.id === "vib") { var vb = read(row); return vb > 60 ? 3 : (vb > 30 ? 2 : 1) }
        return 1
    }

    property var  _history: ({})
    property int  _rev:     0
    onVehicleChanged: { _history = ({}); _rev++ }

    Timer {
        interval:       6000
        running:        true
        repeat:         true
        triggeredOnStart: true
        onTriggered: {
            var h = root._history
            for (var i = 0; i < root.rows.length; i++) {
                var r = root.rows[i], v = root.read(r)
                if (!h[r.id]) h[r.id] = []
                if (!isNaN(v)) { h[r.id].push(v); if (h[r.id].length > 100) h[r.id].shift() }
            }
            root._rev++
        }
    }

    // header
    Item {
        width:  root.width
        height: 26 * u
        MLText { x: 20 * u; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * u; text: qsTr("항목"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
        MLText { x: 128 * u; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * u; text: qsTr("최근 10분"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
        MLText { anchors.right: parent.right; anchors.rightMargin: 20 * u; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * u; text: qsTr("값"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
    }

    Repeater {
        model: root.rows

        Item {
            id: row
            required property var modelData
            readonly property real _value: { root._rev; return root.read(modelData) }
            readonly property int  _level: { root._rev; return root.level(modelData) }
            readonly property color _fg:   _level >= 2 ? MLTheme.levelColor(_level) : MLTheme.text

            width:  root.width
            height: 30 * u

            MLText {
                x:                      20 * u
                width:                  100 * u
                anchors.verticalCenter: parent.verticalCenter
                text:                   row.modelData.label
                color:                  row._level >= 2 ? row._fg : MLTheme.label
                font.pixelSize:         MLTheme.fsSmall
            }
            Canvas {
                id:                     spark
                x:                      128 * u
                width:                  parent.width - 128 * u - 112 * u
                height:                 20 * u
                anchors.verticalCenter: parent.verticalCenter
                readonly property int rev: root._rev
                onRevChanged:   requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d")
                    c.reset()
                    var pts = root._history[row.modelData.id] || []
                    if (pts.length < 2) {
                        c.strokeStyle = "#1B2026"; c.lineWidth = 1
                        c.beginPath(); c.moveTo(0, height / 2); c.lineTo(width, height / 2); c.stroke()
                        return
                    }
                    var lo = Math.min.apply(null, pts), hi = Math.max.apply(null, pts)
                    if (hi - lo < 1e-6) { lo -= 1; hi += 1 }
                    var pad = (hi - lo) * 0.15; lo -= pad; hi += pad
                    var n = 100
                    c.strokeStyle = row._level >= 2 ? String(row._fg) : "#7D848D"
                    c.lineWidth = 1.4 * MLTheme.u
                    c.beginPath()
                    for (var i = 0; i < pts.length; i++) {
                        var x = width - (pts.length - 1 - i) * width / (n - 1)
                        var y = height - (pts[i] - lo) / (hi - lo) * height
                        if (i === 0) c.moveTo(x, y); else c.lineTo(x, y)
                    }
                    c.stroke()
                }
            }
            MLNum {
                anchors.right:          parent.right
                anchors.rightMargin:    20 * u
                anchors.verticalCenter: parent.verticalCenter
                text:                   MLTheme.formatValue(row._value, row.modelData.dec)
                unit:                   isNaN(row._value) ? "" : row.modelData.unit
                color:                  row._fg
            }
            Rectangle { anchors.bottom: parent.bottom; x: 20 * u; width: parent.width - 40 * u; height: 1; color: MLTheme.hair }
        }
    }
}
