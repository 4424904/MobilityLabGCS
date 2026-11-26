#include "AcactCore.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace acact {

namespace {
constexpr double EPS = 1e-9;
inline double norm(double x, double y) { return std::hypot(x, y); }
}

std::string fmt1(double v)
{
    char b[64];
    std::snprintf(b, sizeof b, "%.1f", v);
    return b;
}

std::string fmt0(double v)
{
    char b[64];
    std::snprintf(b, sizeof b, "%.0f", v);
    return b;
}

// ═══════════════════════════════════════════════════════════════
// geometry
// ═══════════════════════════════════════════════════════════════
Predicted predicted(const Config &C, const DroneIn &d)
{
    // STALE drone: we do not know whether it kept going or stopped, so treat it
    // as a circle covering both (centre = last + v·age/2, inflated radius).
    // PX4 climbs to the RTL altitude after COM_DL_LOSS_T.
    if (d.fresh) {
        return {d.f, d.r, d.u, d.vf, d.vr, 0.0};
    }
    const double a = std::min(d.age, C.stalePredictMax);
    const double sp = norm(d.vf, d.vr);
    const double infl = std::min(sp * a / 2.0 + 0.5 * a, 10.0);
    double u = d.u;
    const double climb = std::max(d.rtlAlt - d.relAlt, 0.0);
    if (d.age > C.dlLossT + climb / 1.0 + 2.0) {
        u = d.u + climb;
    }
    return {d.f + d.vf * a / 2.0, d.r + d.vr * a / 2.0, u, 0.0, 0.0, infl};
}

std::pair<double, double> cpa(double pf, double pr, double vf, double vr, double tLook)
{
    const double vv = vf * vf + vr * vr;
    if (vv < 1e-6) {
        return {0.0, norm(pf, pr)};
    }
    double t = -(pf * vf + pr * vr) / vv;
    t = std::max(0.0, std::min(t, tLook));
    return {t, norm(pf + vf * t, pr + vr * t)};
}

PairEval evalPair(const Config &C, const DroneIn &a, const DroneIn &b, double extra)
{
    const Predicted A = predicted(C, a);
    const Predicted B = predicted(C, b);
    const double infl = A.infl + B.infl + extra;
    const double dz = std::fabs(A.u - B.u);
    const double pf = B.f - A.f, pr = B.r - A.r;
    const double vf = B.vf - A.vf, vr = B.vr - A.vr;
    const double dNow = norm(pf, pr);
    const auto [tC, dC] = cpa(pf, pr, vf, vr, C.tLook);

    // vertical: expected height difference at CPA, climbs stop at the mission goal altitude
    auto uAt = [](const DroneIn &d, double u0, double tt) {
        if (!d.fresh || std::fabs(d.vu) < 0.4) {
            return u0;
        }
        if (d.goalAlt && std::fabs(*d.goalAlt - d.relAlt) < 1.0) {
            return u0;
        }
        double u1 = u0 + d.vu * tt;
        if (d.goalAlt) {
            const double g = u0 + (*d.goalAlt - d.relAlt);
            if ((d.vu > 0 && g >= u0) || (d.vu < 0 && g <= u0)) {
                u1 = d.vu > 0 ? std::min(u1, g) : std::max(u1, g);
            }
        }
        return u1;
    };
    // both only moving vertically (take-off / landing columns)
    auto vertOnly = [](const DroneIn &d) {
        if (!d.fresh || norm(d.vf, d.vr) > 0.5) {
            return false;
        }
        return !d.goal || norm(d.goal->first - d.f, d.goal->second - d.r) < 2.5;
    };
    if (vertOnly(a) && vertOnly(b) && dNow > C.dEmerg) {
        return {0, dNow, dC, tC, dz, true};
    }
    // both inside their own pad zone
    auto onPad = [&C](const DroneIn &d) {
        return d.fresh && d.home && norm(d.f - d.home->first, d.r - d.home->second) < C.padZone;
    };
    if (onPad(a) && onPad(b) && dNow > C.dEmerg) {
        return {0, dNow, dC, tC, dz, true};
    }
    // both settling onto separate hold points
    auto settling = [](const DroneIn &d) {
        return d.fresh && d.goalHold && d.goal && norm(d.goal->first - d.f, d.goal->second - d.r) < 4.0 &&
               norm(d.vf, d.vr) < 1.5;
    };
    if (settling(a) && settling(b) && dNow > C.dEmerg &&
        norm(a.goal->first - b.goal->first, a.goal->second - b.goal->second) > C.dEmerg + 2.0) {
        return {0, dNow, dC, tC, dz, true};
    }
    const double dzCpa = std::fabs(uAt(a, A.u, tC) - uAt(b, B.u, tC));
    const double dzMid = std::fabs(uAt(a, A.u, tC / 2) - uAt(b, B.u, tC / 2));
    if (std::min({dz, dzCpa, dzMid}) > C.vSep) {
        return {0, dNow, dC, tC, dz, true};
    }
    // flying side by side at the same speed: distance does not shrink
    const double closing = -(pf * vf + pr * vr) / std::max(dNow, 1e-3);
    if (a.fresh && b.fresh && closing < 0.3 && norm(vf, vr) < 1.0 && dNow > C.dEmerg + 1.0) {
        return {0, dNow, dC, tC, dz, dNow > C.dSafe + C.releaseMargin};
    }
    int level = 0;
    if (dNow < C.dEmerg + infl) {
        level = 2;
    } else if (dNow < C.dSafe + infl || (dC < C.dSafe + infl && tC < C.tLook)) {
        level = 1;
    }
    const double rel = C.dSafe + C.releaseMargin + infl;
    const bool clear = dNow > rel && (dC > rel || tC >= C.tLook);
    return {level, dNow, dC, tC, dz, clear};
}

