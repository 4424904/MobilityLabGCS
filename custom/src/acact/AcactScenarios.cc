// Port of scenarios.py and geo.py (rev1). Arithmetic follows the Python
// expressions term by term (pow for **0.5, Python-style round) so that
// tests/acact_compare.py can require bit-identical missions.
#include "AcactScenarios.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <numeric>

namespace acact {

namespace {
constexpr double PI = 3.14159265358979323846;
constexpr double DEG2RAD = PI / 180.0;   // CPython math.radians
constexpr double RAD2DEG = 180.0 / PI;   // CPython math.degrees
constexpr double R_EARTH = 6378137.0;

double pyRound2(double x)
{
    char b[64];
    std::snprintf(b, sizeof b, "%.2f", x);
    return std::strtod(b, nullptr);
}

using P = std::array<double, 2>;

Item wp(P p, double hold = 0.0)
{
    Item it;
    it.type = Item::Wp; it.f = p[0]; it.r = p[1]; it.hasP = true; it.hold = hold; it.hasHold = true;
    return it;
}
Item sync(P p)
{
    Item it;
    it.type = Item::Sync; it.f = p[0]; it.r = p[1]; it.hasP = true;
    return it;
}
Item spd(double v)
{
    Item it;
    it.type = Item::Speed; it.v = v;
    return it;
}
} // namespace

Scenarios::Scenarios(const Config &c, const std::vector<std::string> &ids)
    : _c(c), _ids(ids)
{
}

std::vector<ScenarioInfo> Scenarios::list()
{
    return {
        {"S7_duo", "2대 역동 시나리오 (편대 대시·고속 정면·직각·역선회·추월)"},
        {"S0_integrated", "통합 1회 비행 (S1→S3→S2→S4→S6)"},
        {"S1_formation", "편대 출격"},
        {"S2_headon", "정면 교차 (2쌍 순차)"},
        {"S3_cross4", "4방향 중앙 동시 교차"},
        {"S4_merge", "거점 합류·포위"},
        {"S5_survey", "구역 4분할 정찰"},
        {"S6_linkloss", "통신 두절 대응"},
    };
}

bool Scenarios::available(const std::string &name) const
{
    if (name == "S7_duo") {
        return _ids.size() == 2;
    }
    for (const auto &s : list()) {
        if (s.name == name) {
            return true;
        }
    }
    return false;
}

std::array<double, 2> Scenarios::home(const std::string &id) const
{
    auto lay = _c.homeLayouts.find(_c.profile);
    if (lay != _c.homeLayouts.end() && !lay->second.empty()) {
        auto it = lay->second.find(id);
        if (it != lay->second.end()) {
            return {it->second.first, it->second.second};
        }
    }
    int i = 0;
    for (size_t k = 0; k < _c.allDrones.size(); k++) {
        if (_c.allDrones[k].id == id) {
            i = static_cast<int>(k);
        }
    }
    return {_c.homeLineF, (i - 1.5) * _c.homeSpacing};
}

std::array<double, 2> Scenarios::stepPos(const std::string &id) const
{
    const auto h = home(id);
    return {h[0] + _c.stepFwd, h[1]};
}

double Scenarios::layer(const std::string &id) const
{
    const DroneSlot *s = _c.slot(id);
    return s ? s->layer : 20.0;
}

std::map<std::string, std::string> Scenarios::_assign(const std::vector<std::string> &ids,
                                                      const std::vector<std::pair<std::string, P>> &slots) const
{
    // itertools.permutations(keys, len(ids)) order, first minimum kept
    std::vector<int> idx(slots.size());
    std::iota(idx.begin(), idx.end(), 0);
    std::map<std::string, std::string> best;
    double bestc = 1e18;
    do {
        double cost = 0.0;
        for (size_t i = 0; i < ids.size(); i++) {
            const P p = stepPos(ids[i]);
            const P q = slots[idx[i]].second;
            cost += (p[0] - q[0]) * (p[0] - q[0]) + (p[1] - q[1]) * (p[1] - q[1]);
        }
        if (cost < bestc) {
            bestc = cost;
            best.clear();
            for (size_t i = 0; i < ids.size(); i++) {
                best[ids[i]] = slots[idx[i]].first;
            }
        }
    } while (std::next_permutation(idx.begin(), idx.end()));
    return best;
}

bool Scenarios::_directOk(const std::map<std::string, P> &starts) const
{
    const double speed = _c.lowTransitSpeed;
    struct Path { P a, b; double L; };
    std::vector<std::string> ids = _ids;   // dict order = IDS order
    std::map<std::string, Path> path;
    double maxL = 0;
    for (const auto &d : ids) {
        const P a = stepPos(d), b = starts.at(d);
        const double L = std::pow((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]), 0.5);
        path[d] = {a, b, L};
        maxL = std::max(maxL, L);
    }
    const double T = maxL / speed + 1.0;
    auto at = [&](const std::string &d, double t) {
        const Path &p = path[d];
        const double k = p.L < 1e-6 ? 1.0 : std::min(1.0, speed * t / p.L);
        return P {p.a[0] + (p.b[0] - p.a[0]) * k, p.a[1] + (p.b[1] - p.a[1]) * k};
    };
    for (size_t i = 0; i < ids.size(); i++) {
        for (size_t j = i + 1; j < ids.size(); j++) {
            P pa = at(ids[i], 0), pb = at(ids[j], 0);
            const double d0 = std::pow((pa[0] - pb[0]) * (pa[0] - pb[0]) + (pa[1] - pb[1]) * (pa[1] - pb[1]), 0.5);
            double t = 0.0;
            while (t <= T) {
                pa = at(ids[i], t);
                pb = at(ids[j], t);
                const double dd = std::pow((pa[0] - pb[0]) * (pa[0] - pb[0]) + (pa[1] - pb[1]) * (pa[1] - pb[1]), 0.5);
                if (dd < std::min(d0, _c.dSafe + 2.0) - 0.5) {
                    return false;
                }
                t += 0.2;
            }
        }
    }
    return true;
}

