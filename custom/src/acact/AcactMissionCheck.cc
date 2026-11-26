// ACACT engine — pre-flight check of user-defined missions. See AcactMissionCheck.h.
//
// Issue codes
//   per vehicle                                   level  numbers
//   EMPTY          no mission                     E
//   NO_NAV         no position item               E
//   NO_TAKEOFF     on the ground, first nav item  W
//                  is not a takeoff
//   TAKEOFF_FAR    takeoff point vs position      E      a = distance, b = tolerance
//   ALT_HIGH       item above the ceiling         E      a = alt, b = limit
//   ALT_LOW        cruise item too low            E      a = alt, b = limit
//   RANGE          item too far from home         E      a = distance, b = limit
//   FENCE_OUT      track leaves inclusion fence   E
//   FENCE_IN       track enters exclusion fence   E
//   ALT_AMSL       AMSL frame, converted          I      a = home AMSL
//   ALT_TERRAIN    terrain frame, unchecked       W
//   NO_END         no LAND / RTL at the end       W
//   JUMP           DO_JUMP (timeline once only)   I
//   SYNC           LOITER_UNLIM count             I      a = count
//   ENDURANCE      longer than the battery allows E      a = need %, b = usable %
//   BATT           not enough charge now          W      a = need %, b = battery %, c = reserve %
//   NOT_CONNECTED  link down                      W
//   pair (other = the other vehicle)
//   PATH_NEAR      tracks pass close (|dz|<V_SEP) W      a = distance, b = dz       (ACACT will resolve)
//   PATH_NEAR_UNGUARDED  … and neither vehicle can be flown by the guard   E
//   TIMED_NEAR     simultaneous start, close      W      a = distance, b = time [s]
//   PAD_NEAR       takeoff/landing points close   E      a = distance, b = limit
//   SAME_MISSION   the same mission on both       E
#include "AcactMissionCheck.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace acact {

namespace {
constexpr double kM = 111320.0;
constexpr double kPi = 3.14159265358979323846;

struct Local {
    double lat0, lon0, c0;
    Local(double la, double lo) : lat0(la), lon0(lo), c0(std::cos(la * kPi / 180.0)) {}
    void ne(double lat, double lon, double &n, double &e) const
    {
        n = (lat - lat0) * kM;
        e = (lon - lon0) * kM * c0;
    }
};

bool isNav(int cmd)
{
    switch (cmd) {
    case mav::WAYPOINT: case mav::LOITER_UNLIM: case mav::LOITER_TURNS: case mav::LOITER_TIME: case mav::RTL:
    case mav::LAND: case mav::TAKEOFF: case mav::LOITER_TO_ALT: case mav::SPLINE_WAYPOINT: case mav::VTOL_TAKEOFF:
    case mav::VTOL_LAND:
        return true;
    default:
        return false;
    }
}

struct P3 { double n, e, u; int seq; };

struct Walk {
    std::vector<PathPt> timeline;   // 0.5 s
    std::vector<P3> dense;          // ~1 m
    std::vector<std::pair<double, double>> pads;   // takeoff / landing points (n, e)
    std::vector<P3> navPts;         // target of every nav item
    double t = 0, n = 0, e = 0, u = 0;
    void sample(int seq)
    {
        timeline.push_back({t, n, e, u});
        (void)seq;
    }
    // straight move to (n1, e1, u1) taking `dur` seconds
    void move(double n1, double e1, double u1, double dur, int seq)
    {
        const double n0 = n, e0 = e, u0 = u, t0 = t;
        const double len = std::sqrt((n1 - n0) * (n1 - n0) + (e1 - e0) * (e1 - e0) + (u1 - u0) * (u1 - u0));
        const int steps = std::max(1, static_cast<int>(std::ceil(len)));
        for (int i = 1; i <= steps; i++) {
            const double f = static_cast<double>(i) / steps;
            dense.push_back({n0 + (n1 - n0) * f, e0 + (e1 - e0) * f, u0 + (u1 - u0) * f, seq});
        }
        const double tEnd = t0 + dur;
        double ts = std::floor(t0 / 0.5) * 0.5 + 0.5;
        for (; ts < tEnd; ts += 0.5) {
            const double f = dur > 0 ? (ts - t0) / dur : 1.0;
            timeline.push_back({ts, n0 + (n1 - n0) * f, e0 + (e1 - e0) * f, u0 + (u1 - u0) * f});
        }
        timeline.push_back({tEnd, n1, e1, u1});
        n = n1; e = e1; u = u1; t = tEnd;
    }
    void hold(double dur)
    {
        if (dur <= 0) {
            return;
        }
        t += dur;
        timeline.push_back({t, n, e, u});
    }
    PathPt at(double tq) const
    {
        if (timeline.empty()) {
            return {tq, n, e, u};
        }
        if (tq <= timeline.front().t) {
            return timeline.front();
        }
        if (tq >= timeline.back().t) {
            return {tq, timeline.back().n, timeline.back().e, timeline.back().u};
        }
        // linear interpolation between the samples around tq
        auto it = std::lower_bound(timeline.begin(), timeline.end(), tq, [](const PathPt &p, double v) { return p.t < v; });
        const PathPt &b = *it, &a = *(it - 1);
        const double f = b.t > a.t ? (tq - a.t) / (b.t - a.t) : 1.0;
        return {tq, a.n + (b.n - a.n) * f, a.e + (b.e - a.e) * f, a.u + (b.u - a.u) * f};
    }
};

bool inPoly(const std::vector<std::pair<double, double>> &poly, double n, double e)
{
    bool in = false;
    for (size_t i = 0, j = poly.size() - 1; i < poly.size(); j = i++) {
        const double ni = poly[i].first, ei = poly[i].second, nj = poly[j].first, ej = poly[j].second;
        if (((ei > e) != (ej > e)) && (n < (nj - ni) * (e - ei) / (ej - ei) + ni)) {
            in = !in;
        }
    }
    return in;
}

Issue mk(Level l, const char *code, int seq = -1, double a = 0, double b = 0, double c = 0)
{
    Issue i;
    i.level = l;
    i.code = code;
    i.seq = seq;
    i.a = a;
    i.b = b;
    i.c = c;
    return i;
}
} // namespace

