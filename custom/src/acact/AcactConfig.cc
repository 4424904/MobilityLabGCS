#include "AcactConfig.h"

#include <algorithm>

namespace acact {

namespace {
const std::map<std::string, std::map<std::string, std::pair<double, double>>> &layouts()
{
    static const std::map<std::string, std::map<std::string, std::pair<double, double>>> L = {
        // oregon: computed from homeLineF / homeSpacing
        {"oregon2", {{"D1", {-35.0, -7.5}}, {"D2", {-35.0, 7.5}}, {"D3", {-35.0, 22.5}}, {"D4", {-35.0, -22.5}}}},
        {"hwaseong", {{"D1", {-37.0, -5.0}}, {"D2", {-37.0, 5.0}}, {"D3", {-47.0, -5.0}}, {"D4", {-47.0, 5.0}}}},
    };
    return L;
}
}

std::vector<std::string> profileNames()
{
    return {"oregon", "oregon2", "hwaseong"};
}

void Config::selectDrones(const std::vector<std::string> &ids)
{
    drones.clear();
    for (const DroneCfg &d : allDrones) {
        if (ids.empty() || std::find(ids.begin(), ids.end(), d.id) != ids.end()) {
            drones.push_back(d);
        }
    }
}

Config Config::forDrones(const std::vector<std::string> &ids, const std::string &prof)
{
    Config c;
    c.profile = prof;
    c.selectDrones(ids);
    c.duo = c.drones.size() == 2;
    if (c.duo) {
        // config.py: 2-drone demo — more room to dodge, so avoid earlier and faster
        c.maxHSpeed = 4.5;
        c.dSafe = 12.0;
        c.acact.rs = 14.0;
        c.acact.k_cpa = 3.0;
    }
    return c;
}

std::optional<std::pair<double, double>> Config::layoutHome(const std::string &id) const
{
    const auto it = layouts().find(profile);
    if (it == layouts().end()) {
        return std::nullopt;
    }
    const auto jt = it->second.find(id);
    if (jt == it->second.end()) {
        return std::nullopt;
    }
    return jt->second;
}

double Config::homeCenterF() const
{
    if (profile == "hwaseong") {
        return -42.0;
    }
    return homeLineF;
}

const DroneCfg *Config::drone(const std::string &id) const
{
    for (const DroneCfg &d : allDrones) {
        if (d.id == id) {
            return &d;
        }
    }
    return nullptr;
}

int Config::indexInAll(const std::string &id) const
{
    for (size_t i = 0; i < allDrones.size(); i++) {
        if (allDrones[i].id == id) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

} // namespace acact
