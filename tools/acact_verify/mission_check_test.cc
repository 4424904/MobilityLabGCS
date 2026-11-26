// Regression tests for the user-mission pre-flight check (custom/src/acact/AcactMissionCheck)
//   g++ -std=c++17 -I custom/src/acact custom/src/acact/AcactMissionCheck.cc tools/acact_verify/mission_check_test.cc
#include "AcactMissionCheck.h"

#include <cmath>
#include <cstdio>
#include <string>

using namespace acact;

static int g_fail = 0, g_pass = 0;
#define CHECK(cond, what)                                                       \
    do {                                                                        \
        if (cond) { g_pass++; }                                                 \
        else { g_fail++; std::printf("FAIL  %s  (%s:%d)\n", what, __FILE__, __LINE__); } \
    } while (0)

static const double LA = 37.21, LO = 126.83;
static double dLat(double n) { return LA + n / 111320.0; }
static double dLon(double e) { return LO + e / (111320.0 * std::cos(LA * 3.14159265358979323846 / 180.0)); }

static MItem item(int seq, int cmd, double n, double e, double alt, double p1 = 0, int frame = mav::F_GLOBAL_REL)
{
    MItem i;
    i.seq = seq;
    i.cmd = cmd;
    i.frame = frame;
    i.p1 = p1;
    i.lat = dLat(n);
    i.lon = dLon(e);
    i.alt = alt;
    return i;
}

static VehicleMission veh(const std::string &id, double n, double e)
{
    VehicleMission v;
    v.id = id;
    v.lat = v.homeLat = dLat(n);
    v.lon = v.homeLon = dLon(e);
    v.homeValid = true;
    v.batt = 100;
    v.cruise = 3.0;
    return v;
}

// takeoff at (n,e) → wp (n2,e2) → land there
static void simple(VehicleMission &v, double n2, double e2, double alt = 10)
{
    const double n = (v.homeLat - LA) * 111320.0, e = (v.homeLon - LO) * 111320.0 * std::cos(LA * 3.14159265358979323846 / 180.0);
    v.items = {item(0, mav::TAKEOFF, n, e, alt), item(1, mav::WAYPOINT, n2, e2, alt), item(2, mav::LAND, n2, e2, 0)};
}

static bool has(const std::vector<Issue> &is, const char *code)
{
    for (const Issue &i : is) {
        if (i.code == code) {
            return true;
        }
    }
    return false;
}

static const VehicleReport &vr(const MissionReport &r, const char *id)
{
    for (const VehicleReport &v : r.vehicles) {
        if (v.id == id) {
            return v;
        }
    }
    static VehicleReport none;
    return none;
}

