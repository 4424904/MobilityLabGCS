// C interface to the ACACT engine, for the Python comparison harness
// (tests/acact_compare.py loads it with ctypes and runs the original
// sim_check.py with this core in place of / next to core.py).
// Not used by the GCS itself.
#include "AcactCore.h"

#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>

using namespace acact;

extern "C" {

struct AcDrone {
    char   id[8];
    int    prio;
    int    fresh;
    double age;
    double f, r, u, vf, vr, vu;
    double rel_alt;
    int    in_air;
    char   mode[16];
    int    has_goal;
    double gf, gr;
    double rtl_alt;
    int    goal_hold;
    int    has_goal_alt;
    double goal_alt;
    int    has_home;
    double hf, hr;
};

// Config values, in this order (names as in config.py)
enum CfgIndex {
    C_STALE_PREDICT_MAX, C_DL_LOSS_T, C_STALE_DROP_T, C_DEGRADED_MARGIN, C_D_SAFE, C_D_EMERG, C_T_LOOK, C_V_SEP,
    C_RELEASE_MARGIN, C_RELEASE_HOLD, C_MIN_OWN_TIME, C_MIN_TAKEOVER_ALT, C_GOAL_HANDOFF, C_MAX_H_SPEED, C_MAX_CLIMB,
    C_EMERG_CLIMB_MAX, C_ALT_HOLD_KP, C_PAD_ZONE, C_SCENARIO_SPEED, C_ADVANCE_IN_AVOID,
    C_KPA, C_KPP, C_KPV, C_RS, C_TS, C_K_RH, C_K_CPA, C_GOAL_TOL,
    C_COUNT
};

int acact_cfg_count() { return C_COUNT; }

void *acact_new(const char *idsCsv, const double *cfg, int n)
{
    if (n != C_COUNT) {
        return nullptr;
    }
    Config c;
    c.stalePredictMax = cfg[C_STALE_PREDICT_MAX];
    c.dlLossT         = cfg[C_DL_LOSS_T];
    c.staleDropT      = cfg[C_STALE_DROP_T];
    c.degradedMargin  = cfg[C_DEGRADED_MARGIN];
    c.dSafe           = cfg[C_D_SAFE];
    c.dEmerg          = cfg[C_D_EMERG];
    c.tLook           = cfg[C_T_LOOK];
    c.vSep            = cfg[C_V_SEP];
    c.releaseMargin   = cfg[C_RELEASE_MARGIN];
    c.releaseHold     = cfg[C_RELEASE_HOLD];
    c.minOwnTime      = cfg[C_MIN_OWN_TIME];
    c.minTakeoverAlt  = cfg[C_MIN_TAKEOVER_ALT];
    c.goalHandoff     = cfg[C_GOAL_HANDOFF];
    c.maxHSpeed       = cfg[C_MAX_H_SPEED];
    c.maxClimb        = cfg[C_MAX_CLIMB];
    c.emergClimbMax   = cfg[C_EMERG_CLIMB_MAX];
    c.altHoldKp       = cfg[C_ALT_HOLD_KP];
    c.padZone         = cfg[C_PAD_ZONE];
    c.scenarioSpeed   = cfg[C_SCENARIO_SPEED];
    c.advanceInAvoid  = cfg[C_ADVANCE_IN_AVOID] != 0.0;
    c.acact.kpa       = cfg[C_KPA];
    c.acact.kpp       = cfg[C_KPP];
    c.acact.kpv       = cfg[C_KPV];
    c.acact.rs        = cfg[C_RS];
    c.acact.ts        = cfg[C_TS];
    c.acact.k_rh      = cfg[C_K_RH];
    c.acact.k_cpa     = cfg[C_K_CPA];
    c.acact.goalTol   = cfg[C_GOAL_TOL];

    std::vector<std::string> ids;
    std::stringstream ss(idsCsv ? idsCsv : "");
    std::string item;
    while (std::getline(ss, item, ',')) {
        if (!item.empty()) {
            ids.push_back(item);
        }
    }
    return new GuardCore(c, ids);
}

void acact_free(void *h) { delete static_cast<GuardCore *>(h); }

void acact_set_enabled(void *h, int on) { static_cast<GuardCore *>(h)->enabled = on != 0; }

// Returns bytes written (commands as lines "kind\tid\tv0\tv1\tv2\ttext"), or -needed if out is too small.
int acact_step(void *h, double t, const AcDrone *ds, int n, char *out, int outLen)
{
    GuardCore *g = static_cast<GuardCore *>(h);
    std::vector<DroneIn> in;
    in.reserve(n);
    for (int i = 0; i < n; i++) {
        const AcDrone &a = ds[i];
        DroneIn d;
        d.id = a.id;
        d.prio = a.prio;
        d.fresh = a.fresh != 0;
        d.age = a.age;
        d.f = a.f; d.r = a.r; d.u = a.u;
        d.vf = a.vf; d.vr = a.vr; d.vu = a.vu;
        d.relAlt = a.rel_alt;
        d.inAir = a.in_air != 0;
        d.mode = a.mode;
        if (a.has_goal) d.goal = Vec2 {a.gf, a.gr};
        d.rtlAlt = a.rtl_alt;
        d.goalHold = a.goal_hold != 0;
        if (a.has_goal_alt) d.goalAlt = a.goal_alt;
        if (a.has_home) d.home = Vec2 {a.hf, a.hr};
        in.push_back(d);
    }
    const auto cmds = g->step(t, in);
    std::string s;
    char buf[160];
    static const char *names[] = {"takeover", "vel", "release", "advance", "event"};
    for (const Command &c : cmds) {
        std::snprintf(buf, sizeof buf, "%s\t%s\t%.17g\t%.17g\t%.17g\t", names[static_cast<int>(c.kind)], c.id.c_str(),
                      c.v[0], c.v[1], c.v[2]);
        s += buf;
        s += c.text;
        s += "\n";
    }
    if (static_cast<int>(s.size()) + 1 > outLen) {
        return -static_cast<int>(s.size() + 1);
    }
    std::memcpy(out, s.c_str(), s.size() + 1);
    return static_cast<int>(s.size());
}

// owned, lock, yielding, takeovers, owned_time, hold_u, t_take, has_t_clear, t_clear
int acact_own(void *h, const char *id, double *out9)
{
    GuardCore *g = static_cast<GuardCore *>(h);
    auto it = g->own.find(id);
    if (it == g->own.end()) {
        return 0;
    }
    const Own &o = it->second;
    out9[0] = o.owned; out9[1] = o.lock; out9[2] = o.yielding; out9[3] = o.takeovers; out9[4] = o.ownedTime;
    out9[5] = o.holdU; out9[6] = o.tTake; out9[7] = o.tClear ? 1 : 0; out9[8] = o.tClear ? *o.tClear : 0;
    return 1;
}

// Pairs of the last step: lines "a\tb\tlevel\td_now\td_cpa\tt_cpa\tdz\tclear\tmin_sep\tmin_3d"
int acact_pairs(void *h, char *out, int outLen)
{
    GuardCore *g = static_cast<GuardCore *>(h);
    std::string s;
    char buf[256];
    for (const auto &[k, pe] : g->pairs) {
        const auto ms = g->minSep.find(k);
        const auto m3 = g->min3d.find(k);
        std::snprintf(buf, sizeof buf, "%s\t%s\t%d\t%.17g\t%.17g\t%.17g\t%.17g\t%d\t%.17g\t%.17g\n", k.first.c_str(),
                      k.second.c_str(), pe.level, pe.dNow, pe.dCpa, pe.tCpa, pe.dz, pe.clear ? 1 : 0,
                      ms == g->minSep.end() ? 1e9 : ms->second, m3 == g->min3d.end() ? 1e9 : m3->second);
        s += buf;
    }
    if (static_cast<int>(s.size()) + 1 > outLen) {
        return -static_cast<int>(s.size() + 1);
    }
    std::memcpy(out, s.c_str(), s.size() + 1);
    return static_cast<int>(s.size());
}

} // extern "C"

