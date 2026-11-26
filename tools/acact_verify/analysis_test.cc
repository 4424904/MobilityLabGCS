// Regression test: MLFlightAnalysis on a synthetic log (two vehicles head-on, D2 dodges 55–65 s, D2 link gap 90–93 s)
//   needs Qt6 Core/Gui; run with QT_QPA_PLATFORM=offscreen
#include "MLFlightAnalysis.h"

#include <QtCore/QFile>
#include <QtGui/QGuiApplication>
#include <cmath>
#include <cstdio>

static int fails = 0;
#define CHECK(c, w) do { if (c) std::printf("ok    %s\n", w); else { fails++; std::printf("FAIL  %s\n", w); } } while (0)

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    MLFlightAnalysis a;
    a.setLogDir(QString::fromLocal8Bit(argv[1]));
    a.refresh();
    CHECK(a.sessions().size() == 1, "one session listed");
    CHECK(a.load(QStringLiteral("20261126_101500")), "load");
    CHECK(std::fabs(a.duration() - 119.95) < 0.1, "duration 120 s");
    const QVariantMap p = a.pairs().value(0).toMap();
    const double minSame = p.value(QStringLiteral("minSame")).toDouble();
    std::printf("      minSame %.2f at %.1f s, below D_SAFE %.1f s\n", minSame, p.value(QStringLiteral("tMin")).toDouble(), p.value(QStringLiteral("belowSafe")).toDouble());
    CHECK(minSame > 4.0 && minSame < 6.5, "minimum same-layer separation where D2 dodged (≈6 m)");
    std::printf("      interventions %d\n", int(a.interventions().size()));
    CHECK(a.interventions().size() == 1 && a.interventions().value(0).toMap().value(QStringLiteral("id")).toString() == QStringLiteral("D2"), "one intervention by D2");
    const double dur = a.interventions().value(0).toMap().value(QStringLiteral("dur")).toDouble();
    CHECK(dur > 9.5 && dur < 10.1, "intervention ≈10 s");
    const QVariantMap v2 = a.vehicles().value(1).toMap();
    CHECK(std::fabs(v2.value(QStringLiteral("maxLinkGap")).toDouble() - 3.0) < 0.2, "D2 link gap 3 s");
    CHECK(a.events().size() == 2, "events");
    CHECK(a.verdict().value(QStringLiteral("pass")).toBool() == (minSame >= 5.5), "verdict follows D_EMERG");
    const QVariantList st = a.stateAt(50.0);
    CHECK(st.size() == 2 && std::fabs(st[0].toMap().value(QStringLiteral("r")).toDouble() - (-30 + 0.6 * 50)) < 0.2, "replay state at 50 s");
    const QString pdf = a.exportPdf(QString::fromLocal8Bit(argv[1]) + QStringLiteral("/report.pdf"));
    QFile f(pdf);
    CHECK(!pdf.isEmpty() && f.exists() && f.size() > 20000, "PDF written");
    std::printf("analysis_test: %d failed\n", fails);
    return fails ? 1 : 0;
}