std::vector<Scenarios::Leg> Scenarios::_scenario(const std::string &name) const
{
    const double R = _c.scenarioRadius;
    const P N_ {R, 0.0}, S_ {-R, 0.0}, E_ {0.0, R}, W_ {0.0, -R};
    std::vector<Leg> out;

    if (name == "S1_formation") {
        const std::vector<std::pair<std::string, P>> off = {{"D1", {8, -8}}, {"D2", {8, 8}}, {"D3", {-8, -8}}, {"D4", {-8, 8}}};
        const std::vector<P> path = {{-15, -15}, {15, -15}, {15, 15}, {-15, 15}, {-15, -15}};
        for (const auto &[d, o] : off) {
            std::vector<P> pts;
            for (const P &p : path) pts.push_back({p[0] + o[0], p[1] + o[1]});
            Leg l {d, pts[0], {}};
            for (size_t k = 1; k < pts.size(); k++) l.legs.push_back(wp(pts[k]));
            out.push_back(l);
        }
    } else if (name == "S2_headon") {
        out.push_back({"D1", W_, {wp(E_, 30), wp(W_)}});
        out.push_back({"D3", E_, {wp(W_, 30), wp(E_)}});
        out.push_back({"D2", N_, {wp(N_, 25), wp(S_, 30), wp(N_)}});
        out.push_back({"D4", S_, {wp(S_, 25), wp(N_, 30), wp(S_)}});
    } else if (name == "S3_cross4") {
        const std::vector<std::pair<std::string, std::pair<P, P>>> st = {
            {"D1", {W_, E_}}, {"D2", {N_, S_}}, {"D3", {E_, W_}}, {"D4", {S_, N_}}};
        for (const auto &[d, so] : st) out.push_back({d, so.first, {wp(so.second, 10), wp(so.first)}});
    } else if (name == "S4_merge") {
        const double rr = 14.0;
        const std::map<std::string, P> ring = {{"N", {rr, 0}}, {"W", {0, -rr}}, {"S", {-rr, 0}}, {"E", {0, rr}}};
        const std::vector<std::string> order = {"N", "W", "S", "E"};
        const P gateW {0, -24}, gateE {0, 24};
        struct Pl { std::string d; P st; P gate; std::string slot; };
        const std::vector<Pl> plan = {{"D1", {20, -34}, gateW, "N"}, {"D2", {-20, -34}, gateW, "W"},
                                      {"D3", {20, 34}, gateE, "E"}, {"D4", {-20, 34}, gateE, "S"}};
        for (const auto &pl : plan) {
            const int k = static_cast<int>(std::find(order.begin(), order.end(), pl.slot) - order.begin());
            Leg l {pl.d, pl.st, {wp(pl.gate), wp(ring.at(pl.slot)), sync(ring.at(pl.slot))}};
            for (int i = 1; i <= 4; i++) l.legs.push_back(wp(ring.at(order[(k + i) % 4])));
            out.push_back(l);
        }
    } else if (name == "S5_survey") {
        const std::vector<P> base = {{4, 4}, {4, 26}, {11, 26}, {11, 4}, {18, 4}, {18, 26}, {25, 26}, {25, 4}};
        const std::vector<std::pair<std::string, P>> org = {{"D1", {0, -30}}, {"D2", {0, 0}}, {"D3", {-30, -30}}, {"D4", {-30, 0}}};
        for (const auto &[d, o] : org) {
            std::vector<P> pts;
            for (const P &p : base) pts.push_back({p[0] + o[0], p[1] + o[1]});
            Leg l {d, pts[0], {}};
            for (size_t k = 1; k < pts.size(); k++) l.legs.push_back(wp(pts[k]));
            out.push_back(l);
        }
    } else if (name == "S6_linkloss") {
        const std::vector<std::pair<std::string, P>> st = {{"D1", W_}, {"D2", N_}, {"D3", E_}, {"D4", S_}};
        for (const auto &[d, p] : st) out.push_back({d, p, {sync(p)}});
    } else if (name == "S0_integrated") {
        const std::vector<std::pair<std::string, P>> off = {{"FL", {8, -8}}, {"FR", {8, 8}}, {"BL", {-8, -8}}, {"BR", {-8, 8}}};
        const std::map<std::string, std::string> ringOf = {{"FL", "N"}, {"FR", "E"}, {"BL", "W"}, {"BR", "S"}};
        const std::map<std::string, P> Pm = {{"N", N_}, {"E", E_}, {"W", W_}, {"S", S_}};
        const std::map<std::string, std::string> OPP = {{"N", "S"}, {"S", "N"}, {"E", "W"}, {"W", "E"}};
        const P f0 {-6.0, 0.0}, f1 {14.0, 0.0};
        std::vector<std::pair<std::string, P>> st;
        std::map<std::string, P> stm, fe;
        for (const auto &[k, o] : off) {
            st.push_back({k, {f0[0] + o[0], f0[1] + o[1]}});
            stm[k] = {f0[0] + o[0], f0[1] + o[1]};
            fe[k] = {f1[0] + o[0], f1[1] + o[1]};
        }
        const std::map<std::string, P> gate = {{"N", {12, -12}}, {"W", {12, -12}}, {"E", {-12, 12}}, {"S", {-12, 12}}};
        const double rr = 14.0;
        const std::map<std::string, P> slot = {{"N", {rr, 0}}, {"W", {0, -rr}}, {"S", {-rr, 0}}, {"E", {0, rr}}};
        const std::vector<std::string> order = {"N", "W", "S", "E"};
        std::map<std::string, std::string> role;
        if (_ids.size() == 4) {
            role = _assign(_ids, st);
        } else {
            const std::vector<std::string> pri = {"BL", "FR", "FL", "BR"};
            std::vector<std::pair<std::string, P>> sub;
            for (size_t i = 0; i < _ids.size() && i < pri.size(); i++) sub.push_back({pri[i], stm[pri[i]]});
            role = _assign(_ids, sub);
        }
        for (const auto &d : _ids) {
            const std::string fs = role[d];
            const std::string rg = ringOf.at(fs);
            const int k = static_cast<int>(std::find(order.begin(), order.end(), rg) - order.begin());
            const std::vector<P> half = {slot.at(order[(k + 1) % 4]), slot.at(order[(k + 2) % 4])};
            Leg l {d, stm[fs], {}};
            l.legs = {wp(fe[fs]), wp(Pm.at(rg)), sync(Pm.at(rg)), wp(Pm.at(OPP.at(rg))), sync(Pm.at(OPP.at(rg)))};
            if (rg == "N" || rg == "S") l.legs.push_back(wp(Pm.at(OPP.at(rg)), 12));
            else l.legs.push_back(wp(Pm.at(OPP.at(rg))));
            l.legs.push_back(wp(Pm.at(rg)));
            l.legs.push_back(sync(Pm.at(rg)));
            l.legs.push_back(wp(gate.at(rg)));
            l.legs.push_back(wp(slot.at(rg)));
            l.legs.push_back(sync(slot.at(rg)));
            for (const P &p : half) l.legs.push_back(wp(p));
            l.legs.push_back(sync(half.back()));
            out.push_back(l);
        }
    } else if (name == "S7_duo") {
        std::vector<std::string> ids = _ids;
        if (ids.size() < 2) ids.push_back("_");
        const std::string A = ids[0], B = ids[1];
        const double RO = 21.0;
        std::vector<P> circ;
        for (int k = 0; k < 9; k++) {
            const double th = (-90.0 - 45.0 * k) * DEG2RAD;
            circ.push_back({pyRound2(RO * std::cos(th)), pyRound2(RO * std::sin(th))});
        }
        const double RB = 15.0;
        std::vector<P> circB;
        for (const P &p : circ) circB.push_back({pyRound2(p[0] * RB / RO), pyRound2(-p[1] * RB / RO)});
        std::vector<Item> la = {spd(4.0), wp({15, -10}), spd(3.0), wp(W_), sync(W_), spd(4.5), wp(E_), sync(E_),
                                spd(3.0), wp(N_), sync(N_), spd(4.0), wp(S_), sync(S_), spd(3.0), wp(circ[0]), sync(circ[0]),
                                spd(3.0)};
        for (size_t k = 1; k < circ.size(); k++) la.push_back(wp(circ[k]));
        for (const Item &it : {sync(circ.back()), spd(3.0), wp({0, 0}), sync({0, 0}), spd(1.0), wp({6, 0}), sync({6, 0})}) la.push_back(it);
        std::vector<Item> lb = {spd(4.0), wp({15, 10}), spd(3.0), wp(E_), sync(E_), spd(4.5), wp(W_), sync(W_),
                                spd(3.0), wp(W_), sync(W_), spd(4.0), wp(E_), sync(E_), spd(3.0), wp(circB[0]), sync(circB[0]),
                                spd(3.0)};
        for (size_t k = 1; k < circB.size(); k++) lb.push_back(wp(circB[k]));
        for (const Item &it : {sync(circB.back()), spd(3.0), wp({-20, 4}), sync({-20, 4}), spd(4.0), wp({28, 4}), sync({28, 4})}) lb.push_back(it);
        for (const auto &d : _ids) {
            if (d == A) out.push_back({d, {-20, -10}, la});
            else if (d == B) out.push_back({d, {-20, 10}, lb});
        }
    }
    return out;
}

