pragma Singleton

import QtQuick
import QtCore

// 기체 프로필 (v1.2): what the GCS shows for each system id — name, airframe type for the 3D model
// and the type label, colour, the information shown on its card, notes. Stored in this PC's settings
// only. Applying a profile NEVER writes a flight-controller parameter or sends anything to the
// vehicle; the FC's own settings stay in QGC's vehicle setup.
QtObject {
    id: root
    // sysid (string) → { name, type: "auto"|"multi"|"heli"|"tandem"|"fixed", color: "" | "#RRGGBB", notes, card: "full"|"compact" }
    property var map: ({})
    property string _json: ""
    property Settings _s: Settings { category: "MLProfiles"; property alias json: root._json }
    Component.onCompleted: { try { map = _json ? JSON.parse(_json) : ({}) } catch (e) { map = ({}) } }
    function _save() { _json = JSON.stringify(map) }

    readonly property var types: [
        { k: "auto",   t: qsTr("자동 (FC 보고)") },
        { k: "multi",  t: qsTr("멀티콥터") },
        { k: "heli",   t: qsTr("무인헬기") },
        { k: "tandem", t: qsTr("탠덤 헬기") },
        { k: "fixed",  t: qsTr("고정익") }
    ]
    function get(sysid) { var p = map[String(sysid)]; return p ? p : ({}) }
    function set(sysid, fields) {
        var m = Object.assign({}, map), p = Object.assign({}, m[String(sysid)] || ({}))
        for (var k in fields) p[k] = fields[k]
        m[String(sysid)] = p
        map = m
        _save()
    }
    function clear(sysid) { var m = Object.assign({}, map); delete m[String(sysid)]; map = m; _save() }
    function nameFor(sysid) { var p = map[String(sysid)]; return p && p.name ? p.name : "" }
    function colorFor(sysid) { var p = map[String(sysid)]; return p && p.color ? p.color : "" }
    // model type for the 3D view: the profile, otherwise what the FC reports (QGC vehicle type)
    function typeFor(sysid, qgcTypeString) {
        var p = map[String(sysid)]
        if (p && p.type && p.type !== "auto") return p.type
        var s = String(qgcTypeString || "").toLowerCase()
        if (s.indexOf("helicopter") >= 0) return "heli"
        if (s.indexOf("fixed") >= 0 || s.indexOf("plane") >= 0 || s.indexOf("vtol") >= 0) return "fixed"
        return "multi"
    }
    function typeName(k) { for (var i = 0; i < types.length; i++) if (types[i].k === k) return types[i].t; return "" }
}