// ═══════════════════════════════════════════════════════════════
// ACACT 2D with keep-right
// ═══════════════════════════════════════════════════════════════
namespace {
std::pair<double, double> acactAdapt(double vf, double vr, double rf, double rr, double ts)
{
    // eq. (12)-(15): if predicted collision time tc < ts, shrink the obstacle-direction component
    const double rm = norm(rf, rr);
    const double vm = norm(vf, vr);
    if (rm < EPS || vm < EPS) {
        return {vf, vr};
    }
    const double dot = vf * rf + vr * rr;
    if (dot >= 0) {
        return {vf, vr};
    }
    const double tc = rm * rm / (-dot);
    if (tc >= ts) {
        return {vf, vr};
    }
    const double vpPlus = rm / ts;
    const double rhf = rf / rm, rhr = rr / rm;
    const double proj = vf * rhf + vr * rhr;
    const double pf_ = proj * rhf, pr_ = proj * rhr;
    const double qf = vf - pf_, qr = vr - pr_;
    const double pn = norm(pf_, pr_), qn = norm(qf, qr);
    double pfu = 0, pru = 0, qfu = 0, qru = 0;
    if (pn > EPS) { pfu = pf_ / pn; pru = pr_ / pn; }
    if (qn > EPS) { qfu = qf / qn; qru = qr / qn; }
    const double rem = std::max(vm * vm - vpPlus * vpPlus, 0.0);
    const double s = std::sqrt(rem);
    return {vpPlus * pfu + s * qfu, vpPlus * pru + s * qru};
}
}

