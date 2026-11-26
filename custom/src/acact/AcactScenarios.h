// ACACT engine — demo scenarios and demo frame (port of scenarios.py and geo.py, rev1)
#pragma once

#include "AcactConfig.h"

#include <array>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace acact {

/// One mission item in the demo frame (scenarios.py item dict)
struct Item {
    enum Type { Takeoff, Sync, Speed, Wp, Land } type = Wp;
    double f = 0, r = 0;            // "p"
    bool   hasP = false;
    std::optional<double> alt;      // "alt"
    double hold = 0;                // "hold" (wp)
    bool   hasHold = false;
    double v = 0;                   // "v" (speed)
    std::string tag;                // "start" / "end" / ""
};

using Mission = std::vector<Item>;

struct ScenarioInfo {
    std::string name;
    std::string title;
};

class Scenarios {
public:
    /// ids: active drones (subset of D1..D4), profile: oregon / oregon2 / hwaseong
    Scenarios(const Config &c, const std::vector<std::string> &ids);

    static std::vector<ScenarioInfo> list();
    bool available(const std::string &name) const;
    /// name: S0_integrated … S7_duo, mode: "demo" | "rehearsal"
    std::map<std::string, Mission> build(const std::string &name, const std::string &mode) const;

    std::array<double, 2> home(const std::string &id) const;
    std::array<double, 2> stepPos(const std::string &id) const;
    double layer(const std::string &id) const;

private:
    struct Leg { std::string id; std::array<double, 2> start; std::vector<Item> legs; };
    std::vector<Leg> _scenario(const std::string &name) const;
    bool _directOk(const std::map<std::string, std::array<double, 2>> &starts) const;
    std::map<std::string, std::string> _assign(const std::vector<std::string> &ids,
                                               const std::vector<std::pair<std::string, std::array<double, 2>>> &slotList) const;

    Config _c;
    std::vector<std::string> _ids;
};

/// geo.py Frame: lat/lon ↔ demo frame (F forward, R right)
class Frame {
public:
    Frame(double lat0, double lon0, double bearingDeg = 0.0);
    std::array<double, 2> neToFr(double n, double e) const;
    std::array<double, 2> frToNe(double f, double r) const;
    std::array<double, 2> llToFr(double lat, double lon) const;
    std::array<double, 2> frToLl(double f, double r) const;
    double lat0() const { return _lat0; }
    double lon0() const { return _lon0; }
    double bearingDeg() const { return _bearingDeg; }

private:
    double _lat0, _lon0, _bearingDeg, _b, _cos0;
};

} // namespace acact
