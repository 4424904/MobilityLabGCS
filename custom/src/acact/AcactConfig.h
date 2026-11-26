// ACACT Guard — configuration (port of acact_guard/config.py)
//
// Pure C++17 (no Qt) so the algorithm can be compiled and verified on its own
// (tools/acact_verify). Field names follow config.py; defaults are the values
// of the original. forDrones() applies the 2-drone (DUO) adjustments exactly
// as config.py does at import time.
#pragma once

#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace acact {

struct DroneCfg {
    std::string id;     // "D1" … "D4"  (D1 = highest priority)
    int         sysid;  // MAVLink system id
    double      layer;  // transit / rehearsal / RTL altitude [m, above home]
};

struct AcactGains {
    double kpa      = 0.6;   // attraction gain
    double kpp      = 1.5;   // position repulsion gain
    double kpv      = 0.3;   // relative-velocity repulsion gain
    double rs       = 12.0;  // repulsion radius [m]
    double ts       = 3.0;   // safety time [s]
    double k_rh     = 1.2;   // keep-right bias gain
    double k_cpa    = 2.0;   // CPA-based early keep-right gain [m/s]
    double goal_tol = 1.0;
};

struct Config {
    // ---- drones
    std::vector<DroneCfg> allDrones = {
        {"D1", 1, 20.0}, {"D2", 2, 26.0}, {"D3", 3, 32.0}, {"D4", 4, 38.0}};
    std::vector<DroneCfg> drones = allDrones;   // active set

    // ---- altitudes / site layout
    double demoAlt       = 8.0;
    double takeoffAlt    = 8.0;
    double takeoffSpeed  = 1.0;
    double stepFwd       = 2.0;
    double padZone       = 4.0;
    double homeLineF     = -35.0;
    double homeSpacing   = 15.0;
    std::string profile  = "oregon";
    double scenarioRadius = 25.0;

    // ---- speeds
    double transitSpeed    = 5.0;
    double lowTransitSpeed = 3.0;
    double scenarioSpeed   = 3.0;

    // ---- guard loop
    int    loopHz          = 20;
    int    telemHz         = 10;
    int    prestreamHz     = 5;
    double staleT          = 1.5;
    double stalePredictMax = 8.0;
    double dlLossT         = 2.0;
    bool   autoSync        = true;
    double battWarn        = 35.0;
    bool   autoLand        = true;
    double autoSyncDelay   = 5.0;
    double degradedMargin  = 2.0;
    double staleDropT      = 30.0;

    double dSafe          = 10.0;
    double dEmerg         = 5.5;
    double tLook          = 6.0;
    double vSep           = 4.0;
    double releaseMargin  = 2.0;
    double releaseHold    = 2.0;
    double minOwnTime     = 3.0;
    double minTakeoverAlt = 5.0;
    double goalHandoff    = 1.8;

    double maxHSpeed     = 3.0;
    double maxClimb      = 1.0;
    double emergClimbMax = 6.0;
    double altHoldKp     = 0.8;

    AcactGains acact;

    bool duo = false;

    // ---- helpers
    /// Config for a set of drone ids ("D1","D3"…). Unknown ids are ignored.
    /// Two drones → DUO adjustments (config.py bottom block).
    static Config forDrones(const std::vector<std::string> &ids, const std::string &profile = "oregon");
    /// The same values for an explicit configuration the user edited: re-applies
    /// nothing, only selects the drone set.
    void selectDrones(const std::vector<std::string> &ids);

    std::optional<std::pair<double, double>> layoutHome(const std::string &id) const;
    double homeCenterF() const;
    const DroneCfg *drone(const std::string &id) const;
    int indexInAll(const std::string &id) const;
};

std::vector<std::string> profileNames();

} // namespace acact