std::tuple<double, double, VelocityDebug> acactVelocity(const Config &C, const DroneIn &me,
                                                        const std::vector<const DroneIn *> &others,
                                                        XY goal, bool emergency)
{
    const AcactGains &p = C.acact;
    const double af = goal.first - me.f, ar = goal.second - me.r;
    const double am = norm(af, ar);
    const double sa = std::min(p.kpa * am, C.maxHSpeed);
    double vf = 0, vr = 0;
    if (am > p.goal_tol) {
        vf = sa * af / am;
        vr = sa * ar / am;
    }

    double hf, hr;
    if (norm(me.vf, me.vr) > 0.3) { hf = me.vf; hr = me.vr; } else { hf = af; hr = ar; }
    const double hm = norm(hf, hr);
    if (hm > EPS) { hf /= hm; hr /= hm; } else { hf = 1.0; hr = 0.0; }
    const double rightf = -hr, rightr = hf;

    double rpf = 0, rpr = 0, rvf = 0, rvr = 0, bf = 0, br = 0;
    std::optional<XY> best;
    double bestTc = std::numeric_limits<double>::infinity();
    for (const DroneIn *nb : others) {
        if (nb->id == me.id) {
            continue;
        }
        const Predicted N = predicted(C, *nb);
        if (std::fabs(N.u - me.u) > C.vSep + 2.0) {
            continue;
        }
        const double rf = me.f - N.f, rr = me.r - N.r;
        double rm = norm(rf, rr);
        const double rs = p.rs + N.infl;
        // CPA-based keep-right: start moving right before entering the repulsion radius
        const auto [tC, dC] = cpa(N.f - me.f, N.r - me.r, N.vf - me.vf, N.vr - me.vr, C.tLook);
        const double lim = C.dSafe + 3.0 + N.infl;
        if (tC < C.tLook && dC < lim && tC > 0.0) {
            const double g = p.k_cpa * (lim - dC) / lim;
            bf += g * rightf;
            br += g * rightr;
        }
        if (rm >= rs) {
            continue;
        }
        rm = std::max(rm, 0.5);
        const double rhf = rf / rm, rhr = rr / rm;
        const double k = rs * rs / (rm * rm) - 1.0;
        rpf += k * rhf;
        rpr += k * rhr;
        // relative-velocity repulsion (eq. 5-6)
        const double vrf = N.vf - me.vf, vrr = N.vr - me.vr;
        const double vrm = norm(vrf, vrr);
        if (vrm > EPS) {
            const double vhf = vrf / vrm, vhr = vrr / vrm;
            const double d = rhf * vhf + rhr * vhr;
            if (0.0 < d && d < 1.0) {
                rvf += rhf / d - vhf;
                rvr += rhr / d - vhr;
            }
        }
        const double closing = -(rf * (me.vf - N.vf) + rr * (me.vr - N.vr));
        if (closing > EPS) {
            const double tc = rm * rm / closing;
            if (tc < bestTc) {
                bestTc = tc;
                best = XY{rf, rr};
            }
            if (tc < 2.0 * p.ts) {
                const double g = p.k_rh * (rs / rm - 1.0);
                bf += g * rightf;
                br += g * rightr;
            }
        }
    }

    if (emergency) {
        const double m = norm(rpf, rpr);
        if (m > EPS) { vf = rpf / m * 1.0; vr = rpr / m * 1.0; } else { vf = 0.0; vr = 0.0; }
        return {vf, vr, VelocityDebug{"EMERG", bestTc}};
    }

    vf += p.kpp * rpf + p.kpv * rvf + bf;
    vr += p.kpp * rpr + p.kpv * rvr + br;

    const bool stuck = am > 2.0 && norm(vf, vr) < 0.3;
    if (stuck) {
        const double gm = am > EPS ? am : 1.0;
        vf = 1.0 * (-ar / gm);
        vr = 1.0 * (af / gm);
    } else if (best) {
        std::tie(vf, vr) = acactAdapt(vf, vr, best->first, best->second, p.ts);
    }
    const double m = norm(vf, vr);
    if (m > C.maxHSpeed) {
        vf = vf * C.maxHSpeed / m;
        vr = vr * C.maxHSpeed / m;
    }
    return {vf, vr, VelocityDebug{stuck ? "STUCK" : "ACACT", bestTc}};
}

// ═══════════════════════════════════════════════════════════════
// state machine
// ═══════════════════════════════════════════════════════════════
GuardCore::GuardCore(const Config &config, const std::vector<std::string> &ids)
    : C(config)
{
    for (const std::string &i : ids) {
        own[i] = Own{};
    }
}

