import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Right console column: 추진 · 추세 · 전원·연료 · 경고 · 미션.
// Sections appear only for data the aircraft reports; the column scrolls on
// short screens.
Rectangle {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property real u:       MLTheme.u
    readonly property var  _t:      typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _seen:   _t ? _t.seenKeys : ({})
    readonly property var  _vals:   _t ? _t.values : ({})
    readonly property bool _has:    !!vehicle

    function anySeen(keys) { for (var i = 0; i < keys.length; i++) if (_seen[keys[i]] === true) return true; return false }
    function fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
    function tv(key) { var v = _vals[key]; return v === undefined ? NaN : v }

    readonly property bool _engRpm:   _seen["eng.rpm"] === true
    readonly property bool _rotor:    anySeen([ "rot.front", "rot.rear" ])
    readonly property bool _tandem:   _seen["rot.rear"] === true
    readonly property bool _motors:   _has && !!vehicle.escs && vehicle.escs.count > 0
    readonly property bool _propulsion: _has && (_engRpm || _rotor || _motors)
    readonly property real _ecu:      tv("eng.health")

    color: MLTheme.panelSolid

    Flickable {
        id:             flick
        anchors.fill:   parent
        contentHeight:  col.height
        clip:           true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Column {
            id:     col
            width:  flick.width

            // ===== 추진 =====================================================
            Column {
                width:      parent.width
                visible:    root._propulsion

                MLSection {
                    width:  parent.width
                    rule:   false
                    title:  qsTr("추진")
                    detail: !isNaN(root._ecu) ? (root._ecu > 0 ? "ECU OK" : "ECU FAULT")
                                              : (root._motors ? qsTr("모터 %1").arg(root.vehicle.escs.count) : "")
                    detailColor: !isNaN(root._ecu) && root._ecu <= 0 ? MLTheme.warning : MLTheme.dim
                }

                readonly property int _n: (root._engRpm ? 1 : 0) + (root._rotor ? (root._tandem ? 2 : 1) : 0)
                readonly property real _dial: Math.min(132 * u, (width - 28 * u) / Math.max(1, _n))

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible:    parent._n > 0
                    MLArcGauge { visible: root._engRpm; key: "eng.rpm"; title: qsTr("엔진"); size: parent.parent._dial }
                    MLArcGauge { visible: root._rotor; key: "rot.front"; title: root._tandem ? qsTr("전방 로터") : qsTr("메인 로터"); size: parent.parent._dial
                                 level: isNaN(value) ? 0 : (root._tandem ? Math.max(1, splitLevel) : 1)
                                 readonly property int splitLevel: { var l = root._t ? root._t.levels["rot.split"] : undefined; return l === undefined ? 0 : l } }
                    MLArcGauge { visible: root._tandem; key: "rot.rear"; title: qsTr("후방 로터"); size: parent.parent._dial
                                 level: isNaN(value) ? 0 : Math.max(1, splitLevel)
                                 readonly property int splitLevel: { var l = root._t ? root._t.levels["rot.split"] : undefined; return l === undefined ? 0 : l } }
                }

                // tandem sync: centre-zero scale, ±6 % full scale
                Item {
                    visible:    root._tandem
                    width:      parent.width
                    height:     40 * u
                    readonly property real _split:  root.tv("rot.split")
                    readonly property real _delta:  root.tv("rot.front") - root.tv("rot.rear")
                    readonly property int  _lvl:    { var l = root._t ? root._t.levels["rot.split"] : undefined; return l === undefined ? 0 : l }
                    readonly property color _c:     _lvl >= 3 ? MLTheme.warning : (_lvl === 2 ? MLTheme.caution : MLTheme.label)

                    MLText { x: 20 * u; anchors.verticalCenter: parent.verticalCenter; text: qsTr("탠덤 동기"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.6 * u }
                    Item {
                        id:     syncBar
                        x:      96 * u
                        width:  parent.width - 96 * u - 140 * u
                        height: 18 * u
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4 * u; color: String(MLTheme.line) }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: parent.width * (0.5 - 2 / 12); width: parent.width * 4 / 12; height: 4 * u; color: MLTheme.zoneNormal }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 1; height: parent.height * 0.8; anchors.verticalCenter: parent.verticalCenter; color: String(MLTheme.faint) }
                        Rectangle {
                            visible:    !isNaN(parent.parent._split)
                            width:      3 * u
                            height:     12 * u
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property real _f: Math.max(-1, Math.min(1, (parent.parent._delta >= 0 ? 1 : -1) * parent.parent._split / 6))
                            x:          parent.width / 2 + _f * parent.width / 2 - width / 2
                            color:      parent.parent._lvl >= 2 ? parent.parent._c : MLTheme.bright
                        }
                    }
                    MLNum {
                        anchors.right:          parent.right
                        anchors.rightMargin:    20 * u
                        anchors.verticalCenter: parent.verticalCenter
                        text:   isNaN(parent._split) ? "—" : (parent._delta >= 0 ? "+" : "") + parent._delta.toFixed(0) + " rpm · " + parent._split.toFixed(1) + "%"
                        color:  parent._lvl >= 2 ? parent._c : MLTheme.text
                        size:   MLTheme.fsBody
                    }
                }

                // per-motor RPM (multicopter / VTOL with ESC telemetry)
                MLMotorView {
                    x:          20 * u
                    width:      parent.width - 40 * u
                    visible:    root._motors && !root._rotor && !root._engRpm
                    vehicle:    root.vehicle
                }
                Item { width: 1; height: 8 * u }
            }

            // ===== 추세 =====================================================
            MLSection { width: parent.width; rule: root._propulsion; title: qsTr("추세"); visible: root._has }
            MLTrendTable { width: parent.width; vehicle: root.vehicle; visible: root._has }

            // ===== 전원 · 연료 ==============================================
            MLSection {
                width:  parent.width
                title:  power._fuel ? qsTr("전원 · 연료") : qsTr("전원")
                visible: root._has
            }
            Column {
                id:         power
                width:      parent.width
                visible:    root._has
                spacing:    8 * u

                readonly property bool _fuel: root.anySeen([ "fuel.pct", "fuel.L", "fuel.endurance" ])

                component PowerRow: Item {
                    property string label
                    property string value
                    property real   frac: NaN
                    property int    level: 1
                    width:  power.width
                    height: 20 * u
                    MLText { x: 20 * u; width: 96 * u; anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: parent.level >= 2 ? MLTheme.levelColor(parent.level) : MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                    Rectangle {
                        x:      128 * u
                        width:  parent.width - 128 * u - 140 * u
                        height: 6 * u
                        anchors.verticalCenter: parent.verticalCenter
                        color:  String(MLTheme.line)
                        Rectangle { height: parent.height; width: isNaN(parent.parent.frac) ? 0 : parent.width * Math.max(0, Math.min(1, parent.parent.frac)); color: parent.parent.level >= 2 ? MLTheme.levelColor(parent.parent.level) : String(MLTheme.dim) }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 20 * u; anchors.verticalCenter: parent.verticalCenter; text: parent.value; color: parent.level >= 2 ? MLTheme.levelColor(parent.level) : MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody }
                }

                Repeater {
                    model: root._has ? root.vehicle.batteries : 0
                    PowerRow {
                        required property var object
                        readonly property real _pct: root.fv(object.percentRemaining)
                        readonly property real _v:   root.fv(object.voltage)
                        readonly property int  _st:  isNaN(root.fv(object.chargeState)) ? 0 : root.fv(object.chargeState)
                        label:  root.vehicle.batteries.count > 1 ? (root.fv(object.id) === 0 ? qsTr("주 배터리") : qsTr("배터리 %1").arg(root.fv(object.id) + 1)) : qsTr("배터리")
                        value:  (isNaN(_v) ? "— V" : _v.toFixed(1) + " V") + " · " + (isNaN(_pct) ? "—" : Math.round(_pct) + "%")
                        frac:   _pct / 100
                        level:  _st >= 3 || _pct < 15 ? 3 : (_st === 2 || _pct < 30 ? 2 : 1)
                    }
                }
                PowerRow {
                    visible:    power._fuel
                    label:      qsTr("연료")
                    readonly property real _l: root.tv("fuel.L")
                    readonly property real _e: root.tv("fuel.endurance")
                    value:      (isNaN(_l) ? "" : _l.toFixed(1) + " L") + (isNaN(_e) ? "" : " · " + Math.round(_e) + qsTr("분")) || "—"
                    frac:       root.tv("fuel.pct") / 100
                    level:      { var l = root._t ? root._t.levels["fuel.pct"] : undefined; return l === undefined ? 1 : l }
                }
                Item { width: 1; height: 4 * u }
            }

            // ===== 경고 =====================================================
            MLCasList { width: parent.width; vehicle: root.vehicle }

            // ===== 미션 =====================================================
            MLMissionList {
                width:      parent.width
                vehicle:    root.vehicle
                maxListHeight: Math.max(5 * 28 * u, flick.height - y - 120 * u)
            }
        }
    }

    MLPanelChrome { radius: root.radius }
}
