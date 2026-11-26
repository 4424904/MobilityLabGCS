// ACACT engine — decision core. Line-by-line port of acact_guard/core.py (rev1).
// Keep the structure aligned with core.py so diffs between the two stay readable;
// tests/acact_compare.py checks both give the same commands for the same inputs.
#include "AcactCore.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>

namespace acact {

namespace {
constexpr double EPS = 1e-9;
inline double norm(double x, double y) { return std::hypot(x, y); }

std::string fmt(const char *f, double a)
{
    char b[256];
    std::snprintf(b, sizeof b, f, a);
    return b;
}
} // namespace

// ═══════════════════════════════════════════════════════════════
// geometry
// ═══════════════════════════════════════════════════════════════
Predicted predicted(const Config &c, const DroneIn &d)
{
    if (d.fresh) {
        return {d.f, d.r, d.u, d.vf, d.vr, 0.0};
    }
    const double a = std::min(d.age, c.stalePredictMax);
    const double sp = norm(d.vf, d.vr);
    const double infl = std::min(sp * a / 2.0 + 0.5 * a, 10.0);
    double u = d.u;
    const double climb = std::max(d.rtlAlt - d.relAlt, 0.0);
    if (d.age > c.dlLossT + climb / 1.0 + 2.0) {
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

PairEval evalPair(const Config &c, const DroneIn &a, const DroneIn &b, double extra)
{
    const Predicted A = predicted(c, a);
    const Predicted B = predicted(c, b);
    const double infl = A.infl + B.infl + extra;
    const double dz = std::fabs(A.u - B.u);
    const double pf = B.f - A.f, pr = B.r - A.r;
    const double vf = B.vf - A.vf, vr = B.vr - A.vr;
    const double dNow = norm(pf, pr);
    const auto [tC, dC] = cpa(pf, pr, vf, vr, c.tLook);

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
    auto vertOnly = [](const DroneIn &d) {
        if (!d.fresh || norm(d.vf, d.vr) > 0.5) {
            return false;
        }
        return !d.goal || norm((*d.goal)[0] - d.f, (*d.goal)[1] - d.r) < 2.5;
    };
    if (vertOnly(a) && vertOnly(b) && dNow > c.dEmerg) {
        return {0, dNow, dC, tC, dz, true};
    }
    auto onPad = [&c](const DroneIn &d) {
        return d.fresh && d.home && norm(d.f - (*d.home)[0], d.r - (*d.home)[1]) < c.padZone;
    };
    if (onPad(a) && onPad(b) && dNow > c.dEmerg) {
        return {0, dNow, dC, tC, dz, true};
    }
    auto settling = [](const DroneIn &d) {
        return d.fresh && d.goalHold && d.goal
               && norm((*d.goal)[0] - d.f, (*d.goal)[1] - d.r) < 6.0 && norm(d.vf, d.vr) < 2.5;
    };
    if (settling(a) && settling(b) && dNow > c.dEmerg
        && norm((*a.goal)[0] - (*b.goal)[0], (*a.goal)[1] - (*b.goal)[1]) > c.dEmerg + 2.0) {
        return {0, dNow, dC, tC, dz, true};
    }
    const double dzCpa = std::fabs(uAt(a, A.u, tC) - uAt(b, B.u, tC));
    const double dzMid = std::fabs(uAt(a, A.u, tC / 2) - uAt(b, B.u, tC / 2));
    if (std::min({dz, dzCpa, dzMid}) > c.vSep) {
        return {0, dNow, dC, tC, dz, true};
    }
    const double closing = -(pf * vf + pr * vr) / std::max(dNow, 1e-3);
    if (a.fresh && b.fresh && closing < 0.3 && (norm(vf, vr) < 1.0 || closing < -0.3) && dNow > c.dEmerg + 1.0) {
        return {0, dNow, dC, tC, dz, dNow > c.dSafe + c.releaseMargin};
    }
    int level = 0;
    if (dNow < c.dEmerg + infl) {
        level = 2;
    } else if (dNow < c.dSafe + infl || (dC < c.dSafe + infl && tC < c.tLook)) {
        level = 1;
    }
    const double rel = c.dSafe + c.releaseMargin + infl;
    const bool clear = dNow > rel && (dC > rel || tC >= c.tLook);
    return {level, dNow, dC, tC, dz, clear};
}

// ═══════════════════════════════════════════════════════════════
// ACACT 2D (with keep-right bias)
// ═══════════════════════════════════════════════════════════════
static std::array<double, 2> acactAdapt(double vf, double vr, double rf, double rr, double ts)
{
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
    const double pfu = pn > EPS ? pf_ / pn : 0.0, pru = pn > EPS ? pr_ / pn : 0.0;
    const double qfu = qn > EPS ? qf / qn : 0.0, qru = qn > EPS ? qr / qn : 0.0;
    const double rem = std::max(vm * vm - vpPlus * vpPlus, 0.0);
    const double s = std::sqrt(rem);
    return {vpPlus * pfu + s * qfu, vpPlus * pru + s * qru};
}

std::array<double, 2> acactVelocity(const Config &c, const DroneIn &me, const std::vector<DroneIn> &others,
                                    const Vec2 &goal, bool emergency, AcactDebug *dbg)
{
    const auto &p = c.acact;
    const double af = goal[0] - me.f, ar = goal[1] - me.r;
    const double am = norm(af, ar);
    const double sa = std::min(p.kpa * am, c.maxHSpeed);
    double vf = 0.0, vr = 0.0;
    if (am > p.goalTol) {
        vf = sa * af / am;
        vr = sa * ar / am;
    }

    double hf, hr;
    if (norm(me.vf, me.vr) > 0.3) {
        hf = me.vf; hr = me.vr;
    } else {
        hf = af; hr = ar;
    }
    const double hm = norm(hf, hr);
    if (hm > EPS) {
        hf /= hm; hr /= hm;
    } else {
        hf = 1.0; hr = 0.0;
    }
    const double rightf = -hr, rightr = hf;

    double rpf = 0, rpr = 0, rvf = 0, rvr = 0, bf = 0, br = 0;
    bool haveBest = false;
    double bestF = 0, bestR = 0;
    double bestTc = std::numeric_limits<double>::infinity();
    for (const DroneIn &nb : others) {
        if (nb.id == me.id) {
            continue;
        }
        const Predicted N = predicted(c, nb);
        if (std::fabs(N.u - me.u) > c.vSep + 2.0) {
            continue;
        }
        const double rf = me.f - N.f, rr = me.r - N.r;
        double rm = norm(rf, rr);
        const double rs = p.rs + N.infl;
        const auto [tC, dC] = cpa(N.f - me.f, N.r - me.r, N.vf - me.vf, N.vr - me.vr, c.tLook);
        const double lim = c.dSafe + 3.0 + N.infl;
        if (tC < c.tLook && dC < lim && tC > 0.0) {
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
                haveBest = true;
                bestF = rf; bestR = rr;
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
        if (dbg) { dbg->mode = "EMERG"; dbg->tc = bestTc; }
        if (m > EPS) {
            return {(rpf / m) * 1.0, (rpr / m) * 1.0};
        }
        return {0.0, 0.0};
    }

    vf += p.kpp * rpf + p.kpv * rvf + bf;
    vr += p.kpp * rpr + p.kpv * rvr + br;

    const bool stuck = am > 2.0 && norm(vf, vr) < 0.3;
    if (stuck) {
        const double gm = am > EPS ? am : 1.0;
        vf = 1.0 * (-ar / gm);
        vr = 1.0 * (af / gm);
    } else if (haveBest) {
        const auto ad = acactAdapt(vf, vr, bestF, bestR, p.ts);
        vf = ad[0]; vr = ad[1];
    }
    const double m = norm(vf, vr);
    if (m > c.maxHSpeed) {
        vf = vf * c.maxHSpeed / m;
        vr = vr * c.maxHSpeed / m;
    }
    if (dbg) { dbg->mode = stuck ? "STUCK" : "ACACT"; dbg->tc = bestTc; }
    return {vf, vr};
}

// ═══════════════════════════════════════════════════════════════
// guard state machine
// ═══════════════════════════════════════════════════════════════
GuardCore::GuardCore(const Config &config, const std::vector<std::string> &ids)
    : _c(config)
{
    for (const auto &id : ids) {
        own[id] = Own{};
    }
}

bool GuardCore::eligible(const DroneIn &d) const
{
    const Own &o = own.at(d.id);
    if (!d.fresh || !d.inAir || d.relAlt < _c.minTakeoverAlt || o.lock) {
        return false;
    }
    return d.mode == "MISSION" || (d.mode == "OFFBOARD" && o.owned);
}

std::vector<Command> GuardCore::step(double t, const std::vector<DroneIn> &input)
{
    std::vector<Command> cmds;
    const double dt = _lastT ? t - *_lastT : 0.0;
    _lastT = t;

    auto isDropped = [this](const std::string &id) {
        return std::find(_dropped.begin(), _dropped.end(), id) != _dropped.end();
    };
    // 1) pairs. Drones lost for STALE_DROP_T are assumed on RTL and left out.
    for (const DroneIn &d : input) {
        if (!d.fresh && d.age > _c.staleDropT && d.inAir) {
            if (!isDropped(d.id)) {
                _dropped.push_back(d.id);
                cmds.push_back({CmdKind::Event, d.id, {0, 0, 0},
                                fmt("통신 두절 %.0f초 — RTL 귀환 중으로 간주, 충돌 판단에서 제외 (육안 확인!)", _c.staleDropT)});
            }
        } else if (d.fresh) {
            _dropped.erase(std::remove(_dropped.begin(), _dropped.end(), d.id), _dropped.end());
        }
    }
    std::vector<DroneIn> drones;
    for (const DroneIn &d : input) {
        if (!isDropped(d.id)) {
            drones.push_back(d);
        }
    }
    bool degraded = false;
    for (const DroneIn &d : drones) {
        if (d.inAir && !d.fresh) {
            degraded = true;
        }
    }
    _extra = degraded ? _c.degradedMargin : 0.0;

    std::map<std::string, int> risk;
    std::map<std::string, bool> clearAll;
    for (const DroneIn &d : drones) {
        risk[d.id] = 0;
        clearAll[d.id] = true;
    }
    pairs.clear();
    for (size_t i = 0; i < drones.size(); i++) {
        for (size_t j = i + 1; j < drones.size(); j++) {
            const DroneIn &a = drones[i];
            const DroneIn &b = drones[j];
            if (!(a.inAir && b.inAir)) {
                continue;
            }
            const PairEval pe = evalPair(_c, a, b, _extra);
            const PairKey key {a.id, b.id};
            pairs.emplace_back(key, pe);
            if (a.fresh && b.fresh) {
                const double d3 = std::sqrt(pe.dNow * pe.dNow + pe.dz * pe.dz);
                auto it = min3d.find(key);
                min3d[key] = std::min(it == min3d.end() ? 1e9 : it->second, d3);
                if (pe.dz <= _c.vSep) {
                    auto is = minSep.find(key);
                    minSep[key] = std::min(is == minSep.end() ? 1e9 : is->second, pe.dNow);
                }
            }
            risk[a.id] = std::max(risk[a.id], pe.level);
            risk[b.id] = std::max(risk[b.id], pe.level);
            if (!pe.clear) {
                clearAll[a.id] = clearAll[b.id] = false;
            }
            if (pe.level >= 1 && !(eligible(a) || own[a.id].owned) && !(eligible(b) || own[b.id].owned)) {
                auto w = _warnedT.find(key);
                if (t - (w == _warnedT.end() ? -1e9 : w->second) > 10.0) {
                    _warnedT[key] = t;
                    char buf[256];
                    std::snprintf(buf, sizeof buf, "위험 근접 %.1fm — 두 기체 모두 개입 불가 (모드 %s/%s)",
                                  pe.dNow, a.mode.c_str(), b.mode.c_str());
                    cmds.push_back({CmdKind::Event, a.id + "-" + b.id, {0, 0, 0}, buf});
                }
            }
        }
    }

    // 2) per-drone state machine
    for (const DroneIn &d : drones) {
        Own &o = own[d.id];
        if (o.owned) {
            o.ownedTime += dt;
        }
        if (o.owned && d.fresh && d.mode != "OFFBOARD" && t - o.tTake > 1.5) {
            o.owned = false;
            if (d.mode != "MISSION") {
                o.lock = true;
                cmds.push_back({CmdKind::Event, d.id, {0, 0, 0},
                                "모드 " + d.mode + " 전환 감지 → 가드 해제 (미션 재개 시 다시 감시)"});
            }
            continue;
        }
        if (o.lock && d.mode == "MISSION") {
            o.lock = false;
        }
        if (o.owned && !d.fresh) {
            o.owned = false;
            cmds.push_back({CmdKind::Event, d.id, {0, 0, 0}, "텔레메트리 끊김 — PX4 offboard 상실 페일세이프로 전환 예상"});
            continue;
        }
        if (!enabled) {
            o.owned = false;
            continue;
        }
        if (!o.owned) {
            if (risk[d.id] >= 1 && eligible(d)) {
                o.owned = true;
                o.tTake = t;
                o.tClear.reset();
                o.holdU = d.u;
                o.takeovers += 1;
                const Vec3 v = _velocity(d, drones, risk[d.id]);
                cmds.push_back({CmdKind::Takeover, d.id, v, {}});
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
        if (d.goal && !d.goalHold && risk[d.id] < 2
            && norm((*d.goal)[0] - d.f, (*d.goal)[1] - d.r) < _c.goalHandoff && t - o.tTake >= 1.0) {
            if (risk[d.id] == 0 && _releaseSafe(d, drones)) {
                o.owned = false;
                o.tHandoff = t;
                cmds.push_back({CmdKind::Release, d.id, {0, 0, 0}, {}});
                continue;
            }
            if (!_c.advanceInAvoid) {
                o.owned = false;
                o.tHandoff = t;
                cmds.push_back({CmdKind::Release, d.id, {0, 0, 0}, {}});
                continue;
            }
            if (o.advGoal != d.goal || t - o.tAdv > 2.0) {
                o.advGoal = d.goal;
                o.tAdv = t;
                cmds.push_back({CmdKind::Advance, d.id, {0, 0, 0}, {}});
            }
        }
        if (o.tClear && t - *o.tClear >= _c.releaseHold && t - o.tTake >= _c.minOwnTime && _releaseSafe(d, drones)) {
            o.owned = false;
            cmds.push_back({CmdKind::Release, d.id, {0, 0, 0}, {}});
            continue;
        }
        cmds.push_back({CmdKind::Vel, d.id, _velocity(d, drones, risk[d.id]), {}});
    }
    return cmds;
}

bool GuardCore::_releaseSafe(const DroneIn &d, const std::vector<DroneIn> &drones) const
{
    if (!d.goal) {
        return true;
    }
    const double gf = (*d.goal)[0] - d.f, gr = (*d.goal)[1] - d.r;
    const double L = norm(gf, gr);
    if (L < 0.5) {
        return true;
    }
    const double sp = std::max(norm(d.vf, d.vr), _c.scenarioSpeed);
    const double mvf = gf / L * sp, mvr = gr / L * sp;
    const double rel = _c.dSafe + _c.releaseMargin;
    for (const DroneIn &x : drones) {
        if (x.id == d.id || !x.inAir) {
            continue;
        }
        const Predicted X = predicted(_c, x);
        if (std::fabs(X.u - d.u) > _c.vSep) {
            continue;
        }
        const auto [tC, dC] = cpa(X.f - d.f, X.r - d.r, X.vf - mvf, X.vr - mvr, std::min(_c.tLook, L / sp + 1.0));
        (void)tC;
        if (dC < rel + X.infl) {
            return false;
        }
    }
    return true;
}

Vec3 GuardCore::_velocity(const DroneIn &d, const std::vector<DroneIn> &drones, int level)
{
    Own &o = own[d.id];
    Vec2 goal;
    if (d.goal) {
        goal = *d.goal;
    } else {
        const double sp = norm(d.vf, d.vr);
        goal = sp > 0.3 ? Vec2 {d.f + 10 * d.vf / sp, d.r + 10 * d.vr / sp} : Vec2 {d.f, d.r};
    }
    std::vector<DroneIn> others;
    for (const DroneIn &x : drones) {
        if (x.id != d.id && x.inAir) {
            others.push_back(x);
        }
    }
    const bool emerg = level >= 2;
    o.yielding = false;
    if (d.goal) {
        for (const DroneIn &x : others) {
            if (x.prio < d.prio && x.fresh && x.goal && std::fabs(x.u - d.u) <= _c.vSep
                && norm((*x.goal)[0] - (*d.goal)[0], (*x.goal)[1] - (*d.goal)[1]) < _c.dSafe
                && norm(x.f - d.f, x.r - d.r) < 3 * _c.dSafe) {
                goal = {d.f, d.r};
                o.yielding = true;
                break;
            }
        }
    }
    const auto v = acactVelocity(_c, d, others, goal, emerg);
    double targetU = o.holdU;
    if (emerg) {
        bool lower = false;
        for (const DroneIn &x : others) {
            if (std::fabs(x.u - d.u) <= _c.vSep && norm(x.f - d.f, x.r - d.r) < _c.dEmerg + 2.0 && x.prio < d.prio) {
                lower = true;
            }
        }
        if (lower) {
            targetU = std::min(d.u + 2.0, o.holdU + _c.emergClimbMax);
            o.holdU = std::max(o.holdU, std::min(d.u, o.holdU + _c.emergClimbMax));
        }
    }
    const double vu = std::max(-_c.maxClimb, std::min(_c.maxClimb, _c.altHoldKp * (targetU - d.u)));
    return {v[0], v[1], vu};
}

} // namespace acact