std::map<std::string, Mission> Scenarios::build(const std::string &name, const std::string &mode) const
{
    std::map<std::string, Mission> result;
    if (!available(name)) {
        return result;
    }
    const auto sc = _scenario(name);
    auto find = [&sc](const std::string &d) -> const Leg * {
        for (const Leg &l : sc) if (l.id == d) return &l;
        return nullptr;
    };
    bool direct = false;
    if (mode == "demo") {
        std::map<std::string, P> starts;
        bool all = true;
        for (const auto &d : _ids) {
            const Leg *l = find(d);
            if (!l) { all = false; break; }
            starts[d] = l->start;
        }
        direct = all && _directOk(starts);
    }
    for (const auto &d : _ids) {
        const Leg *L = find(d);
        if (!L) {
            continue;
        }
        const double lay = layer(d);
        const double alt = mode == "demo" ? _c.demoAlt : lay;
        const P h = home(d);
        const P s = L->start;
        const P f = stepPos(d);
        auto mk = [](Item::Type t, P p, std::optional<double> a, bool hasHold = false, double hold = 0, std::string tag = {}) {
            Item it;
            it.type = t; it.f = p[0]; it.r = p[1]; it.hasP = true; it.alt = a; it.hasHold = hasHold; it.hold = hold; it.tag = tag;
            return it;
        };
        Mission items = {mk(Item::Takeoff, h, _c.takeoffAlt), mk(Item::Sync, h, _c.takeoffAlt), spd(_c.lowTransitSpeed),
                         mk(Item::Wp, f, _c.takeoffAlt, true, 0), mk(Item::Sync, f, _c.takeoffAlt)};
        if (direct && alt == _c.takeoffAlt) {
            double maxf = -1e300;
            for (const auto &x : _ids) maxf = std::max(maxf, stepPos(x)[0]);
            if (f[0] < maxf - 5.0) items.push_back(mk(Item::Wp, f, alt, true, 3.0));
            items.push_back(mk(Item::Wp, s, alt, true, 0));
        } else {
            items.push_back(mk(Item::Wp, f, lay, true, 0));
            items.push_back(mk(Item::Sync, f, lay));
            items.push_back(spd(_c.transitSpeed));
            items.push_back(mk(Item::Wp, s, lay, true, 0));
            if (alt != lay) items.push_back(mk(Item::Wp, s, alt, true, 0));
        }
        items.push_back(mk(Item::Sync, s, alt, false, 0, "start"));
        items.push_back(spd(_c.scenarioSpeed));
        P last = s;
        for (Item it : L->legs) {
            if (it.hasP) {
                it.alt = alt;
                last = {it.f, it.r};
            }
            items.push_back(it);
        }
        items.push_back(mk(Item::Wp, last, lay, true, 0));
        items.push_back(mk(Item::Sync, last, lay, false, 0, "end"));
        items.push_back(spd(_c.transitSpeed));
        items.push_back(mk(Item::Wp, h, lay, true, 0));
        items.push_back(mk(Item::Sync, h, lay));
        items.push_back(mk(Item::Land, h, 0.0));
        // _speed_before_sync
        Mission out;
        for (const Item &it : items) {
            if (it.type == Item::Speed && !out.empty() && out.back().type == Item::Sync) {
                size_t j = out.size() - 1;
                while (j > 0 && out[j - 1].type == Item::Speed) j--;
                out.insert(out.begin() + static_cast<long>(j), it);
            } else {
                out.push_back(it);
            }
        }
        result[d] = out;
    }
    return result;
}

