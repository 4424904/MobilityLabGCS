pragma Singleton

import QtQuick

// One overall ACACT state for the operator, derived only from the guard's own published values
// (mlGuard.active / avoiding / worstLevel / drones[].phase). Nothing here computes separation or
// risk; it only names what the guard already reports and says what the operator should do.
//   off      정지          the guard is not running
//   lost     오류 · 두절    a vehicle's telemetry is lost to the guard
//   avoid    회피 중        the guard has taken over at least one vehicle
//   predict  충돌 예측      the core predicts a conflict (level ≥ 1) but nobody is taken over yet
//   return   임무 복귀      a vehicle was handed back to its mission in the last seconds
//   operator 운용자 제어    the operator has a vehicle (ACACT yields)
//   paused   일시정지       guard enabled flag off (all HOLD)
//   normal   정상 감시
QtObject {
    function evaluate(g) {
        var r = { key: "off", name: qsTr("ACACT 정지"), level: -1, action: qsTr("ACACT 콘솔에서 가드를 시작할 수 있습니다"), ids: [] }
        if (!g) { r.name = qsTr("ACACT 사용 불가"); r.action = ""; return r }
        if (!g.active) return r
        var ds = g.drones || []
        var lost = [], avoid = [], ret = [], op = []
        for (var i = 0; i < ds.length; i++) {
            var p = ds[i].phase
            if (p === "lost") lost.push(ds[i].id)
            else if (p === "avoid") avoid.push(ds[i].id)
            else if (p === "return") ret.push(ds[i].id)
            else if (p === "operator") op.push(ds[i].id)
        }
        if (lost.length > 0) {
            return { key: "lost", name: qsTr("텔레메트리 두절 · %1").arg(lost.join(", ")), level: 3, ids: lost,
                     action: qsTr("링크를 확인하세요. 회피 중이었다면 PX4가 스스로 HOLD 합니다. 다른 기체는 마지막 위치로 예측해 피합니다.") }
        }
        if (avoid.length > 0) {
            return { key: "avoid", name: qsTr("회피 기동 중 · %1").arg(avoid.join(", ")), level: 3, ids: avoid,
                     action: qsTr("ACACT가 제어 중입니다. 위험하면 HOLD 또는 조종기로 개입하세요 — 운용자 조작이 우선합니다.") }
        }
        if (g.worstLevel >= 1) {
            return { key: "predict", name: qsTr("충돌 예측"), level: 2, ids: [],
                     action: qsTr("ACACT가 감시 중입니다. 필요하면 자동으로 회피합니다.") }
        }
        if (!g.guardEnabled) {
            return { key: "paused", name: qsTr("일시정지 (HOLD)"), level: 2, ids: [],
                     action: qsTr("ACACT 콘솔의 [재개]로 다시 시작합니다.") }
        }
        if (op.length > 0) {
            return { key: "operator", name: qsTr("운용자 제어 · %1").arg(op.join(", ")), level: 1, ids: op,
                     action: qsTr("운용자가 조작 중인 기체는 ACACT가 넘겨받지 않습니다. 미션을 재개하면 다시 감시합니다.") }
        }
        if (ret.length > 0) {
            return { key: "return", name: qsTr("임무 복귀 · %1").arg(ret.join(", ")), level: 1, ids: ret,
                     action: qsTr("회피가 끝나 미션으로 돌아갔습니다.") }
        }
        return { key: "normal", name: qsTr("정상 감시"), level: 0, ids: [], action: qsTr("조치할 것 없음") }
    }
    function color(key) {
        if (key === "lost" || key === "avoid") return MLTheme.warning
        if (key === "predict" || key === "paused") return MLTheme.caution
        if (key === "operator" || key === "return") return MLTheme.info
        if (key === "normal") return MLTheme.active
        return MLTheme.faint
    }
}
