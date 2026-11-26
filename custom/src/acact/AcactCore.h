#pragma once
//
// AcactCore — C++17 port of ACACT Guard core.py (vendor/acact_guard_original/core.py)
//
// Pure computation: no Qt, no MAVLink, no I/O. The GCS feeds it the state of
// every guarded vehicle at 20 Hz and executes the commands it returns.
// Behaviour must stay identical to the Python original; this is checked by
// tools/acact_compare (replays traces recorded from the original sim_check.py
// and compares every command, see docs/ACACT_INTEGRATION.md).
//
// Frame: demo frame 2D (F forward, R right) + U up, metres / m/s.
//
#include <array>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace mlacact {

struct Params {
    // ── guard (config.py) ──
    double loopHz          = 20.0;
    double staleT          = 1.5;
    double stalePredictMax = 8.0;
    double dlLossT         = 2.0;
    double degradedMargin  = 2.0;
    double staleDropT      = 30.0;
    double dSafe           = 10.0;
    double dEmerg          = 5.5;
    double tLook           = 6.0;
    double vSep            = 4.0;
    double releaseMargin   = 2.0;
    double releaseHold     = 2.0;
    double minOwnTime      = 3.0;
    double minTakeoverAlt  = 5.0;
    double goalHandoff     = 1.8;
    double padZone         = 4.0;
    double maxHSpeed       = 3.0;
    double maxClimb        = 1.0;
    double emergClimbMax   = 6.0;
    double altHoldKp       = 0.8;
    // ── ACACT (Min & Nam, IEEE Access 2023) ──
    double kpa     = 0.6;
    double kpp     = 1.5;
    double kpv     = 0.3;
    double rs      = 12.0;
    double ts      = 3.0;
    double kRh     = 1.2;
    double kCpa    = 2.0;
    double goalTol = 1.0;

    /// config.py defaults for the given number of vehicles (2 → "DUO" values)
    static Params forVehicleCount(int n);
};

struct DroneIn {
    std::string id;
    int    prio = 0;          // 0 = highest (D1)
    bool   fresh = true;
    double age = 0;
    double f = 0, r = 0, u = 0;
    double vf = 0, vr = 0, vu = 0;
    double relAlt = 0;
    bool   inAir = false;
    std::string mode;         // MISSION / OFFBOARD / HOLD / RTL / LAND / TAKEOFF / MANUAL / OTHER
    std::optional<std::pair<double, double>> goal;
    double rtlAlt = 0;
    bool   goalHold = false;
    std::optional<double> goalAlt;
    std::optional<std::pair<double, double>> home;
};

struct Own {
    bool   owned = false;
    double tTake = 0;
    std::optional<double> tClear;
    double holdU = 0;
    bool   lock = false;
    bool   yielding = false;
    double tHandoff = -1e9;
    int    takeovers = 0;
    double ownedTime = 0;
};

struct PairEval {
    int    level = 0;         // 0 normal, 1 risk (CPA), 2 emergency
    double dNow = 0, dCpa = 0, tCpa = 0, dz = 0;
    bool   clear = true;
};

struct Command {
    enum Type { Takeover, Vel, Release, Event };
    Type        type = Event;
    std::string id;           // vehicle id, or "D1-D2" for pair events
    double      v[3] = {0, 0, 0};
    std::string text;         // Event only (Korean, as the original)
};

struct Predicted { double f, r, u, vf, vr, infl; };

Predicted predicted(const Params &p, const DroneIn &d);
std::pair<double, double> cpa(double pf, double pr, double vf, double vr, double tLook);  // (t, d)
PairEval evalPair(const Params &p, const DroneIn &a, const DroneIn &b, double extra = 0.0);

struct VelDebug { std::string mode; double tc; };
// returns (vf, vr) and debug
std::pair<double, double> acactVelocity(const Params &p, const DroneIn &me, const std::vector<DroneIn> &others,
                                        std::pair<double, double> goal, bool emergency, VelDebug *dbg = nullptr);

using PairKey = std::pair<std::string, std::string>;

class GuardCore {
public:
    GuardCore(const std::vector<std::string> &ids, const Params &params);

    std::vector<Command> step(double t, const std::vector<DroneIn> &drones);
    bool eligible(const DroneIn &d) const;

    Params params;
    std::map<std::string, Own> own;
    std::vector<std::pair<PairKey, PairEval>> pairs;    // in evaluation order
    std::map<PairKey, double> minSep;                    // same layer (dz <= V_SEP) minimum horizontal distance
    std::map<PairKey, double> min3d;
    bool enabled = true;

private:
    std::array<double, 3> _velocity(const DroneIn &d, const std::vector<DroneIn> &drones, int level);

    std::optional<double> _lastT;
    std::map<PairKey, double> _warnedT;
    std::vector<std::string> _dropped;
    double _extra = 0.0;
};

} // namespace mlacact
