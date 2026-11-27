import QtQuick

// Records the ACACT run for the timeline: guard events (takeover with its reason, release,
// link loss, operator) and, from the guard's pair evaluations, when a pair first enters a
// predicted conflict and when it clears, plus the closest separation at 2 Hz.
// Values are the guard's own; nothing is interpolated or invented.
Item {
    id: root
    readonly property bool _has: typeof mlGuard !== "undefined"
    property var _prevLevel: ({})
    property bool _wasRunning: false

    function kindOf(text) {
        if (/회피 개입|takeover/i.test(text)) return "takeover"
        if (/회피 완료|미션 복귀|back to mission/i.test(text)) return "release"
        if (/두절|끊김|lost|offboard 상실/i.test(text)) return "lost"
        if (/운용자|조종|모드 .* 전환|pilot|operator/i.test(text)) return "operator"
        if (/불가|실패|fail/i.test(text)) return "info"
        if (/가드 시작|guard start/i.test(text)) return "start"
        if (/가드 종료|가드 정지|guard stop/i.test(text)) return "stop"
        return "info"
    }
    function add(t, who, kind, text, level) {
        MLState.acactEvents.append({ t: t, who: who, kind: kind, text: text, level: level === undefined ? 0 : level })
        if (MLState.acactEvents.count > 2000) MLState.acactEvents.remove(0, 200)
    }

    Connections {
        target: root._has ? mlGuard : null
        function onGuardEvent(seq, time, who, text) {
            root.add(time, who, root.kindOf(text), text)
        }
        function onRunningChanged() {
            if (mlGuard.running && !root._wasRunning) {
                MLState.acactEvents.clear()
                MLState.acactSep = []
                MLState.acactSepRev++
                MLState.acactT0 = -1
                root._prevLevel = ({})
            }
            root._wasRunning = mlGuard.running
        }
        function onUpdated() {
            if (!mlGuard.running) return
            var t = mlGuard.guardTime
            var ps = mlGuard.pairs
            var lv = ({})
            for (var i = 0; i < ps.length; i++) {
                var p = ps[i], key = p.a + "-" + p.b
                var prev = root._prevLevel[key] === undefined ? 0 : root._prevLevel[key]
                if (p.level >= 1 && prev === 0)
                    root.add(t, key, "predict", qsTr("%1·%2 충돌 예측: 현재 %3 m, %4초 후 최소 %5 m").arg(p.a).arg(p.b).arg(p.d.toFixed(1)).arg(p.tcpa.toFixed(1)).arg(p.cpa.toFixed(1)), p.level)
                else if (p.level === 2 && prev === 1)
                    root.add(t, key, "predict", qsTr("%1·%2 비상 이격 진입: %3 m").arg(p.a).arg(p.b).arg(p.d.toFixed(1)), 2)
                else if (p.level === 0 && prev >= 1)
                    root.add(t, key, "clear", qsTr("%1·%2 위험 해소: %3 m").arg(p.a).arg(p.b).arg(p.d.toFixed(1)), 0)
                lv[key] = p.level
            }
            root._prevLevel = lv
        }
    }
    Timer {
        interval: 500; repeat: true
        running: root._has && mlGuard.running
        onTriggered: {
            if (isNaN(mlGuard.closest)) return
            if (MLState.acactT0 < 0) MLState.acactT0 = mlGuard.guardTime
            MLState.acactSep.push({ t: mlGuard.guardTime, d: mlGuard.closest, level: mlGuard.worstLevel })
            if (MLState.acactSep.length > 14400) MLState.acactSep.splice(0, 1200)
            MLState.acactSepRev++
        }
    }
}
