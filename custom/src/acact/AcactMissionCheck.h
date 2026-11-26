// ACACT engine — pre-flight check of user-defined missions (new, not in the Python guard)
//
// Every vehicle's mission is checked on its own (altitude, range, geofence, takeoff
// point, end action, endurance) and every pair of missions against each other
// (path proximity, simultaneous-start prediction, takeoff/landing pad spacing).
// Findings carry a code and numbers only; the GCS formats them (translation).
//
// Qt-free so that it runs in the regression tests (tools/acact_verify).
#pragma once

#include "AcactConfig.h"

#include <string>
#include <vector>

namespace acact {

namespace mav {
// MAV_CMD / MAV_FRAME values used here (common.xml)
constexpr int WAYPOINT = 16, LOITER_UNLIM = 17, LOITER_TURNS = 18, LOITER_TIME = 19, RTL = 20, LAND = 21, TAKEOFF = 22,
              LOITER_TO_ALT = 31, SPLINE_WAYPOINT = 82, VTOL_TAKEOFF = 84, VTOL_LAND = 85, DO_CHANGE_SPEED = 178,
              DO_JUMP = 177;
constexpr int F_GLOBAL = 0, F_MISSION = 2, F_GLOBAL_REL = 3, F_GLOBAL_INT = 5, F_GLOBAL_REL_INT = 6,
              F_TERRAIN = 10, F_TERRAIN_INT = 11;
} // namespace mav

struct MItem {
    int seq = 0, cmd = 0, frame = mav::F_GLOBAL_REL;
    double p1 = 0, p2 = 0, p3 = 0, p4 = 0, lat = 0, lon = 0, alt = 0;
};

struct Fence {
    bool inclusion = true;
    bool circle = true;
    double lat = 0, lon = 0, radius = 0;          // circle
    std::vector<std::pair<double, double>> poly;  // polygon (lat, lon)
};

struct VehicleMission {
    std::string id;
    bool controlled = true;   // PX4 multicopter the guard may fly (else only traffic)
    bool connected = true;
    double lat = 0, lon = 0;  // current position (NaN if unknown)
    double relAlt = 0;
    bool inAir = false;
    bool homeValid = false;
    double homeLat = 0, homeLon = 0, homeAmsl = 0;
    double batt = -1;         // % (−1 unknown)
    double cruise = 5.0;      // [m/s] PX4 MPC_XY_CRUISE (or mission default)
    double rtlAlt = 20.0;     // [m]
    double endurance = -1;    // [s] flight time on 100 % (vehicle profile); ≤ 0 → Limits::endurance
    std::vector<MItem> items; // as on the vehicle (seq 0 = first item, no home)
    std::vector<Fence> fences;
};

struct Limits {
    double maxAlt = 120.0;       // [m AGL] legal ceiling margin (KR 150 m)
    double minAlt = 3.0;         // [m] lowest cruise waypoint
    double maxRange = 1000.0;    // [m] from home
    double takeoffTol = 5.0;     // [m] mission takeoff vs vehicle position
    double padMin = 6.0;         // [m] takeoff/landing points of two vehicles
    double endurance = 900.0;    // [s] flight time on 100 % battery
    double battReserve = 25.0;   // [%] to land with
    double climb = 1.5, descend = 1.0, takeoffSpeed = 1.0, landSpeed = 0.7;   // [m/s]
};

enum class Level { Info = 0, Warn = 1, Error = 2 };

struct Issue {
    Level level = Level::Info;
    std::string code;     // see AcactMissionCheck.cc (also the translation key in the GCS)
    int seq = -1;         // mission item (vehicle seq), −1 = whole mission
    double a = 0, b = 0, c = 0;
    std::string other;    // other vehicle id (pair findings)
};

struct PathPt { double t, n, e, u; };   // time from start [s], local NEU [m]

struct VehicleReport {
    std::string id;
    std::vector<Issue> issues;
    int navItems = 0, syncPoints = 0;
    double length = 0, duration = 0, maxAlt = 0;
    std::vector<PathPt> path;     // 1 s samples (simultaneous-start timeline)
    Level worst() const;
};

struct PairReport {
    std::string a, b;
    double pathMin = 1e9, pathDz = 0, pathN = 0, pathE = 0;   // closest approach of the two tracks (|dz| < V_SEP)
    double timedMin = 1e9, timedAt = -1;                      // simultaneous start
    double padMin = 1e9;                                      // takeoff/landing points
    std::vector<Issue> issues;
};

struct MissionReport {
    std::vector<VehicleReport> vehicles;
    std::vector<PairReport> pairs;
    double originLat = 0, originLon = 0;
    bool ok() const;   // no Error
};

MissionReport checkMissions(const std::vector<VehicleMission> &vms, const Config &c, const Limits &lim);

} // namespace acact
