import QtQuick

import QGroundControl

// CI only (ML_TEST_ACACT=1): drives the GCS the way an operator would, for the SITL cases in
// tools/ci_sitl.sh. Every step is printed as "MLACACT test: …" for tools/acact_sitl.py.
//
//   s7duo      site from the vehicles → load S7_duo demo → guard → preflight → sequential start → auto-advance
//   preflight  load without a site must be refused; a wrong bearing must fail the preflight and block the start
//   user       user .plan files: a bad D2 mission (takeoff 30 m away) must block the start; after the correct one
//              is loaded the check shows only warnings (crossing tracks) and the flight runs with ACACT
//   gcskill    = user; tools/ci_sitl.sh kills the GCS at the first avoidance (PX4 must fail safe by itself)
//   restart    the GCS started again over two hovering vehicles: guard must not take them; operator resumes
//   linkloss   = user; tools/ci_sitl.sh cuts D2's link for 12 s at the first avoidance; operator resumes after
//   operator   = user; at the first avoidance of D1 the operator commands HOLD on D1 (guard must hand it back
//              and leave it alone), then resumes its mission 20 s later
QtObject {
    id: drv

    property string testCase: "s7duo"
    property string planDir: ""
    property int    n: 2

    property int    stage: 0
    property int    tries: 0
    property bool   operatorDone: false
    property var    holdSince: ({})
    property double t0: Date.now()

    function log(s) { console.log("MLACACT test: " + s) }
    function vehicles() { return QGroundControl.multiVehicleManager.vehicles }
    function vehicleById(id) {
        var vs = vehicles()
        for (var i = 0; i < vs.count; i++) if (vs.get(i).id === id) return vs.get(i)
        return null
    }
    function issuesText(mc) {
        var out = []
        var vl = mc.vehicles || [], pl = mc.pairs || []
        for (var i = 0; i < vl.length; i++) for (var k = 0; k < vl[i].issues.length; k++) if (vl[i].issues[k].level >= 1) out.push(vl[i].id + ":" + vl[i].issues[k].code)
        for (i = 0; i < pl.length; i++) for (k = 0; k < pl[i].issues.length; k++) out.push(pl[i].a + "-" + pl[i].b + ":" + pl[i].issues[k].code)
        return out.join(",")
    }
    readonly property bool _userFlow: testCase === "user" || testCase === "gcskill" || testCase === "linkloss" || testCase === "operator"

    // operator: hold D1 2 s after its first avoidance
    property var _guardConn: Connections {
        target: mlGuard
        function onGuardEvent(seq, time, who, text) {
            if (drv.testCase === "operator" && !drv.operatorDone && who === "D1" && text.indexOf("회피 개입") >= 0) {
                drv.operatorDone = true
                opTimer.start()
            }
        }
    }
    property var opTimer: Timer {
        interval: 2000
        onTriggered: {
            var v = drv.vehicleById(1)
            if (!v) return
            QGroundControl.multiVehicleManager.activeVehicle = v
            // what GuidedActionConfirm does for any operator command
            if (mlGuard.owns(1)) mlGuard.operatorCommand(1, "HOLD")
            v.pauseVehicle()
            drv.log("operator HOLD D1 (owned before: true)")
        }
    }

    property var timer: Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: drv.tick()
    }

    function allConnected() {
        var vs = vehicles()
        if (vs.count < n) return false
        var ready = 0
        for (var i = 0; i < vs.count; i++) {
            var v = vs.get(i)
            if (v.coordinate.isValid && v.homePosition.isValid && v.initialConnectComplete) ready++
        }
        return ready >= n && mlGuard.activeIds.split(",").length >= n
    }

    // after link loss / GCS restart / operator hold the vehicles hover in HOLD: the operator resumes them
    function resumeHolding(afterS) {
        var vs = vehicles()
        var now = Date.now()
        for (var i = 0; i < vs.count; i++) {
            var v = vs.get(i)
            var holding = v.flying && v.flightMode === v.pauseFlightMode
            if (!holding) { holdSince[v.id] = 0; continue }
            if (!holdSince[v.id]) holdSince[v.id] = now
            if (now - holdSince[v.id] >= afterS * 1000) {
                drv.log("operator resumes mission D" + v.id + " (held " + Math.round((now - holdSince[v.id]) / 1000) + " s)")
                v.flightMode = v.missionFlightMode
                holdSince[v.id] = 0
            }
        }
    }

    function tick() {
        if (stage === 0) {
            if (!allConnected()) return
            log(vehicles().count + " vehicles (" + mlGuard.activeIds + "), case " + testCase)
            stage = 1
            return
        }
        if (testCase === "s7duo") return s7duo()
        if (testCase === "preflight") return preflight()
        if (testCase === "restart") return restart()
        if (_userFlow) return user()
    }

    function startGuardAndFly() {
        if (!mlGuard.running) mlGuard.start()
        var pf = mlGuard.runPreflight()
        var ok = true
        for (var k = 0; k < pf.length; k++) if (!pf[k].ok) { ok = false; log("preflight " + pf[k].id + " " + pf[k].issues.join(" / ")) }
        if (!ok) return false
        log("preflight ok, start flight")
        return mlGuard.startFlight()
    }

    function s7duo() {
        if (stage === 1) {
            mlGuard.profile = "oregon"
            mlGuard.setSiteFromVehicles(-1)
            if (mlGuard.site.lat !== undefined) stage = 2
        } else if (stage === 2) {
            if (mlGuard.busyText !== "") return
            if (mlGuard.scenario === "S7_duo") { log("S7_duo/demo loaded"); stage = 3; return }
            if (tries++ > 0) log("load retry " + tries)
            mlGuard.loadScenario("S7_duo", "demo")
        } else if (stage === 3) {
            if (startGuardAndFly()) { openConsole(); stage = 9 }
        }
    }

    function preflight() {
        if (stage === 1) {
            mlGuard.clearSite()
            mlGuard.loadScenario("S7_duo", "demo")
            stage = 2
        } else if (stage === 2) {
            log("load without site refused=" + (mlGuard.scenario === "" && mlGuard.busyText === ""))
            mlGuard.profile = "oregon"
            mlGuard.setSiteFromVehicles(90)      // vehicles face north (0°)
            mlGuard.loadScenario("S7_duo", "demo")
            stage = 3
        } else if (stage === 3) {
            if (mlGuard.busyText !== "" || mlGuard.scenario !== "S7_duo") return
            mlGuard.start()
            var pf = mlGuard.runPreflight()
            var heading = false
            for (var k = 0; k < pf.length; k++) for (var j = 0; j < pf[k].issues.length; j++) if (pf[k].issues[j].indexOf("기수 방향") >= 0) heading = true
            log("heading issue=" + heading)
            log("start with wrong bearing=" + mlGuard.startFlight())
            stage = 4
        } else if (stage === 4) {
            mlGuard.stop()
            log("done")
            stage = 9
        }
    }

    function user() {
        var bad = testCase === "user"
        if (stage === 1) {
            if (mlGuard.busyText !== "") return
            if (mlGuard.uploadPlanFile(1, planDir + "/D1.plan")) stage = 2
        } else if (stage === 2) {
            if (mlGuard.busyText !== "") return
            if (mlGuard.uploadPlanFile(2, planDir + (bad ? "/D2_bad.plan" : "/D2.plan"))) stage = bad ? 3 : 5
        } else if (stage === 3) {
            if (mlGuard.busyText !== "") return
            var mc = mlGuard.validateMissions()
            mlGuard.start()
            var ok = mlGuard.startFlight()
            log("bad mission errors=" + mc.errors + " [" + issuesText(mc) + "] start=" + ok)
            if (ok) { mlGuard.abortStart(); mlGuard.holdAll(); log("※ bad mission was not blocked — test stopped"); stage = 9; return }
            stage = 4
        } else if (stage === 4) {
            if (mlGuard.busyText !== "") return
            if (mlGuard.uploadPlanFile(2, planDir + "/D2.plan")) stage = 5
        } else if (stage === 5) {
            if (mlGuard.busyText !== "") return
            mc = mlGuard.validateMissions()
            log("mission check errors=" + mc.errors + " warnings=" + mc.warnings + " [" + issuesText(mc) + "]")
            if (mc.errors > 0) { stage = 9; return }
            if (startGuardAndFly()) { openConsole(); stage = 6 }
        } else if (stage === 6) {
            if (testCase === "linkloss") resumeHolding(8)
            if (testCase === "operator") resumeHolding(20)
        }
    }

    function restart() {
        if (stage === 1) {
            mlGuard.start()
            log("restart: guard started over " + vehicles().count + " vehicles")
            stage = 2
            t0 = Date.now()
        } else if (stage === 2) {
            // give the guard 25 s to (not) take the hovering vehicles, then the operator resumes them
            if (Date.now() - t0 > 25000) resumeHolding(0)
        }
    }

    property var _openConsole: null
    function openConsole() { if (_openConsole) _openConsole() }
}