bool GuardCore::_eligible(const DroneIn &d) const
{
    const Own &o = own.at(d.id);
    if (!d.fresh || !d.inAir || d.relAlt < C.minTakeoverAlt || o.lock) {
        return false;
    }
    return d.mode == "MISSION" || (d.mode == "OFFBOARD" && o.owned);
}

std::vector<Command> GuardCore::step(double t, const std::vector<DroneIn> &allDrones)
{
    std::vector<Command> cmds;
    const double dt = _lastT ? t - *_lastT : 0.0;
    _lastT = t;

    // 1) pair evaluation; drones silent for STALE_DROP_T are assumed returning (RTL) and dropped
    for (const DroneIn &d : allDrones) {
        if (!d.fresh && d.age > C.staleDropT && d.inAir) {
            if (!_dropped.count(d.id)) {
                _dropped.insert(d.id);
                cmds.push_back({Command::Event, d.id, {},
                                "통신 두절 " + fmt0(C.staleDropT) + "초 — RTL 귀환 중으로 간주, 충돌 판단에서 제외 (육안 확인!)"});
            }
        } else if (d.fresh) {
            _dropped.erase(d.id);
        }
    }
    std::vector<const DroneIn *> drones;
    for (const DroneIn &d : allDrones) {
        if (!_dropped.count(d.id)) {
            drones.push_back(&d);
        }
    }
    bool anyStale = false;
    for (const DroneIn *d : drones) {
        if (d->inAir && !d->fresh) {
            anyStale = true;
        }
    }
    _extra = anyStale ? C.degradedMargin : 0.0;

    std::map<std::string, int> risk;
    std::map<std::string, bool> clearAll;
    for (const DroneIn *d : drones) {
        risk[d->id] = 0;
        clearAll[d->id] = true;
    }
    pairs.clear();
    for (size_t i = 0; i < drones.size(); i++) {
        for (size_t j = i + 1; j < drones.size(); j++) {
            const DroneIn &a = *drones[i];
            const DroneIn &b = *drones[j];
            if (!(a.inAir && b.inAir)) {
                continue;
            }
            const PairEval pe = evalPair(C, a, b, _extra);
            const PairKey key{a.id, b.id};
            pairs.emplace_back(key, pe);
            if (a.fresh && b.fresh) {
                const double d3 = std::sqrt(pe.dNow * pe.dNow + pe.dz * pe.dz);
                auto it3 = min3d.find(key);
                min3d[key] = std::min(it3 == min3d.end() ? 1e9 : it3->second, d3);
                if (pe.dz <= C.vSep) {
                    auto its = minSep.find(key);
                    minSep[key] = std::min(its == minSep.end() ? 1e9 : its->second, pe.dNow);
                }
            }
            risk[a.id] = std::max(risk[a.id], pe.level);
            risk[b.id] = std::max(risk[b.id], pe.level);
            if (!pe.clear) {
                clearAll[a.id] = false;
                clearAll[b.id] = false;
            }
            if (pe.level >= 1 && !(_eligible(a) || own[a.id].owned) && !(_eligible(b) || own[b.id].owned)) {
                auto w = _warnedT.find(key);
                if (t - (w == _warnedT.end() ? -1e9 : w->second) > 10.0) {
                    _warnedT[key] = t;
                    cmds.push_back({Command::Event, a.id + "-" + b.id, {},
                                    "위험 근접 " + fmt1(pe.dNow) + "m — 두 기체 모두 개입 불가 (모드 " + a.mode + "/" + b.mode + ")"});
                }
            }
        }
    }

    // 2) per-drone state machine
    for (const DroneIn *dp : drones) {
        const DroneIn &d = *dp;
        Own &o = own[d.id];
        if (o.owned) {
            o.ownedTime += dt;
        }
        // pilot / PX4 changed the mode → hands off
        if (o.owned && d.fresh && d.mode != "OFFBOARD" && t - o.tTake > 1.5) {
            o.owned = false;
            if (d.mode != "MISSION") {
                o.lock = true;
                cmds.push_back({Command::Event, d.id, {}, "모드 " + d.mode + " 전환 감지 → 가드 해제 (미션 재개 시 다시 감시)"});
            }
            continue;
        }
        if (o.lock && d.mode == "MISSION") {
            o.lock = false;
        }
        if (o.owned && !d.fresh) {
            o.owned = false;
            cmds.push_back({Command::Event, d.id, {}, "텔레메트리 끊김 — PX4 offboard 상실 페일세이프로 전환 예상"});
            continue;
        }
        if (!enabled) {
            o.owned = false;      // 'h' (hold all): let go without sending the mission back
            continue;
        }
        if (!o.owned) {
            if (risk[d.id] >= 1 && _eligible(d)) {
                o.owned = true;
                o.tTake = t;
                o.tClear.reset();
                o.holdU = d.u;
                o.takeovers += 1;
                const Vel3 v = _velocity(d, drones, risk[d.id]);
                cmds.push_back({Command::Takeover, d.id, v, {}});
            }
            continue;
        }
        // owned
        if (clearAll[d.id] && risk[d.id] == 0) {
            if (!o.tClear) {
                o.tClear = t;
            }
        } else {
            o.tClear.reset();
        }
        // reached a pass-through waypoint while avoiding → hand back to the mission
        if (d.goal && !d.goalHold && risk[d.id] < 2 &&
            norm(d.goal->first - d.f, d.goal->second - d.r) < C.goalHandoff && t - o.tTake >= 1.0) {
            o.owned = false;
            o.tHandoff = t;
            cmds.push_back({Command::Release, d.id, {}, {}});
            continue;
        }
        if (o.tClear && t - *o.tClear >= C.releaseHold && t - o.tTake >= C.minOwnTime) {
            o.owned = false;
            cmds.push_back({Command::Release, d.id, {}, {}});
            continue;
        }
        cmds.push_back({Command::Vel, d.id, _velocity(d, drones, risk[d.id]), {}});
    }
    return cmds;
}

