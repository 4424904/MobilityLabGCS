// AcactCore — C++17 port of ACACT Guard core.py. See AcactCore.h.
// Every function mirrors the Python original statement by statement (same
// evaluation order) so results match the original to the last bit where the
// C library agrees with CPython (hypot); tools/acact_compare checks this.
#include "AcactCore.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <tuple>
#include <limits>

namespace mlacact {

namespace {
constexpr double EPS = 1e-9;
inline double norm2(double x, double y) { return std::hypot(x, y); }

std::string fmt(const char *f, double v)
{
    char buf[64];
    std::snprintf(buf, sizeof(buf), f, v);
    return buf;
}

std::pair<double, double> acactAdapt(double vf, double vr, double rf, double rr, double ts)
{
    // paper eq. (12)-(15): if predicted collision time tc < ts, reduce the component towards the obstacle
    const double rm = norm2(rf, rr);
    const double vm = norm2(vf, vr);
    if (rm < EPS || vm < EPS) {
        return {vf, vr};
    }
    const double dot = vf * rf + vr * rr;     // r = me <- obstacle
    if (dot >= 0) {
        return {vf, vr};                       // moving away
    }
    const double tc = rm * rm / (-dot);
    if (tc >= ts) {
        return {vf, vr};
    }
    const double vpPlus = rm / ts;
    const double rhf = rf / rm, rhr = rr / rm;
    const double proj = vf * rhf + vr * rhr;
    const double pf = proj * rhf, pr = proj * rhr;
    const double qf = vf - pf, qr = vr - pr;
    const double pn = norm2(pf, pr), qn = norm2(qf, qr);
    double pfu = 0.0, pru = 0.0, qfu = 0.0, qru = 0.0;
    if (pn > EPS) { pfu = pf / pn; pru = pr / pn; }
    if (qn > EPS) { qfu = qf / qn; qru = qr / qn; }
    const double rem = std::max(vm * vm - vpPlus * vpPlus, 0.0);
    const double s = std::sqrt(rem);
    return {vpPlus * pfu + s * qfu, vpPlus * pru + s * qru};
}
} // namespace

Params Params::forVehicleCount(int n)
{
    Params p;
    if (n == 2) {   // config.py "DUO"
        p.maxHSpeed = 4.5;
        p.dSafe = 12.0;
        p.rs = 14.0;
        p.kCpa = 3.0;
    }
    return p;
}

Predicted predicted(const Params &p, const DroneIn &d)
{
    if (d.fresh) {
        return {d.f, d.r, d.u, d.vf, d.vr, 0.0};
    }
    const double a = std::min(d.age, p.stalePredictMax);
    const double sp = norm2(d.vf, d.vr);
    const double infl = std::min(sp * a / 2.0 + 0.5 * a, 10.0);
    double u = d.u;
    const double climb = std::max(d.rtlAlt - d.relAlt, 0.0);
    if (d.age > p.dlLossT + climb / 1.0 + 2.0) {
        u = d.u + climb;
    }
    return {d.f + d.vf * a / 2.0, d.r + d.vr * a / 2.0, u, 0.0, 0.0, infl};
}

std::pair<double, double> cpa(double pf, double pr, double vf, double vr, double tLook)
{
    const double vv = vf * vf + vr * vr;
    if (vv < 1e-6) {
        return {0.0, norm2(pf, pr)};
    }
    double t = -(pf * vf + pr * vr) / vv;
    t = std::max(0.0, std::min(t, tLook));
    return {t, norm2(pf + vf * t, pr + vr * t)};
}

PairEval evalPair(const Params &p, const DroneIn &a, const DroneIn &b, double extra)
{
    const Predicted A = predicted(p, a);
    const Predicted B = predicted(p, b);
    const double infl = A.infl + B.infl + extra;
    const double dz = std::abs(A.u - B.u);
    const double pf = B.f - A.f, pr = B.r - A.r;
    const double vf = B.vf - A.vf, vr = B.vr - A.vr;
    const double dNow = norm2(pf, pr);
    const auto [tC, dC] = cpa(pf, pr, vf, vr, p.tLook);

    auto uAt = [](const DroneIn &d, double u0, double tt) {
        if (!d.fresh || std::abs(d.vu) < 0.4) {
            return u0;
        }
        if (d.goalAlt && std::abs(*d.goalAlt - d.relAlt) < 1.0) {
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
        if (!d.fresh || norm2(d.vf, d.vr) > 0.5) {
            return false;
        }
        return !d.goal || norm2(d.goal->first - d.f, d.goal->second - d.r) < 2.5;
    };
    if (vertOnly(a) && vertOnly(b) && dNow > p.dEmerg) {
        return {0, dNow, dC, tC, dz, true};
    }
    auto onPad = [&p](const DroneIn &d) {
        return d.fresh && d.home && norm2(d.f - d.home->first, d.r - d.home->second) < p.padZone;
    };
    if (onPad(a) && onPad(b) && dNow > p.dEmerg) {
        return {0, dNow, dC, tC, dz, true};
    }
    auto settling = [](const DroneIn &d) {
        return d.fresh && d.goalHold && d.goal && norm2(d.goal->first - d.f, d.goal->second - d.r) < 4.0 &&
               norm2(d.vf, d.vr) < 1.5;
    };
    if (settling(a) && settling(b) && dNow > p.dEmerg &&
        norm2(a.goal->first - b.goal->first, a.goal->second - b.goal->second) > p.dEmerg + 2.0) {
        return {0, dNow, dC, tC, dz, true};
    }
    const double dzCpa = std::abs(uAt(a, A.u, tC) - uAt(b, B.u, tC));
    const double dzMid = std::abs(uAt(a, A.u, tC / 2) - uAt(b, B.u, tC / 2));
    if (std::min({dz, dzCpa, dzMid}) > p.vSep) {
        return {0, dNow, dC, tC, dz, true};
    }
    const double closing = -(pf * vf + pr * vr) / std::max(dNow, 1e-3);
    if (a.fresh && b.fresh && closing < 0.3 && norm2(vf, vr) < 1.0 && dNow > p.dEmerg + 1.0) {
        return {0, dNow, dC, tC, dz, dNow > p.dSafe + p.releaseMargin};
    }
    int level = 0;
    if (dNow < p.dEmerg + infl) {
        level = 2;
    } else if (dNow < p.dSafe + infl || (dC < p.dSafe + infl && tC < p.tLook)) {
        level = 1;
    }
    const double rel = p.dSafe + p.releaseMargin + infl;
    const bool clear = dNow > rel && (dC > rel || tC >= p.tLook);
    return {level, dNow, dC, tC, dz, clear};
}

std::pair<double, double> acactVelocity(const Params &p, const DroneIn &me, const std::vector<DroneIn> &others,
                                        std::pair<double, double> goal, bool emergency, VelDebug *dbg)
{
    const double af = goal.first - me.f, ar = goal.second - me.r;
    const double am = norm2(af, ar);
    const double sa = std::min(p.kpa * am, p.maxHSpeed);
    double vf = 0.0, vr = 0.0;
    if (am > p.goalTol) {
        vf = sa * af / am;
        vr = sa * ar / am;
    }

    double hf, hr;
    if (norm2(me.vf, me.vr) > 0.3) { hf = me.vf; hr = me.vr; } else { hf = af; hr = ar; }
    const double hm = norm2(hf, hr);
    if (hm > EPS) { hf = hf / hm; hr = hr / hm; } else { hf = 1.0; hr = 0.0; }
    const double rightf = -hr, rightr = hf;

    double rpf = 0.0, rpr = 0.0, rvf = 0.0, rvr = 0.0, bf = 0.0, br = 0.0;
    bool haveBest = false;
    double bestF = 0, bestR = 0, bestTc = std::numeric_limits<double>::infinity();
    for (const DroneIn &nb : others) {
        if (nb.id == me.id) {
            continue;
        }
        const Predicted N = predicted(p, nb);
        if (std::abs(N.u - me.u) > p.vSep + 2.0) {
            continue;
        }
        const double rf = me.f - N.f, rr = me.r - N.r;
        double rm = norm2(rf, rr);
        const double rs = p.rs + N.infl;
        const auto [tC, dC] = cpa(N.f - me.f, N.r - me.r, N.vf - me.vf, N.vr - me.vr, p.tLook);
        const double lim = p.dSafe + 3.0 + N.infl;
        if (tC < p.tLook && dC < lim && tC > 0.0) {
            const double g = p.kCpa * (lim - dC) / lim;
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
        const double vrm = norm2(vrf, vrr);
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
                bestF = rf;
                bestR = rr;
            }
            if (tc < 2.0 * p.ts) {
                const double g = p.kRh * (rs / rm - 1.0);
                bf += g * rightf;
                br += g * rightr;
            }
        }
    }

    if (emergency) {
        const double m = norm2(rpf, rpr);
        if (m > EPS) { vf = (rpf / m) * 1.0; vr = (rpr / m) * 1.0; } else { vf = 0.0; vr = 0.0; }
        if (dbg) { *dbg = {"EMERG", bestTc}; }
        return {vf, vr};
    }

    vf += p.kpp * rpf + p.kpv * rvf + bf;
    vr += p.kpp * rpr + p.kpv * rvr + br;

    const bool stuck = am > 2.0 && norm2(vf, vr) < 0.3;
    if (stuck) {
        const double gm = am > EPS ? am : 1.0;
        vf = 1.0 * (-ar / gm);
        vr = 1.0 * (af / gm);
    } else if (haveBest) {
        std::tie(vf, vr) = acactAdapt(vf, vr, bestF, bestR, p.ts);
    }

    const double m = norm2(vf, vr);
    if (m > p.maxHSpeed) {
        vf = vf * p.maxHSpeed / m;
        vr = vr * p.maxHSpeed / m;
    }
    if (dbg) { *dbg = {stuck ? "STUCK" : "ACACT", bestTc}; }
    return {vf, vr};
}

GuardCore::GuardCore(const std::vector<std::string> &ids, const Params &prm)
    : params(prm)
{
    for (const auto &id : ids) {
        own[id] = Own{};
    }
}

bool GuardCore::eligible(const DroneIn &d) const
{
    const Own &o = own.at(d.id);
    if (!d.fresh || !d.inAir || d.relAlt < params.minTakeoverAlt || o.lock) {
        return false;
    }
    return d.mode == "MISSION" || (d.mode == "OFFBOARD" && o.owned);
}

std::vector<Command> GuardCore::step(double t, const std::vector<DroneIn> &input)
{
    const Params &p = params;
    std::vector<Command> cmds;
    const double dt = _lastT ? t - *_lastT : 0.0;
    _lastT = t;

    auto event = [&cmds](const std::string &id, const std::string &text) {
        Command c;
        c.type = Command::Event;
        c.id = id;
        c.text = text;
        cmds.push_back(c);
    };
    auto isDropped = [this](const std::string &id) {
        return std::find(_dropped.begin(), _dropped.end(), id) != _dropped.end();
    };

    // 1) pair evaluation; vehicles silent for STALE_DROP_T are assumed on RTL and left out
    for (const DroneIn &d : input) {
        if (!d.fresh && d.age > p.staleDropT && d.inAir) {
            if (!isDropped(d.id)) {
                _dropped.push_back(d.id);
                event(d.id, "통신 두절 " + fmt("%.0f", p.staleDropT) + "초 — RTL 귀환 중으로 간주, 충돌 판단에서 제외 (육안 확인!)");
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
    _extra = 0.0;
    for (const DroneIn &d : drones) {
        if (d.inAir && !d.fresh) {
            _extra = p.degradedMargin;
            break;
        }
    }
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
            const PairEval pe = evalPair(p, a, b, _extra);
            const PairKey key{a.id, b.id};
            pairs.emplace_back(key, pe);
            if (a.fresh && b.fresh) {
                const double d3 = std::sqrt(pe.dNow * pe.dNow + pe.dz * pe.dz);
                auto it3 = min3d.find(key);
                min3d[key] = std::min(it3 == min3d.end() ? 1e9 : it3->second, d3);
                if (pe.dz <= p.vSep) {
                    auto it = minSep.find(key);
                    minSep[key] = std::min(it == minSep.end() ? 1e9 : it->second, pe.dNow);
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
                    event(a.id + "-" + b.id, "위험 근접 " + fmt("%.1f", pe.dNow) + "m — 두 기체 모두 개입 불가 (모드 " +
                                                 a.mode + "/" + b.mode + ")");
                }
            }
        }
    }

    // 2) per-vehicle state machine
    for (const DroneIn &d : drones) {
        Own &o = own[d.id];
        if (o.owned) {
            o.ownedTime += dt;
        }
        // pilot / PX4 changed the mode -> let go
        if (o.owned && d.fresh && d.mode != "OFFBOARD" && t - o.tTake > 1.5) {
            o.owned = false;
            if (d.mode != "MISSION") {
                o.lock = true;
                event(d.id, "모드 " + d.mode + " 전환 감지 → 가드 해제 (미션 재개 시 다시 감시)");
            }
            continue;
        }
        if (o.lock && d.mode == "MISSION") {
            o.lock = false;
        }
        if (o.owned && !d.fresh) {
            o.owned = false;
            event(d.id, "텔레메트리 끊김 — PX4 offboard 상실 페일세이프로 전환 예상");
            continue;
        }
        if (!enabled) {
            o.owned = false;       // 'h' (hold all): let go without sending the mission back
            continue;
        }

        if (!o.owned) {
            if (risk[d.id] >= 1 && eligible(d)) {
                o.owned = true;
                o.tTake = t;
                o.tClear.reset();
                o.holdU = d.u;
                o.takeovers += 1;
                const auto v = _velocity(d, drones, risk[d.id]);
                Command c;
                c.type = Command::Takeover;
                c.id = d.id;
                c.v[0] = v[0]; c.v[1] = v[1]; c.v[2] = v[2];
                cmds.push_back(c);
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
        if (d.goal && !d.goalHold && risk[d.id] < 2 &&
            norm2(d.goal->first - d.f, d.goal->second - d.r) < p.goalHandoff && t - o.tTake >= 1.0) {
            o.owned = false;
            o.tHandoff = t;
            Command c;
            c.type = Command::Release;
            c.id = d.id;
            cmds.push_back(c);
            continue;
        }
        if (o.tClear && t - *o.tClear >= p.releaseHold && t - o.tTake >= p.minOwnTime) {
            o.owned = false;
            Command c;
            c.type = Command::Release;
            c.id = d.id;
            cmds.push_back(c);
            continue;
        }
        const auto v = _velocity(d, drones, risk[d.id]);
        Command c;
        c.type = Command::Vel;
        c.id = d.id;
        c.v[0] = v[0]; c.v[1] = v[1]; c.v[2] = v[2];
        cmds.push_back(c);
    }
    return cmds;
}

std::array<double, 3> GuardCore::_velocity(const DroneIn &d, const std::vector<DroneIn> &drones, int level)
{
    const Params &p = params;
    Own &o = own[d.id];
    std::pair<double, double> goal;
    if (d.goal) {
        goal = *d.goal;
    } else {
        const double sp = norm2(d.vf, d.vr);
        goal = sp > 0.3 ? std::make_pair(d.f + 10 * d.vf / sp, d.r + 10 * d.vr / sp) : std::make_pair(d.f, d.r);
    }
    std::vector<DroneIn> others;
    for (const DroneIn &x : drones) {
        if (x.id != d.id && x.inAir) {
            others.push_back(x);
        }
    }
    const bool emerg = level >= 2;
    // merging at the same point: the lower-priority vehicle yields (waits in place)
    o.yielding = false;
    if (d.goal) {
        for (const DroneIn &x : others) {
            if (x.prio < d.prio && x.fresh && x.goal && std::abs(x.u - d.u) <= p.vSep &&
                norm2(x.goal->first - d.goal->first, x.goal->second - d.goal->second) < p.dSafe &&
                norm2(x.f - d.f, x.r - d.r) < 3 * p.dSafe) {
                goal = {d.f, d.r};
                o.yielding = true;
                break;
            }
        }
    }
    const auto [vf, vr] = acactVelocity(p, d, others, goal, emerg);
    // altitude: hold the takeover altitude; in an emergency only the lower-priority vehicle climbs
    double targetU = o.holdU;
    if (emerg) {
        bool lower = false;
        for (const DroneIn &x : others) {
            if (std::abs(x.u - d.u) <= p.vSep && norm2(x.f - d.f, x.r - d.r) < p.dEmerg + 2.0 && x.prio < d.prio) {
                lower = true;
            }
        }
        if (lower) {
            targetU = std::min(d.u + 2.0, o.holdU + p.emergClimbMax);
            o.holdU = std::max(o.holdU, std::min(d.u, o.holdU + p.emergClimbMax));
        }
    }
    const double vu = std::max(-p.maxClimb, std::min(p.maxClimb, p.altHoldKp * (targetU - d.u)));
    return {vf, vr, vu};
}

} // namespace mlacact
