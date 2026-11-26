// ACACT engine — decision core (port of acact_guard/core.py, revision 1)
//
// No I/O, no Qt, no MAVLink: the same code runs in the GCS, in the offline
// simulator and in the Python comparison harness (through acact_capi).
//
// Frame: demo frame 2D (F forward, R right) + altitude U (up +).
// GuardCore::step() takes the drone states and returns a command list:
//   Takeover id v  : enter Offboard + avoidance velocity
//   Vel      id v  : update avoidance velocity
//   Release  id    : back to mission
//   Advance  id    : keep Offboard, move mission sequence to the next item (rev1)
//   Event    id txt: log / screen event
#pragma once

#include "AcactConfig.h"

#include <array>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace acact {

using Vec2 = std::array<double, 2>;
using Vec3 = std::array<double, 3>;

struct DroneIn {
    std::string id;
    int    prio = 0;            // 0 = highest (D1)
    bool   fresh = true;        // telemetry is recent
    double age = 0.0;           // since last telemetry [s]
    double f = 0, r = 0, u = 0; // position (u: common altitude reference)
    double vf = 0, vr = 0, vu = 0;
    double relAlt = 0;          // above takeoff point
    bool   inAir = false;
    std::string mode = "OTHER"; // MISSION / OFFBOARD / HOLD / RTL / LAND / TAKEOFF / MANUAL / OTHER
    std::optional<Vec2>   goal;     // current mission target (F, R)
    double rtlAlt = 0.0;            // PX4 RTL altitude (above takeoff)
    bool   goalHold = false;        // target is a stop point (sync / hold)
    std::optional<double> goalAlt;  // current mission target altitude (above takeoff)
    std::optional<Vec2>   home;     // takeoff point (F, R)
};

struct Own {
    bool   owned = false;
    double tTake = 0.0;
    std::optional<double> tClear;
    double holdU = 0.0;
    bool   lock = false;        // pilot took control → hands off until mission resumes
    bool   yielding = false;
    double tHandoff = -1e9;
    std::optional<Vec2> advGoal;
    double tAdv = -1e9;
    int    takeovers = 0;
    double ownedTime = 0.0;
};

struct PairEval {
    int    level = 0;           // 0 normal, 1 conflict (CPA), 2 emergency
    double dNow = 0;
    double dCpa = 0;
    double tCpa = 0;
    double dz = 0;
    bool   clear = true;        // release criterion (hysteresis) met
};

enum class CmdKind { Takeover, Vel, Release, Advance, Event };

struct Command {
    CmdKind     kind;
    std::string id;
    Vec3        v {0, 0, 0};
    std::string text;
};

struct Predicted {
    double f, r, u, vf, vr, infl;
};

using PairKey = std::pair<std::string, std::string>;

// ── geometry (free functions, as in core.py) ─────────────────
Predicted predicted(const Config &c, const DroneIn &d);
std::pair<double, double> cpa(double pf, double pr, double vf, double vr, double tLook);
PairEval evalPair(const Config &c, const DroneIn &a, const DroneIn &b, double extra = 0.0);

struct AcactDebug { std::string mode; double tc; };
std::array<double, 2> acactVelocity(const Config &c, const DroneIn &me, const std::vector<DroneIn> &others,
                                    const Vec2 &goal, bool emergency, AcactDebug *dbg = nullptr);

class GuardCore {
public:
    GuardCore(const Config &config, const std::vector<std::string> &ids);

    std::vector<Command> step(double t, const std::vector<DroneIn> &drones);
    bool eligible(const DroneIn &d) const;

    const Config &config() const { return _c; }
    Config &config() { return _c; }

    std::map<std::string, Own>          own;
    std::vector<std::pair<PairKey, PairEval>> pairs;   // insertion order, like the Python dict
    std::map<PairKey, double>           minSep;        // same layer (≤ V_SEP) min horizontal distance
    std::map<PairKey, double>           min3d;
    bool enabled = true;

private:
    bool  _releaseSafe(const DroneIn &d, const std::vector<DroneIn> &drones) const;
    Vec3  _velocity(const DroneIn &d, const std::vector<DroneIn> &drones, int level);

    Config _c;
    std::optional<double> _lastT;
    std::map<PairKey, double> _warnedT;
    std::vector<std::string>  _dropped;
    double _extra = 0.0;
};

} // namespace acact