Level VehicleReport::worst() const
{
    Level w = Level::Info;
    for (const Issue &i : issues) {
        w = std::max(w, i.level);
    }
    return w;
}

bool MissionReport::ok() const
{
    for (const VehicleReport &v : vehicles) {
        if (v.worst() == Level::Error) {
            return false;
        }
    }
    for (const PairReport &p : pairs) {
        for (const Issue &i : p.issues) {
            if (i.level == Level::Error) {
                return false;
            }
        }
    }
    return true;
}

MissionReport checkMissions(const std::vector<VehicleMission> &vms, const Config &c, const Limits &lim)
{
    MissionReport rep;
    // origin: first known position
    double la0 = std::numeric_limits<double>::quiet_NaN(), lo0 = la0;
    for (const VehicleMission &vm : vms) {
        const double la = vm.homeValid ? vm.homeLat : vm.lat, lo = vm.homeValid ? vm.homeLon : vm.lon;
        if (!std::isnan(la) && !std::isnan(lo) && (la != 0 || lo != 0)) {
            la0 = la;
            lo0 = lo;
            break;
        }
    }
    if (std::isnan(la0)) {
        for (const VehicleMission &vm : vms) {
            for (const MItem &it : vm.items) {
                if (isNav(it.cmd) && (it.lat != 0 || it.lon != 0)) {
                    la0 = it.lat;
                    lo0 = it.lon;
                    break;
                }
            }
            if (!std::isnan(la0)) {
                break;
            }
        }
    }
    if (std::isnan(la0)) {
        la0 = lo0 = 0;
    }
    rep.originLat = la0;
    rep.originLon = lo0;
    const Local L(la0, lo0);

    std::vector<Walk> walks(vms.size());
    std::vector<bool> hasPath(vms.size(), false);

    for (size_t vi = 0; vi < vms.size(); vi++) {
        const VehicleMission &vm = vms[vi];
        VehicleReport vr;
        vr.id = vm.id;
        Walk &w = walks[vi];

        if (!vm.connected) {
            vr.issues.push_back(mk(Level::Warn, "NOT_CONNECTED"));
        }
        double hn = 0, he = 0;
        const bool posKnown = !std::isnan(vm.lat) && !std::isnan(vm.lon) && (vm.lat != 0 || vm.lon != 0);
        if (vm.homeValid) {
            L.ne(vm.homeLat, vm.homeLon, hn, he);
        } else if (posKnown) {
            L.ne(vm.lat, vm.lon, hn, he);
        }
        if (posKnown) {
            L.ne(vm.lat, vm.lon, w.n, w.e);
        } else {
            w.n = hn;
            w.e = he;
        }
        w.u = vm.inAir ? vm.relAlt : 0.0;
        w.sample(-1);

        if (vm.items.empty()) {
            if (vm.controlled) {
                vr.issues.push_back(mk(Level::Error, "EMPTY"));
            }
            rep.vehicles.push_back(vr);
            continue;
        }

        double speed = vm.cruise > 0.1 ? vm.cruise : 5.0;
        bool firstNav = true, ended = false, amslTold = false, terrainTold = false;
        int lastNavCmd = 0;
        for (const MItem &it : vm.items) {
            if (it.cmd == mav::DO_CHANGE_SPEED) {
                if (it.p2 > 0) {
                    speed = it.p2;
                }
                continue;
            }
            if (it.cmd == mav::DO_JUMP) {
                vr.issues.push_back(mk(Level::Info, "JUMP", it.seq));
                continue;
            }
            if (!isNav(it.cmd) || ended) {
                continue;
            }
            vr.navItems++;
            lastNavCmd = it.cmd;
            // target
            double tn = w.n, te = w.e;
            if (it.cmd == mav::RTL) {
                tn = hn;
                te = he;
            } else if (it.lat != 0 || it.lon != 0) {
                L.ne(it.lat, it.lon, tn, te);
            }
            double alt = it.alt;
            if (it.frame == mav::F_GLOBAL || it.frame == mav::F_GLOBAL_INT) {
                alt = it.alt - vm.homeAmsl;
                if (!amslTold) {
                    vr.issues.push_back(mk(Level::Info, "ALT_AMSL", it.seq, vm.homeAmsl));
                    amslTold = true;
                }
            } else if (it.frame == mav::F_TERRAIN || it.frame == mav::F_TERRAIN_INT) {
                if (!terrainTold) {
                    vr.issues.push_back(mk(Level::Warn, "ALT_TERRAIN", it.seq));
                    terrainTold = true;
                }
            }
            const bool isTakeoff = it.cmd == mav::TAKEOFF || it.cmd == mav::VTOL_TAKEOFF;
            const bool isLand = it.cmd == mav::LAND || it.cmd == mav::VTOL_LAND;

            if (firstNav && !vm.inAir && !isTakeoff) {
                vr.issues.push_back(mk(Level::Warn, "NO_TAKEOFF", it.seq));
            }
            if (isTakeoff && !vm.inAir && firstNav && posKnown && (it.lat != 0 || it.lon != 0)) {
                const double d = std::hypot(tn - w.n, te - w.e);
                if (d > lim.takeoffTol) {
                    vr.issues.push_back(mk(Level::Error, "TAKEOFF_FAR", it.seq, d, lim.takeoffTol));
                }
            }
            firstNav = false;

            // limits on the target
            if (!isLand && alt > lim.maxAlt) {
                vr.issues.push_back(mk(Level::Error, "ALT_HIGH", it.seq, alt, lim.maxAlt));
            }
            if (!isTakeoff && !isLand && it.cmd != mav::RTL && alt < lim.minAlt) {
                vr.issues.push_back(mk(Level::Error, "ALT_LOW", it.seq, alt, lim.minAlt));
            }
            const double rng = std::hypot(tn - hn, te - he);
            if (rng > lim.maxRange) {
                vr.issues.push_back(mk(Level::Error, "RANGE", it.seq, rng, lim.maxRange));
            }

            // fly it
            const size_t d0 = w.dense.size();
            if (isTakeoff) {
                // PX4 climbs vertically at the takeoff point, then flies on
                w.pads.push_back({w.n, w.e});
                w.move(w.n, w.e, alt, std::max(0.0, alt - w.u) / lim.takeoffSpeed, it.seq);
            } else if (it.cmd == mav::RTL) {
                const double ua = std::max(w.u, vm.rtlAlt);
                w.move(w.n, w.e, ua, std::max(0.0, ua - w.u) / lim.climb, it.seq);
                const double h = std::hypot(tn - w.n, te - w.e);
                w.move(tn, te, ua, h / speed, it.seq);
                w.pads.push_back({tn, te});
                w.move(tn, te, 0.0, ua / lim.landSpeed, it.seq);
                ended = true;
            } else if (isLand) {
                const double h = std::hypot(tn - w.n, te - w.e);
                w.move(tn, te, w.u, h / speed, it.seq);
                w.pads.push_back({tn, te});
                w.move(tn, te, 0.0, w.u / lim.landSpeed, it.seq);
                ended = true;
            } else {
                const double h = std::hypot(tn - w.n, te - w.e);
                const double dz = alt - w.u;
                const double dur = std::max(h / speed, dz > 0 ? dz / lim.climb : -dz / lim.descend);
                w.move(tn, te, alt, dur, it.seq);
                double holdS = 0;
                if (it.cmd == mav::WAYPOINT || it.cmd == mav::LOITER_TIME) {
                    holdS = std::max(0.0, it.p1);
                } else if (it.cmd == mav::LOITER_TURNS) {
                    holdS = std::fabs(it.p1) * 2 * kPi * std::max(5.0, std::fabs(it.p3)) / std::max(1.0, speed);
                } else if (it.cmd == mav::LOITER_UNLIM) {
                    vr.syncPoints++;
                }
                w.hold(holdS);
            }
            w.navPts.push_back({tn, te, alt, it.seq});

            // fences along the new part of the track (every ~5 m)
            if (!vm.fences.empty()) {
                bool anyIncl = false;
                for (const Fence &f : vm.fences) {
                    anyIncl = anyIncl || f.inclusion;
                }
                bool toldOut = false, toldIn = false;
                for (size_t k = d0; k < w.dense.size(); k += 5) {
                    const P3 &p = w.dense[k];
                    bool inAnyIncl = false, inExcl = false;
                    for (const Fence &f : vm.fences) {
                        bool inside;
                        if (f.circle) {
                            double fn, fe;
                            L.ne(f.lat, f.lon, fn, fe);
                            inside = std::hypot(p.n - fn, p.e - fe) <= f.radius;
                        } else {
                            std::vector<std::pair<double, double>> pl;
                            for (const auto &q : f.poly) {
                                double fn, fe;
                                L.ne(q.first, q.second, fn, fe);
                                pl.push_back({fn, fe});
                            }
                            inside = pl.size() >= 3 && inPoly(pl, p.n, p.e);
                        }
                        if (f.inclusion && inside) {
                            inAnyIncl = true;
                        }
                        if (!f.inclusion && inside) {
                            inExcl = true;
                        }
                    }
                    if (anyIncl && !inAnyIncl && !toldOut) {
                        vr.issues.push_back(mk(Level::Error, "FENCE_OUT", p.seq));
                        toldOut = true;
                    }
                    if (inExcl && !toldIn) {
                        vr.issues.push_back(mk(Level::Error, "FENCE_IN", p.seq));
                        toldIn = true;
                    }
                }
            }
        }

        if (vr.navItems == 0) {
            vr.issues.push_back(mk(Level::Error, "NO_NAV"));
        } else if (lastNavCmd != mav::LAND && lastNavCmd != mav::VTOL_LAND && lastNavCmd != mav::RTL) {
            vr.issues.push_back(mk(Level::Warn, "NO_END"));
        }
        if (vr.syncPoints > 0) {
            vr.issues.push_back(mk(Level::Info, "SYNC", -1, vr.syncPoints));
        }
        for (size_t k = 1; k < w.dense.size(); k++) {
            const P3 &a = w.dense[k - 1], &b = w.dense[k];
            vr.length += std::sqrt((b.n - a.n) * (b.n - a.n) + (b.e - a.e) * (b.e - a.e) + (b.u - a.u) * (b.u - a.u));
            vr.maxAlt = std::max(vr.maxAlt, b.u);
        }
        vr.duration = w.t;
        const double need = 100.0 * w.t / std::max(60.0, lim.endurance);
        if (vr.navItems > 0) {
            if (need > 100.0 - lim.battReserve) {
                vr.issues.push_back(mk(Level::Error, "ENDURANCE", -1, need, 100.0 - lim.battReserve));
            } else if (vm.batt >= 0 && vm.batt - need < lim.battReserve) {
                vr.issues.push_back(mk(Level::Warn, "BATT", -1, need, vm.batt, lim.battReserve));
            }
        }
        vr.path = w.timeline;
        hasPath[vi] = vr.navItems > 0;
        rep.vehicles.push_back(vr);
    }

    // ---- pairs --------------------------------------------------------------
    for (size_t i = 0; i < vms.size(); i++) {
        for (size_t j = i + 1; j < vms.size(); j++) {
            if (!hasPath[i] || !hasPath[j]) {
                continue;
            }
            const Walk &A = walks[i], &B = walks[j];
            PairReport pr;
            pr.a = vms[i].id;
            pr.b = vms[j].id;
            auto addIssue = [&](Issue is) {
                is.other = pr.b;
                pr.issues.push_back(is);
            };
            // tracks
            for (const P3 &p : A.dense) {
                if (p.u < 0.5) {
                    continue;
                }
                for (const P3 &q : B.dense) {
                    if (q.u < 0.5 || std::fabs(p.u - q.u) >= c.vSep) {
                        continue;
                    }
                    const double d = std::hypot(p.n - q.n, p.e - q.e);
                    if (d < pr.pathMin) {
                        pr.pathMin = d;
                        pr.pathDz = q.u - p.u;
                        pr.pathN = (p.n + q.n) / 2;
                        pr.pathE = (p.e + q.e) / 2;
                    }
                }
            }
            if (pr.pathMin < c.dSafe) {
                const bool guarded = vms[i].controlled || vms[j].controlled;
                addIssue(mk(guarded ? Level::Warn : Level::Error, guarded ? "PATH_NEAR" : "PATH_NEAR_UNGUARDED", -1, pr.pathMin, pr.pathDz));
            }
            // simultaneous start
            const double tEnd = std::max(A.t, B.t);
            for (double t = 0; t <= tEnd; t += 0.5) {
                const PathPt p = A.at(t), q = B.at(t);
                if (p.u < 0.5 || q.u < 0.5 || std::fabs(p.u - q.u) >= c.vSep) {
                    continue;
                }
                const double d = std::hypot(p.n - q.n, p.e - q.e);
                if (d < pr.timedMin) {
                    pr.timedMin = d;
                    pr.timedAt = t;
                }
            }
            if (pr.timedMin < c.dEmerg) {
                addIssue(mk(Level::Warn, "TIMED_NEAR", -1, pr.timedMin, pr.timedAt));
            }
            // pads (below MIN_TAKEOVER_ALT the guard does not act)
            for (const auto &pa : A.pads) {
                for (const auto &pb : B.pads) {
                    pr.padMin = std::min(pr.padMin, std::hypot(pa.first - pb.first, pa.second - pb.second));
                }
            }
            if (pr.padMin < lim.padMin) {
                addIssue(mk(Level::Error, "PAD_NEAR", -1, pr.padMin, lim.padMin));
            }
            // the same mission loaded twice
            if (A.navPts.size() == B.navPts.size() && A.navPts.size() >= 2) {
                bool same = true;
                for (size_t k = 0; k < A.navPts.size() && same; k++) {
                    same = std::hypot(A.navPts[k].n - B.navPts[k].n, A.navPts[k].e - B.navPts[k].e) < 1.0 &&
                           std::fabs(A.navPts[k].u - B.navPts[k].u) < 1.0;
                }
                if (same) {
                    addIssue(mk(Level::Error, "SAME_MISSION"));
                }
            }
            rep.pairs.push_back(pr);
        }
    }
    return rep;
}

} // namespace acact
