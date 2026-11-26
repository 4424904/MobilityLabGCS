// compare.cpp — replay reference traces (recorded from the ORIGINAL Python
// ACACT Guard by record_traces.py) through the C++ port and compare every
// command: type, vehicle, velocity (|Δ| <= tol) and event text.
//
//   g++ -std=c++17 -O2 -I../../custom/src/acact compare.cpp ../../custom/src/acact/AcactCore.cpp -o acact_compare
//   ./acact_compare <trace files...>
//
// Exit 0 only if every trace matches.
#include "AcactCore.h"

#include <cmath>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using namespace mlacact;

struct Ref {
    Command::Type type;
    std::string id, text;
    double v[3] = {0, 0, 0};
};

static Command::Type typeOf(const std::string &k)
{
    if (k == "takeover") return Command::Takeover;
    if (k == "vel") return Command::Vel;
    return Command::Release;
}
static const char *typeName(Command::Type t)
{
    switch (t) {
    case Command::Takeover: return "takeover";
    case Command::Vel: return "vel";
    case Command::Release: return "release";
    default: return "event";
    }
}

int main(int argc, char **argv)
{
    const double tol = 1e-9;
    int failedTraces = 0;
    long totalSteps = 0, totalCmds = 0, totalTakeovers = 0;
    double worstDiff = 0;
    for (int ai = 1; ai < argc; ai++) {
        const std::string path = argv[ai];
        std::ifstream in(path);
        if (!in) { std::cerr << "cannot open " << path << "\n"; return 2; }
        std::vector<std::string> lines;
        std::string ln;
        std::set<std::string> idset;
        int nDrones = 4;
        while (std::getline(in, ln)) {
            if (ln.rfind("D ", 0) == 0) {
                std::istringstream ss(ln.substr(2));
                std::string id; ss >> id; idset.insert(id);
            } else if (ln.rfind("P ", 0) == 0) {
                nDrones = std::stoi(ln.substr(2));
            }
            lines.push_back(ln);
        }
        std::vector<std::string> ids(idset.begin(), idset.end());
        GuardCore core(ids, Params::forVehicleCount(nDrones));

        long steps = 0, cmdsN = 0, mismatches = 0;
        double maxDiff = 0;
        std::string firstMismatch;
        size_t i = 0;
        while (i < lines.size()) {
            const std::string &l = lines[i];
            if (l.rfind("S ", 0) != 0) { i++; continue; }
            double t; int n;
            { std::istringstream ss(l.substr(2)); ss >> t >> n; }
            i++;
            std::vector<DroneIn> ins;
            for (int k = 0; k < n; k++, i++) {
                std::istringstream ss(lines[i].substr(2));
                DroneIn d;
                int fresh, inAir, hasG, goalHold, hasGa, hasH;
                double gf, gr, ga, hf, hr;
                ss >> d.id >> d.prio >> fresh >> d.age >> d.f >> d.r >> d.u >> d.vf >> d.vr >> d.vu >> d.relAlt >> inAir >> d.mode
                   >> hasG >> gf >> gr >> d.rtlAlt >> goalHold >> hasGa >> ga >> hasH >> hf >> hr;
                d.fresh = fresh; d.inAir = inAir; d.goalHold = goalHold;
                if (hasG) d.goal = std::make_pair(gf, gr);
                if (hasGa) d.goalAlt = ga;
                if (hasH) d.home = std::make_pair(hf, hr);
                ins.push_back(d);
            }
            std::vector<Ref> ref;
            while (i < lines.size() && (lines[i].rfind("C ", 0) == 0 || lines[i].rfind("E ", 0) == 0)) {
                Ref r;
                if (lines[i][0] == 'C') {
                    std::istringstream ss(lines[i].substr(2));
                    std::string k; ss >> k >> r.id >> r.v[0] >> r.v[1] >> r.v[2];
                    r.type = typeOf(k);
                } else {
                    r.type = Command::Event;
                    const std::string rest = lines[i].substr(2);
                    const size_t sp = rest.find(' ');
                    r.id = rest.substr(0, sp);
                    r.text = rest.substr(sp + 1);
                }
                ref.push_back(r);
                i++;
            }
            const auto got = core.step(t, ins);
            steps++;
            cmdsN += static_cast<long>(ref.size());
            bool ok = got.size() == ref.size();
            for (size_t c = 0; ok && c < got.size(); c++) {
                if (got[c].type != ref[c].type || got[c].id != ref[c].id) { ok = false; break; }
                if (got[c].type == Command::Takeover) totalTakeovers++;
                if (got[c].type == Command::Event) { if (got[c].text != ref[c].text) ok = false; continue; }
                for (int q = 0; q < 3; q++) {
                    const double df = std::abs(got[c].v[q] - ref[c].v[q]);
                    maxDiff = std::max(maxDiff, df);
                    if (!(df <= tol)) ok = false;
                }
            }
            if (!ok) {
                mismatches++;
                if (firstMismatch.empty()) {
                    std::ostringstream os;
                    os.precision(17);
                    os << "  first mismatch at t=" << t << "\n    python:";
                    for (auto &r : ref) os << " [" << typeName(r.type) << " " << r.id << " " << r.v[0] << "," << r.v[1] << "," << r.v[2] << " " << r.text << "]";
                    os << "\n    c++   :";
                    for (auto &g : got) os << " [" << typeName(g.type) << " " << g.id << " " << g.v[0] << "," << g.v[1] << "," << g.v[2] << " " << g.text << "]";
                    firstMismatch = os.str();
                }
            }
        }
        totalSteps += steps;
        totalCmds += cmdsN;
        worstDiff = std::max(worstDiff, maxDiff);
        const std::string name = path.substr(path.find_last_of('/') + 1);
        std::printf("%-48s steps %6ld  cmds %6ld  max|dv| %.3g  %s\n", name.c_str(), steps, cmdsN, maxDiff,
                    mismatches ? ("MISMATCH x" + std::to_string(mismatches)).c_str() : "OK");
        if (mismatches) {
            failedTraces++;
            std::cout << firstMismatch << "\n";
        }
    }
    std::printf("\nTOTAL: %d traces, %ld guard steps, %ld commands (%ld takeovers), worst |dv| %.3g — %s\n", argc - 1,
                totalSteps, totalCmds, totalTakeovers, worstDiff, failedTraces ? "FAIL" : "IDENTICAL");
    return failedTraces ? 1 : 0;
}
