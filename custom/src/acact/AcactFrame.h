#pragma once
// AcactFrame — port of ACACT Guard geo.py: lat/lon <-> demo frame (F forward, R right)
#include <cmath>
#include <utility>

namespace mlacact {

// same constants as CPython math.radians / math.degrees
constexpr double kPi = 3.14159265358979323846;
constexpr double kDegToRad = kPi / 180.0;
constexpr double kRadToDeg = 180.0 / kPi;

class Frame {
public:
    Frame() = default;
    Frame(double lat0, double lon0, double bearingDeg)
        : lat0(lat0), lon0(lon0), bearingDeg(bearingDeg), _b(bearingDeg * kDegToRad), _cos0(std::cos(lat0 * kDegToRad)) {}

    std::pair<double, double> neToFr(double n, double e) const
    {
        const double cb = std::cos(_b), sb = std::sin(_b);
        return {n * cb + e * sb, -n * sb + e * cb};
    }
    std::pair<double, double> frToNe(double f, double r) const
    {
        const double cb = std::cos(_b), sb = std::sin(_b);
        return {f * cb - r * sb, f * sb + r * cb};
    }
    std::pair<double, double> llToFr(double lat, double lon) const
    {
        const double n = (lat - lat0) * kDegToRad * R_EARTH;
        const double e = (lon - lon0) * kDegToRad * R_EARTH * _cos0;
        return neToFr(n, e);
    }
    std::pair<double, double> frToLl(double f, double r) const
    {
        const auto [n, e] = frToNe(f, r);
        return {lat0 + (n / R_EARTH) * kRadToDeg, lon0 + (e / (R_EARTH * _cos0)) * kRadToDeg};
    }

    double lat0 = 0, lon0 = 0, bearingDeg = 0;
    static constexpr double R_EARTH = 6378137.0;

private:
    double _b = 0, _cos0 = 1;
};

} // namespace mlacact