// ── Frame ─────────────────────────────────────────────────────
Frame::Frame(double lat0, double lon0, double bearingDeg)
    : _lat0(lat0), _lon0(lon0), _bearingDeg(bearingDeg), _b(bearingDeg * DEG2RAD), _cos0(std::cos(lat0 * DEG2RAD))
{
}

std::array<double, 2> Frame::neToFr(double n, double e) const
{
    const double cb = std::cos(_b), sb = std::sin(_b);
    return {n * cb + e * sb, -n * sb + e * cb};
}

std::array<double, 2> Frame::frToNe(double f, double r) const
{
    const double cb = std::cos(_b), sb = std::sin(_b);
    return {f * cb - r * sb, f * sb + r * cb};
}

std::array<double, 2> Frame::llToFr(double lat, double lon) const
{
    const double n = (lat - _lat0) * DEG2RAD * R_EARTH;
    const double e = (lon - _lon0) * DEG2RAD * R_EARTH * _cos0;
    return neToFr(n, e);
}

std::array<double, 2> Frame::frToLl(double f, double r) const
{
    const auto ne = frToNe(f, r);
    return {_lat0 + (ne[0] / R_EARTH) * RAD2DEG, _lon0 + (ne[1] / (R_EARTH * _cos0)) * RAD2DEG};
}

} // namespace acact
