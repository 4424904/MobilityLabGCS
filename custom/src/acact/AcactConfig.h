// ACACT engine — configuration (port of acact_guard/config.py, revision 1)
//
// Every field keeps the name and default of config.py. Values that depend on
// how many drones fly (the DUO block) are applied by applyFleetSize().
// Values that must match PX4 parameters are marked [PX4].
#pragma once

#include <map>
#include <string>
#include <vector>

namespace acact {

struct DroneSlot {
    std::string id;      // "D1" … (D1 = highest priority)
    int         sysid;   // MAVLink system id
    double      layer;   // transit / rehearsal / RTL altitude [m, above takeoff]
};

struct Config {
    // ── airframes ─────────────────────────────────────────────
    std::vector<DroneSlot> allDrones = {
        {"D1", 1, 20.0}, {"D2", 2, 26.0}, {"D3", 3, 32.0}, {"D4", 4, 38.0},
    };

    double demoAlt          = 8.0;   // DEMO_ALT
    double takeoffAlt       = 8.0;   // TAKEOFF_ALT
    double takeoffSpeed     = 1.0;   // TAKEOFF_SPEED [PX4 MPC_TKO_SPEED]
    double stepFwd          = 2.0;   // STEP_FWD
    double padZone          = 4.0;   // PAD_ZONE

    // ── site layout (demo frame, m) ───────────────────────────
    double homeLineF        = -35.0; // HOME_LINE_F
    double homeSpacing      = 15.0;  // HOME_SPACING
    std::string profile     = "oregon";
    // HOME_LAYOUTS: profile → {id: (F, R)}; "oregon" has none (computed from the line)
    std::map<std::string, std::map<std::string, std::pair<double, double>>> homeLayouts = {
        {"oregon", {}},
        {"oregon2", {{"D1", {-35.0, -7.5}}, {"D2", {-35.0, 7.5}}, {"D3", {-35.0, 22.5}}, {"D4", {-35.0, -22.5}}}},
        {"hwaseong", {{"D1", {-37.0, -5.0}}, {"D2", {-37.0, 5.0}}, {"D3", {-47.0, -5.0}}, {"D4", {-47.0, 5.0}}}},
    };
    std::map<std::string, double> homeCenterF = {{"oregon", -35.0}, {"oregon2", -35.0}, {"hwaseong", -42.0}};
    double scenarioRadius   = 25.0;  // SCENARIO_RADIUS

    // ── speeds ────────────────────────────────────────────────
    double transitSpeed     = 5.0;   // TRANSIT_SPEED
    double lowTransitSpeed  = 3.0;   // LOW_TRANSIT_SPEED
    double scenarioSpeed    = 3.0;   // SCENARIO_SPEED

    // ── collision guard ───────────────────────────────────────
    double loopHz           = 20;    // LOOP_HZ
    double telemHz          = 10;    // TELEM_HZ
    double prestreamHz      = 5;     // PRESTREAM_HZ
    double staleT           = 1.5;   // STALE_T
    double stalePredictMax  = 8.0;   // STALE_PREDICT_MAX
    double dlLossT          = 2.0;   // DL_LOSS_T [PX4 COM_DL_LOSS_T]
    bool   autoSync         = true;  // AUTO_SYNC
    double battWarn         = 35.0;  // BATT_WARN
    bool   autoLand         = true;  // AUTO_LAND
    double autoSyncDelay    = 5.0;   // AUTO_SYNC_DELAY
    bool   advanceInAvoid   = false; // ADVANCE_IN_AVOID (rev1)
    double degradedMargin   = 2.0;   // DEGRADED_MARGIN
    double staleDropT       = 30.0;  // STALE_DROP_T

    double dSafe            = 10.0;  // D_SAFE
    double dEmerg           = 5.5;   // D_EMERG
    double tLook            = 6.0;   // T_LOOK
    double vSep             = 4.0;   // V_SEP
    double releaseMargin    = 2.0;   // RELEASE_MARGIN
    double releaseHold      = 2.0;   // RELEASE_HOLD
    double minOwnTime       = 3.0;   // MIN_OWN_TIME
    double minTakeoverAlt   = 5.0;   // MIN_TAKEOVER_ALT
    double goalHandoff      = 1.8;   // GOAL_HANDOFF [< PX4 NAV_ACC_RAD]

    double maxHSpeed        = 3.0;   // MAX_H_SPEED
    double maxClimb         = 1.0;   // MAX_CLIMB
    double emergClimbMax    = 6.0;   // EMERG_CLIMB_MAX
    double altHoldKp        = 0.8;   // ALT_HOLD_KP

    // ── ACACT (Min & Nam, IEEE Access 2023) ───────────────────
    struct Acact {
        double kpa     = 0.6;
        double kpp     = 1.5;
        double kpv     = 0.3;
        double rs      = 12.0;
        double ts      = 3.0;
        double k_rh    = 1.2;
        double k_cpa   = 2.0;
        double goalTol = 1.0;
    } acact;

    bool duo = false;

    /// DUO block of config.py: exactly two drones fly.
    void applyFleetSize(int activeDrones)
    {
        duo = (activeDrones == 2);
        if (duo) {
            maxHSpeed = 4.5;
            dSafe     = 12.0;
            acact.rs  = 14.0;
            acact.k_cpa = 3.0;
        }
    }

    const DroneSlot *slot(const std::string &id) const
    {
        for (const auto &d : allDrones) {
            if (d.id == id) {
                return &d;
            }
        }
        return nullptr;
    }
};

} // namespace acact