#include "AcactScenarios.h"

extern "C" {

// Missions of a scenario as lines "id\ttype\tf\tr\thasAlt\talt\thasHold\thold\tv\ttag"
// cfg: same vector as acact_new plus (fleet size handled by the caller's config values)
int acact_build(const char *idsCsv, const char *profile, const char *name, const char *mode,
                double dSafe, char *out, int outLen)
{
    Config c;
    c.profile = profile;
    c.dSafe = dSafe;
    std::vector<std::string> ids;
    std::stringstream ss(idsCsv ? idsCsv : "");
    std::string item;
    while (std::getline(ss, item, ',')) {
        if (!item.empty()) ids.push_back(item);
    }
    Scenarios sc(c, ids);
    const auto m = sc.build(name, mode);
    static const char *types[] = {"takeoff", "sync", "speed", "wp", "land"};
    std::string s;
    char buf[320];
    for (const auto &id : ids) {
        auto it = m.find(id);
        if (it == m.end()) continue;
        for (const Item &x : it->second) {
            std::snprintf(buf, sizeof buf, "%s\t%s\t%.17g\t%.17g\t%d\t%.17g\t%d\t%.17g\t%.17g\t%s\n", id.c_str(),
                          types[x.type], x.f, x.r, x.alt ? 1 : 0, x.alt ? *x.alt : 0.0, x.hasHold ? 1 : 0, x.hold, x.v,
                          x.tag.c_str());
            s += buf;
        }
    }
    if (static_cast<int>(s.size()) + 1 > outLen) return -static_cast<int>(s.size() + 1);
    std::memcpy(out, s.c_str(), s.size() + 1);
    return static_cast<int>(s.size());
}

// lat/lon → F/R and back, for the geo comparison
void acact_frame(double lat0, double lon0, double bearing, double lat, double lon, double f, double r, double *out4)
{
    Frame fr(lat0, lon0, bearing);
    const auto a = fr.llToFr(lat, lon);
    const auto b = fr.frToLl(f, r);
    out4[0] = a[0]; out4[1] = a[1]; out4[2] = b[0]; out4[3] = b[1];
}

} // extern "C"