int main()
{
    Config c;
    c.applyFleetSize(2);
    Limits lim;

    {   // 1. two parallel missions 40 m apart: clean
        auto a = veh("D1", 0, 0), b = veh("D2", 0, 40);
        simple(a, 60, 0);
        simple(b, 60, 40);
        const auto r = checkMissions({a, b}, c, lim);
        CHECK(r.ok(), "parallel: ok");
        CHECK(r.pairs.size() == 1 && r.pairs[0].issues.empty(), "parallel: no pair issue");
        CHECK(std::fabs(r.pairs[0].pathMin - 40.0) < 1.0, "parallel: path distance 40 m");
        CHECK(vr(r, "D1").navItems == 3 && std::fabs(vr(r, "D1").length - (10 + 60 + 10)) < 1.0, "parallel: length");
        CHECK(vr(r, "D1").duration > 60.0 / 3.0 + 10 && vr(r, "D1").duration < 60.0, "parallel: duration plausible");
    }
    {   // 2. head-on at the same altitude: tracks meet, guard will resolve (warning, not error)
        auto a = veh("D1", 0, 0), b = veh("D2", 0, 40);
        // same line, opposite directions; land points off the line
        a.items = {item(0, mav::TAKEOFF, 0, 0, 10), item(1, mav::WAYPOINT, 0, 60, 10), item(2, mav::LAND, 10, 60, 0)};
        b.items = {item(0, mav::TAKEOFF, 0, 40, 10), item(1, mav::WAYPOINT, 0, -20, 10), item(2, mav::LAND, -10, -20, 0)};
        const auto r = checkMissions({a, b}, c, lim);
        CHECK(r.ok(), "head-on: no error");
        CHECK(has(r.pairs[0].issues, "PATH_NEAR"), "head-on: PATH_NEAR");
        CHECK(has(r.pairs[0].issues, "TIMED_NEAR"), "head-on: TIMED_NEAR");
        CHECK(r.pairs[0].timedAt > 0, "head-on: time of closest approach");
    }
    {   // 3. head-on but 10 m apart vertically: no conflict
        auto a = veh("D1", 0, 0), b = veh("D2", 0, 40);
        a.items = {item(0, mav::TAKEOFF, 0, 0, 10), item(1, mav::WAYPOINT, 10, 60, 10), item(2, mav::LAND, 10, 60, 0)};
        b.items = {item(0, mav::TAKEOFF, 0, 40, 20), item(1, mav::WAYPOINT, -10, -20, 20), item(2, mav::LAND, -10, -20, 0)};
        const auto r = checkMissions({a, b}, c, lim);
        CHECK(!has(r.pairs[0].issues, "PATH_NEAR") || r.pairs[0].pathMin > 5, "layers: separated except climb/descent");
        CHECK(!has(r.pairs[0].issues, "TIMED_NEAR"), "layers: no timed conflict");
    }
    {   // 4. altitude limits
        auto a = veh("D1", 0, 0);
        a.items = {item(0, mav::TAKEOFF, 0, 0, 10), item(1, mav::WAYPOINT, 50, 0, 150), item(2, mav::WAYPOINT, 60, 0, 1.0),
                   item(3, mav::LAND, 60, 0, 0)};
        const auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "ALT_HIGH"), "ALT_HIGH");
        CHECK(has(vr(r, "D1").issues, "ALT_LOW"), "ALT_LOW");
        CHECK(!r.ok(), "altitude: not ok");
    }
    {   // 5. takeoff point is somewhere else (wrong mission)
        auto a = veh("D1", 0, 0);
        a.items = {item(0, mav::TAKEOFF, 30, 0, 10), item(1, mav::WAYPOINT, 60, 0, 10), item(2, mav::LAND, 60, 0, 0)};
        const auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "TAKEOFF_FAR"), "TAKEOFF_FAR");
    }
    {   // 6. range
        auto a = veh("D1", 0, 0);
        simple(a, 1500, 0);
        const auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "RANGE"), "RANGE");
    }
    {   // 7. fences
        auto a = veh("D1", 0, 0);
        simple(a, 80, 0);
        Fence f;
        f.inclusion = true;
        f.circle = true;
        f.lat = LA;
        f.lon = LO;
        f.radius = 50;
        a.fences = {f};
        auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "FENCE_OUT"), "FENCE_OUT");
        Fence x;
        x.inclusion = false;
        x.circle = false;
        x.poly = {{dLat(20), dLon(-5)}, {dLat(20), dLon(5)}, {dLat(30), dLon(5)}, {dLat(30), dLon(-5)}};
        f.radius = 200;
        a.fences = {f, x};
        r = checkMissions({a}, c, lim);
        CHECK(!has(vr(r, "D1").issues, "FENCE_OUT"), "inside big inclusion");
        CHECK(has(vr(r, "D1").issues, "FENCE_IN"), "FENCE_IN (crosses exclusion box)");
    }
    {   // 8. pads too close, same mission
        auto a = veh("D1", 0, 0), b = veh("D2", 0, 3);
        simple(a, 60, 0);
        simple(b, 60, 0);
        b.items[0] = item(0, mav::TAKEOFF, 0, 3, 10);
        auto r = checkMissions({a, b}, c, lim);
        CHECK(has(r.pairs[0].issues, "PAD_NEAR"), "PAD_NEAR");
        auto b2 = veh("D2", 0, 0.2);
        b2.items = a.items;
        r = checkMissions({a, b2}, c, lim);
        CHECK(has(r.pairs[0].issues, "SAME_MISSION"), "SAME_MISSION");
    }
    {   // 9. end action
        auto a = veh("D1", 0, 0);
        a.items = {item(0, mav::TAKEOFF, 0, 0, 10), item(1, mav::WAYPOINT, 60, 0, 10)};
        auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "NO_END"), "NO_END");
        MItem rtl;
        rtl.seq = 2;
        rtl.cmd = mav::RTL;
        a.items.push_back(rtl);
        r = checkMissions({a}, c, lim);
        CHECK(!has(vr(r, "D1").issues, "NO_END"), "RTL ends the mission");
        CHECK(vr(r, "D1").path.back().u < 0.01, "RTL lands");
    }
    {   // 10. endurance and battery
        auto a = veh("D1", 0, 0);
        a.items = {item(0, mav::TAKEOFF, 0, 0, 10), item(1, mav::WAYPOINT, 300, 0, 10, 600), item(2, mav::LAND, 300, 0, 0)};
        auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "ENDURANCE"), "ENDURANCE (10 min hold on a 15 min battery)");
        a.items[1].p1 = 120;
        a.batt = 40;
        r = checkMissions({a}, c, lim);
        CHECK(!has(vr(r, "D1").issues, "ENDURANCE") && has(vr(r, "D1").issues, "BATT"), "BATT (40 %)");
    }
    {   // 11. AMSL frame converted with the home altitude
        auto a = veh("D1", 0, 0);
        a.homeAmsl = 50;
        a.items = {item(0, mav::TAKEOFF, 0, 0, 10), item(1, mav::WAYPOINT, 50, 0, 60, 0, mav::F_GLOBAL), item(2, mav::LAND, 50, 0, 0)};
        const auto r = checkMissions({a}, c, lim);
        CHECK(has(vr(r, "D1").issues, "ALT_AMSL") && !has(vr(r, "D1").issues, "ALT_HIGH") && std::fabs(vr(r, "D1").maxAlt - 10) < 0.5,
              "AMSL 60 m with home 50 m = 10 m");
    }
    {   // 12. neither vehicle controllable → error
        auto a = veh("D1", 0, 0), b = veh("D2", 0, 40);
        simple(a, 0, 60);
        simple(b, 0, -20);
        a.items[1] = item(1, mav::WAYPOINT, 10, 60, 10);
        a.items[2] = item(2, mav::LAND, 10, 60, 0);
        b.items[1] = item(1, mav::WAYPOINT, -10, -20, 10);
        b.items[2] = item(2, mav::LAND, -10, -20, 0);
        a.controlled = b.controlled = false;
        const auto r = checkMissions({a, b}, c, lim);
        CHECK(has(r.pairs[0].issues, "PATH_NEAR_UNGUARDED") && !r.ok(), "PATH_NEAR_UNGUARDED");
    }
    {   // 13. empty mission, sync points, speed change
        auto a = veh("D1", 0, 0), b = veh("D2", 0, 40);
        b.items = {item(0, mav::TAKEOFF, 0, 40, 10), item(1, mav::LOITER_UNLIM, 30, 40, 10), item(3, mav::LAND, 30, 40, 0)};
        MItem sp;
        sp.seq = 2;
        sp.cmd = mav::DO_CHANGE_SPEED;
        sp.p2 = 1.0;
        b.items.insert(b.items.begin() + 2, sp);
        const auto r = checkMissions({a, b}, c, lim);
        CHECK(has(vr(r, "D1").issues, "EMPTY"), "EMPTY");
        CHECK(vr(r, "D2").syncPoints == 1 && has(vr(r, "D2").issues, "SYNC"), "SYNC");
    }
    std::printf("mission_check_test: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