Vel3 GuardCore::_velocity(const DroneIn &d, const std::vector<const DroneIn *> &drones, int level)
{
    Own &o = own[d.id];
    XY goal;
    if (d.goal) {
        goal = *d.goal;
    } else {
        const double sp = norm(d.vf, d.vr);
        goal = sp > 0.3 ? XY{d.f + 10 * d.vf / sp, d.r + 10 * d.vr / sp} : XY{d.f, d.r};
    }
    std::vector<const DroneIn *> others;
    for (const DroneIn *x : drones) {
        if (x->id != d.id && x->inAir) {
            others.push_back(x);
        }
    }
    const bool emerg = level >= 2;
    // merging into the same point: the lower-priority drone yields (waits in place)
    o.yielding = false;
    if (d.goal) {
        for (const DroneIn *x : others) {
            if (x->prio < d.prio && x->fresh && x->goal && std::fabs(x->u - d.u) <= C.vSep &&
                norm(x->goal->first - d.goal->first, x->goal->second - d.goal->second) < C.dSafe &&
                norm(x->f - d.f, x->r - d.r) < 3 * C.dSafe) {
                goal = XY{d.f, d.r};
                o.yielding = true;
                break;
            }
        }
    }
    auto [vf, vr, dbg] = acactVelocity(C, d, others, goal, emerg);
    (void)dbg;
    // altitude: hold the take-over altitude; in an emergency only the lower-priority drone climbs
    double targetU = o.holdU;
    if (emerg) {
        bool lower = false;
        for (const DroneIn *x : others) {
            if (std::fabs(x->u - d.u) <= C.vSep && norm(x->f - d.f, x->r - d.r) < C.dEmerg + 2.0 && x->prio < d.prio) {
                lower = true;
            }
        }
        if (lower) {
            targetU = std::min(d.u + 2.0, o.holdU + C.emergClimbMax);
            o.holdU = std::max(o.holdU, std::min(d.u, o.holdU + C.emergClimbMax));
        }
    }
    const double vu = std::max(-C.maxClimb, std::min(C.maxClimb, C.altHoldKp * (targetU - d.u)));
    return {vf, vr, vu};
}

} // namespace acact
