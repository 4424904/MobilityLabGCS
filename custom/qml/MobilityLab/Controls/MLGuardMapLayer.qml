import QtQuick
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls

// ACACT Guard state drawn on the fly-view map: the demo area, each drone's
// safety ring (half of D_SAFE, so two rings touching = guard threshold),
// a 3 s velocity vector, and a line with the distance between every pair the
// guard is watching (grey normal · amber predicted conflict · red emergency).
// Map items are created once (fixed pools) and only re-bound on updates.
Item {
    id: root

    property var map

    readonly property bool   _on:       typeof mlGuard !== "undefined" && mlGuard.active
    readonly property var    _drones:   _on ? mlGuard.drones : []
    readonly property var    _pairs:    _on ? mlGuard.pairs : []
    readonly property var    _site:     _on ? mlGuard.site : ({})
    readonly property real   _dSafe:    _on && mlGuard.config.d_safe ? mlGuard.config.d_safe : 10
    readonly property real   u:         MLTheme.u

    function _byId(id) {
        for (var i = 0; i < _drones.length; i++) if (_drones[i].id === id) return _drones[i]
        return null
    }
    function _coord(d) {
        return (d && d.lat !== null && d.lat !== undefined && d.lon !== null) ? QtPositioning.coordinate(d.lat, d.lon) : QtPositioning.coordinate()
    }
    function _levelColor(level) { return level >= 2 ? MLTheme.warning : (level === 1 ? MLTheme.caution : String(MLTheme.dim)) }

    // demo area
    property var _area: MapCircle {
        visible:        root._on && !!root._site && root._site.lat !== undefined && root._site.lat !== null
        center:         visible ? QtPositioning.coordinate(root._site.lat, root._site.lon) : QtPositioning.coordinate()
        radius:         root._site && root._site.radius ? root._site.radius : 25
        color:          "transparent"
        border.color:   String(MLTheme.alpha(MLTheme.accent, 0.4))
        border.width:   1
    }

    Instantiator {
        model: 4
        delegate: QtObject {
            id: dslot
            readonly property int  slot:    index
            readonly property var  d:       slot < root._drones.length ? root._drones[slot] : null
            readonly property var  c:       root._coord(d)
            readonly property bool ok:      !!d && c.isValid
            readonly property color col:    d ? MLTheme.vehicleColor(d.sysid) : "white"
            readonly property bool own:     !!d && d.own
            readonly property bool lost:    !!d && !d.fresh

            property var ring: MapCircle {
                visible:        dslot.ok
                center:         dslot.c
                radius:         root._dSafe / 2
                color:          dslot.own ? String(MLTheme.alpha(MLTheme.warning, 0.19)) : MLTheme.alpha(MLTheme.text, 0.08)
                border.color:   dslot.lost ? String(MLTheme.alpha(MLTheme.warning, 0.6)) : (dslot.own ? MLTheme.warning : dslot.col)
                border.width:   dslot.own ? 2.5 : 1.5
                opacity:        dslot.lost ? 0.5 : 1
            }
            property var vec: MapPolyline {
                visible:        dslot.ok && Math.hypot(dslot.d.vn, dslot.d.ve) > 0.3
                line.width:     3
                line.color:     dslot.col
                path: {
                    if (!dslot.ok) return []
                    var sp = Math.hypot(dslot.d.vn, dslot.d.ve)
                    var az = (Math.atan2(dslot.d.ve, dslot.d.vn) * 180 / Math.PI + 360) % 360
                    return [dslot.c, dslot.c.atDistanceAndAzimuth(sp * 3, az)]
                }
            }
            property var tag: MapQuickItem {
                visible:        dslot.ok
                coordinate:     dslot.c
                // alternate sides so two close drones do not cover each other's tag
                anchorPoint.x:  dslot.slot % 2 === 0 ? tagBox.width + 14 * root.u : -14 * root.u
                anchorPoint.y:  dslot.slot % 2 === 0 ? -10 * root.u : tagBox.height + 10 * root.u
                sourceItem: Rectangle {
                    id:     tagBox
                    width:  tagCol.implicitWidth + 16 * root.u
                    height: tagCol.implicitHeight + 10 * root.u
                    radius: 4 * root.u
                    color:  String(MLTheme.glass)
                    border.color: dslot.own ? MLTheme.warning : (dslot.lost ? MLTheme.warning : String(MLTheme.lineStrong))
                    Column {
                        id: tagCol
                        x: 8 * root.u; y: 5 * root.u
                        spacing: 1 * root.u
                        Text {
                            text: dslot.d ? dslot.d.id + "  " + (dslot.d.alt === null ? "—" : Number(dslot.d.alt).toFixed(1) + " m") : ""
                            color: dslot.col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
                        }
                        Text {
                            text: !dslot.d ? "" : (dslot.lost ? qsTr("링크 두절") : (dslot.own ? qsTr("ACACT 회피 중") : (dslot.d.yield ? qsTr("양보") : (dslot.d.lock ? qsTr("조종기 개입") : qsTr("감시")))))
                            color: dslot.own || dslot.lost ? MLTheme.warning : (dslot.d && dslot.d.lock ? MLTheme.caution : MLTheme.dim)
                            font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel; font.weight: dslot.own ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }
        onObjectAdded: function(index, object) { if (root.map) { root.map.addMapItem(object.ring); root.map.addMapItem(object.vec); root.map.addMapItem(object.tag) } }
        onObjectRemoved: function(index, object) { if (root.map) { root.map.removeMapItem(object.ring); root.map.removeMapItem(object.vec); root.map.removeMapItem(object.tag) } }
    }

    Instantiator {
        model: 6
        delegate: QtObject {
            id: pslot
            readonly property int slot: index
            readonly property var p:    slot < root._pairs.length ? root._pairs[slot] : null
            readonly property var a:    p ? root._coord(root._byId(p.a)) : QtPositioning.coordinate()
            readonly property var b:    p ? root._coord(root._byId(p.b)) : QtPositioning.coordinate()
            readonly property bool ok:  !!p && a.isValid && b.isValid
            readonly property color col: p ? root._levelColor(p.level) : "grey"

            property var line: MapPolyline {
                visible:    pslot.ok
                line.width: pslot.p && pslot.p.level ? 2.5 : 1
                line.color: pslot.col
                path:       pslot.ok ? [pslot.a, pslot.b] : []
            }
            property var label: MapQuickItem {
                visible:        pslot.ok
                coordinate:     pslot.ok ? pslot.a.atDistanceAndAzimuth(pslot.a.distanceTo(pslot.b) / 2, pslot.a.azimuthTo(pslot.b)) : QtPositioning.coordinate()
                anchorPoint.x:  lbl.width / 2
                anchorPoint.y:  lbl.height / 2
                sourceItem: Rectangle {
                    id:     lbl
                    width:  lblText.implicitWidth + 12 * root.u
                    height: lblText.implicitHeight + 6 * root.u
                    radius: 3 * root.u
                    color:  String(MLTheme.glass)
                    border.color: pslot.col
                    Text {
                        id: lblText
                        anchors.centerIn: parent
                        text: !pslot.p ? "" : Number(pslot.p.d).toFixed(1) + " m" + (pslot.p.level && pslot.p.cpa !== null ? "  ▸ " + Number(pslot.p.cpa).toFixed(1) + " m · " + Number(pslot.p.tcpa).toFixed(0) + "s" : "")
                        color: pslot.col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel
                    }
                }
            }
        }
        onObjectAdded: function(index, object) { if (root.map) { root.map.addMapItem(object.line); root.map.addMapItem(object.label) } }
        onObjectRemoved: function(index, object) { if (root.map) { root.map.removeMapItem(object.line); root.map.removeMapItem(object.label) } }
    }

    // pre-flight mission check: where two planned tracks come close (shown while the guard is not flying)
    readonly property var _mc: typeof mlGuard !== "undefined" && !mlGuard.running && mlGuard.missionCheck.pairs ? mlGuard.missionCheck.pairs : []
    Instantiator {
        model: 6
        delegate: QtObject {
            id: cslot
            readonly property var p: index < root._mc.length ? root._mc[index] : null
            readonly property bool ok: !!p && p.worst >= 1 && p.pathMin !== undefined && p.pathMin !== null
            readonly property color col: p && p.worst >= 2 ? MLTheme.warning : MLTheme.caution
            property var ring: MapCircle {
                visible:        cslot.ok
                center:         cslot.ok ? QtPositioning.coordinate(cslot.p.lat, cslot.p.lon) : QtPositioning.coordinate()
                radius:         root._dSafe / 2
                color:          Qt.rgba(cslot.col.r, cslot.col.g, cslot.col.b, 0.10)
                border.color:   cslot.col
                border.width:   1.5
            }
            property var tag: MapQuickItem {
                visible:        cslot.ok
                coordinate:     cslot.ok ? QtPositioning.coordinate(cslot.p.lat, cslot.p.lon) : QtPositioning.coordinate()
                anchorPoint.x:  ctag.width / 2
                anchorPoint.y:  -10 * root.u
                sourceItem: Rectangle {
                    id: ctag
                    width: ctagText.implicitWidth + 14 * root.u
                    height: ctagText.implicitHeight + 8 * root.u
                    radius: 3 * root.u
                    color: String(MLTheme.glass)
                    border.color: cslot.col
                    Text {
                        id: ctagText
                        anchors.centerIn: parent
                        text: !cslot.ok ? "" : qsTr("예상 근접 %1·%2  %3 m").arg(cslot.p.a).arg(cslot.p.b).arg(Number(cslot.p.pathMin).toFixed(1))
                        color: cslot.col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel
                    }
                }
            }
        }
        onObjectAdded: function(index, object) { if (root.map) { root.map.addMapItem(object.ring); root.map.addMapItem(object.tag) } }
        onObjectRemoved: function(index, object) { if (root.map) { root.map.removeMapItem(object.ring); root.map.removeMapItem(object.tag) } }
    }

    Component.onCompleted: if (map) map.addMapItem(_area)
}
