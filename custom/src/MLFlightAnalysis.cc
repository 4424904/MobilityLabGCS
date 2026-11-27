#include "MLFlightAnalysis.h"

#include <QtSvg/QSvgRenderer>

#include <QtCore/QCoreApplication>

#include <cmath>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QStandardPaths>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtGui/QFont>
#include <QtGui/QFontMetricsF>
#include <QtGui/QPageSize>
#include <QtGui/QPainter>
#include <QtGui/QPainterPath>
#include <QtGui/QPdfWriter>

#include <algorithm>
#include <cmath>
#include <limits>
#include <tuple>

namespace {
constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();
// vehicle colours for white paper (darker than the screen palette, same order)
const char *kPaper[] = {"#1B6FA8", "#7B4FC9", "#4F7A12", "#C23D6E", "#15867E", "#B07A0E"};
QColor paperColor(int sysid) { return QColor(QLatin1String(kPaper[std::max(0, sysid - 1) % 6])); }

QString fmtDur(double s)
{
    const int m = static_cast<int>(s) / 60;
    return QStringLiteral("%1:%2").arg(m).arg(static_cast<int>(s) % 60, 2, 10, QLatin1Char('0'));
}

QStringList splitCsv(const QString &line)
{
    QStringList out;
    QString cur;
    bool q = false;
    for (QChar c : line) {
        if (c == QLatin1Char('"')) {
            q = !q;
        } else if (c == QLatin1Char(',') && !q) {
            out << cur;
            cur.clear();
        } else {
            cur += c;
        }
    }
    out << cur;
    return out;
}
} // namespace

MLFlightAnalysis::MLFlightAnalysis(QObject *parent)
    : QObject(parent)
{
}

QString MLFlightAnalysis::logDir() const
{
    if (!_dirOverride.isEmpty()) {
        return _dirOverride;
    }
    if (qEnvironmentVariableIsSet("MLGCS_PORTABLE_DIR")) {
        return QDir(qEnvironmentVariable("MLGCS_PORTABLE_DIR")).filePath(QStringLiteral("data/ACACT"));
    }
    return QDir(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)).filePath(QStringLiteral("MobilityLab/ACACT"));
}

void MLFlightAnalysis::refresh()
{
    _sessions.clear();
    QDir d(logDir());
    QFileInfoList files = d.entryInfoList({QStringLiteral("guard_*.csv")}, QDir::Files, QDir::Name | QDir::Reversed);
    for (const QFileInfo &fi : files) {
        const QString base = fi.completeBaseName();
        if (base.endsWith(QLatin1String("_events"))) {
            continue;
        }
        const QString stamp = base.mid(6);
        QVariantMap s{{QStringLiteral("stamp"), stamp}, {QStringLiteral("size"), fi.size()}};
        const QDateTime dt = QDateTime::fromString(stamp, QStringLiteral("yyyyMMdd_HHmmss"));
        s[QStringLiteral("date")] = dt.isValid() ? dt.toString(QStringLiteral("yyyy-MM-dd HH:mm")) : stamp;
        QFile mf(d.filePath(QStringLiteral("guard_%1_meta.json").arg(stamp)));
        if (mf.open(QIODevice::ReadOnly)) {
            const QJsonObject m = QJsonDocument::fromJson(mf.readAll()).object();
            s[QStringLiteral("plan")] = m.value(QStringLiteral("plan")).toString();
            s[QStringLiteral("opMode")] = m.value(QStringLiteral("opMode")).toString();
            s[QStringLiteral("duration")] = m.value(QStringLiteral("duration")).toDouble(-1);
            s[QStringLiteral("minSep")] = m.value(QStringLiteral("minSep")).toVariant();
            s[QStringLiteral("takeovers")] = m.value(QStringLiteral("takeovers")).toInt(-1);
            QStringList ids;
            for (const QJsonValue &v : m.value(QStringLiteral("vehicles")).toArray()) {
                ids << v.toObject().value(QStringLiteral("id")).toString();
            }
            s[QStringLiteral("vehicles")] = ids.join(QStringLiteral(", "));
        }
        _sessions.append(s);
    }
    emit sessionsChanged();
}

bool MLFlightAnalysis::load(const QString &stamp)
{
    QDir d(logDir());
    QFile f(d.filePath(QStringLiteral("guard_%1.csv").arg(stamp)));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }
    _stamp = stamp;
    _t.clear();
    _tr.clear();
    _info.clear();
    QTextStream ts(&f);
    const QStringList head = ts.readLine().split(QLatin1Char(','));
    // header: t, <id>_mode, _f, _r, _alt, _vf, _vr, _own, _fresh, _wp (× vehicles), min_pair, min_dist
    for (int c = 1; c + 8 < head.size(); c += 9) {
        if (!head[c].endsWith(QLatin1String("_mode"))) {
            break;
        }
        Track tr;
        tr.id = head[c].left(head[c].size() - 5);
        tr.sysid = tr.id.mid(1).toInt();
        tr.battCol = head.indexOf(tr.id + QStringLiteral("_batt"));
        _tr.append(tr);
    }
    while (!ts.atEnd()) {
        const QStringList c = ts.readLine().split(QLatin1Char(','));
        if (c.size() < 1 + 9 * _tr.size()) {
            continue;
        }
        _t.append(c[0].toDouble());
        for (int k = 0; k < _tr.size(); k++) {
            Track &tr = _tr[k];
            const int b = 1 + 9 * k;
            const bool ok = !c[b + 1].isEmpty();
            tr.mode.append(c[b]);
            tr.f.append(ok ? c[b + 1].toFloat() : NAN);
            tr.r.append(ok ? c[b + 2].toFloat() : NAN);
            tr.alt.append(ok ? c[b + 3].toFloat() : NAN);
            tr.spd.append(ok ? std::hypot(c[b + 4].toFloat(), c[b + 5].toFloat()) : NAN);
            tr.batt.append(tr.battCol > 0 && tr.battCol < c.size() && !c[tr.battCol].isEmpty() ? c[tr.battCol].toFloat() : NAN);
            tr.own.append(ok && c[b + 6] == QLatin1String("1"));
            tr.fresh.append(ok && c[b + 7] == QLatin1String("1"));
        }
    }
    // meta
    QFile mf(d.filePath(QStringLiteral("guard_%1_meta.json").arg(stamp)));
    if (mf.open(QIODevice::ReadOnly)) {
        const QJsonObject m = QJsonDocument::fromJson(mf.readAll()).object();
        _info = m.toVariantMap();
        const QJsonObject cfg = m.value(QStringLiteral("cfg")).toObject();
        _dSafe = cfg.value(QStringLiteral("dSafe")).toDouble(10);
        _dEmerg = cfg.value(QStringLiteral("dEmerg")).toDouble(5.5);
        _vSep = cfg.value(QStringLiteral("vSep")).toDouble(4);
        for (const QJsonValue &v : m.value(QStringLiteral("vehicles")).toArray()) {
            const QJsonObject o = v.toObject();
            for (Track &tr : _tr) {
                if (tr.id == o.value(QStringLiteral("id")).toString()) {
                    tr.controlled = o.value(QStringLiteral("supported")).toBool(true);
                    tr.sim = o.value(QStringLiteral("sim")).toInt(-1);
                    tr.sysid = o.value(QStringLiteral("sysid")).toInt(tr.sysid);
                }
            }
        }
    }
    _info[QStringLiteral("stamp")] = stamp;
    _info[QStringLiteral("logFile")] = f.fileName();
    // events
    _evV.clear();
    QFile ef(d.filePath(QStringLiteral("guard_%1_events.csv").arg(stamp)));
    if (ef.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream es(&ef);
        es.readLine();
        while (!es.atEnd()) {
            const QStringList c = splitCsv(es.readLine());
            if (c.size() >= 3) {
                _evV.append(QVariantMap{{QStringLiteral("t"), c[0].toDouble() - (_t.isEmpty() ? 0.0 : _t.first())},
                                        {QStringLiteral("who"), c[1]}, {QStringLiteral("text"), c.mid(2).join(QLatin1Char(','))}});
            }
        }
    }
    _compute();
    emit loadedChanged();
    return !_t.isEmpty();
}

void MLFlightAnalysis::_compute()
{
    _tracksV.clear();
    _pairsV.clear();
    _vehV.clear();
    _intV.clear();
    _verdict.clear();
    _extent.clear();
    const int n = _t.size();
    if (n == 0) {
        return;
    }
    const double t0 = _t.first();
    const int step = std::max(1, n / 1500);
    double fMin = 1e9, fMax = -1e9, rMin = 1e9, rMax = -1e9, aMax = 0;

    // tracks + per-vehicle stats
    for (const Track &tr : _tr) {
        QVariantList pts;
        double flight = 0, owned = 0, gap = 0, maxGap = 0, maxAlt = 0;
        int takeovers = 0;
        for (int i = 0; i < n; i++) {
            const double dt = i ? _t[i] - _t[i - 1] : 0;
            if (!std::isnan(tr.f[i])) {
                fMin = std::min<double>(fMin, tr.f[i]);
                fMax = std::max<double>(fMax, tr.f[i]);
                rMin = std::min<double>(rMin, tr.r[i]);
                rMax = std::max<double>(rMax, tr.r[i]);
                maxAlt = std::max<double>(maxAlt, tr.alt[i]);
            }
            const bool air = !std::isnan(tr.alt[i]) && tr.alt[i] > 1.0;
            if (air) {
                flight += dt;
            }
            if (tr.own[i]) {
                owned += dt;
            }
            if (i && tr.own[i] && !tr.own[i - 1]) {
                takeovers++;
            }
            if (air && !tr.fresh[i]) {
                gap += dt;
                maxGap = std::max(maxGap, gap);
            } else {
                gap = 0;
            }
            if (i % step == 0 && !std::isnan(tr.f[i])) {
                pts.append(QVariant(QVariantList{_t[i] - t0, tr.f[i], tr.r[i], tr.alt[i], tr.own[i],
                                                 std::isnan(tr.spd[i]) ? QVariant() : QVariant(tr.spd[i]),
                                                 std::isnan(tr.batt[i]) ? QVariant() : QVariant(tr.batt[i])}));
            }
        }
        aMax = std::max(aMax, maxAlt);
        _tracksV.append(QVariantMap{{QStringLiteral("id"), tr.id}, {QStringLiteral("sysid"), tr.sysid}, {QStringLiteral("points"), pts}});
        _vehV.append(QVariantMap{{QStringLiteral("id"), tr.id}, {QStringLiteral("sysid"), tr.sysid}, {QStringLiteral("controlled"), tr.controlled},
                                 {QStringLiteral("sim"), tr.sim}, {QStringLiteral("flightTime"), flight}, {QStringLiteral("takeovers"), takeovers},
                                 {QStringLiteral("ownedTime"), owned}, {QStringLiteral("maxLinkGap"), maxGap}, {QStringLiteral("maxAlt"), maxAlt}});
    }
    const double mf = std::max(10.0, 0.08 * std::max(fMax - fMin, rMax - rMin));
    _extent = {{QStringLiteral("fMin"), fMin - mf}, {QStringLiteral("fMax"), fMax + mf}, {QStringLiteral("rMin"), rMin - mf},
               {QStringLiteral("rMax"), rMax + mf}, {QStringLiteral("altMax"), std::max(10.0, aMax * 1.1)}};

    // pairs
    double worstSame = 1e9;
    for (int a = 0; a < _tr.size(); a++) {
        for (int b = a + 1; b < _tr.size(); b++) {
            const Track &A = _tr[a], &B = _tr[b];
            double minSame = 1e9, min3d = 1e9, tMin = -1, belowSafe = 0, belowEmerg = 0;
            QVariantList series;
            for (int i = 0; i < n; i++) {
                if (std::isnan(A.f[i]) || std::isnan(B.f[i])) {
                    continue;
                }
                const double dh = std::hypot(A.f[i] - B.f[i], A.r[i] - B.r[i]);
                const double dz = B.alt[i] - A.alt[i];
                const bool air = A.alt[i] > 1.0 && B.alt[i] > 1.0;
                const double dt = i ? _t[i] - _t[i - 1] : 0;
                if (air) {
                    min3d = std::min(min3d, std::hypot(dh, dz));
                    if (std::fabs(dz) < _vSep) {
                        if (dh < minSame) {
                            minSame = dh;
                            tMin = _t[i] - t0;
                        }
                        belowSafe += dh < _dSafe ? dt : 0;
                        belowEmerg += dh < _dEmerg ? dt : 0;
                    }
                }
                if (i % step == 0) {
                    series.append(QVariant(QVariantList{_t[i] - t0, dh, dz, air}));
                }
            }
            worstSame = std::min(worstSame, minSame);
            _pairsV.append(QVariantMap{{QStringLiteral("a"), A.id}, {QStringLiteral("b"), B.id},
                                       {QStringLiteral("minSame"), minSame < 1e8 ? QVariant(minSame) : QVariant()},
                                       {QStringLiteral("min3d"), min3d < 1e8 ? QVariant(min3d) : QVariant()}, {QStringLiteral("tMin"), tMin},
                                       {QStringLiteral("belowSafe"), belowSafe}, {QStringLiteral("belowEmerg"), belowEmerg},
                                       {QStringLiteral("series"), series}});
        }
    }

    // interventions
    for (const Track &tr : _tr) {
        int start = -1;
        for (int i = 0; i <= n; i++) {
            const bool o = i < n && tr.own[i];
            if (o && start < 0) {
                start = i;
            } else if (!o && start >= 0) {
                double nearest = 1e9;
                QString who;
                for (int k = start; k < i; k++) {
                    for (const Track &other : _tr) {
                        if (&other == &tr || std::isnan(other.f[k]) || std::isnan(tr.f[k])) {
                            continue;
                        }
                        const double d3 = std::hypot(std::hypot(tr.f[k] - other.f[k], tr.r[k] - other.r[k]), tr.alt[k] - other.alt[k]);
                        if (d3 < nearest) {
                            nearest = d3;
                            who = other.id;
                        }
                    }
                }
                const double ts = _t[start] - t0, te = _t[i - 1] - t0;
                _intV.append(QVariantMap{{QStringLiteral("id"), tr.id}, {QStringLiteral("sysid"), tr.sysid}, {QStringLiteral("t0"), ts},
                                         {QStringLiteral("t1"), te}, {QStringLiteral("dur"), te - ts},
                                         {QStringLiteral("nearest"), nearest < 1e8 ? QVariant(nearest) : QVariant()}, {QStringLiteral("other"), who}});
                start = -1;
            }
        }
    }
    std::sort(_intV.begin(), _intV.end(), [](const QVariant &x, const QVariant &y) {
        return x.toMap().value(QStringLiteral("t0")).toDouble() < y.toMap().value(QStringLiteral("t0")).toDouble();
    });

    // verdict
    int errors = 0;
    for (const QVariant &e : _evV) {
        if (e.toMap().value(QStringLiteral("text")).toString().contains(QStringLiteral("내부 오류"))) {
            errors++;
        }
    }
    const bool sepOk = worstSame >= 1e8 || worstSame >= _dEmerg;
    QStringList why;
    if (!sepOk) {
        why << tr("같은 층 최소 이격 %1 m < 긴급 거리 %2 m").arg(worstSame, 0, 'f', 1).arg(_dEmerg, 0, 'f', 1);
    }
    if (errors) {
        why << tr("가드 내부 오류 %1건").arg(errors);
    }
    _verdict = {{QStringLiteral("pass"), sepOk && errors == 0}, {QStringLiteral("minSame"), worstSame < 1e8 ? QVariant(worstSame) : QVariant()},
                {QStringLiteral("dSafe"), _dSafe}, {QStringLiteral("dEmerg"), _dEmerg}, {QStringLiteral("vSep"), _vSep},
                {QStringLiteral("reasons"), why}};
}

int MLFlightAnalysis::_row(double t) const
{
    if (_t.isEmpty()) {
        return -1;
    }
    const double tt = _t.first() + t;
    auto it = std::lower_bound(_t.begin(), _t.end(), tt);
    return std::clamp(static_cast<int>(it - _t.begin()), 0, static_cast<int>(_t.size()) - 1);
}

QVariantList MLFlightAnalysis::stateAt(double t) const
{
    QVariantList out;
    const int i = _row(t);
    if (i < 0) {
        return out;
    }
    for (const Track &tr : _tr) {
        if (std::isnan(tr.f[i])) {
            continue;
        }
        // velocity from the neighbouring rows (for the heading marker)
        const int j = std::max(0, i - 4);
        const double dt = std::max(1e-3, _t[i] - _t[j]);
        out.append(QVariantMap{{QStringLiteral("id"), tr.id}, {QStringLiteral("sysid"), tr.sysid}, {QStringLiteral("f"), tr.f[i]},
                               {QStringLiteral("r"), tr.r[i]}, {QStringLiteral("alt"), tr.alt[i]}, {QStringLiteral("own"), bool(tr.own[i])},
                               {QStringLiteral("fresh"), bool(tr.fresh[i])}, {QStringLiteral("mode"), tr.mode[i]},
                               {QStringLiteral("spd"), std::isnan(tr.spd[i]) ? QVariant() : QVariant(tr.spd[i])},
                               {QStringLiteral("batt"), std::isnan(tr.batt[i]) ? QVariant() : QVariant(tr.batt[i])},
                               {QStringLiteral("vf"), std::isnan(tr.f[j]) ? 0.0 : (tr.f[i] - tr.f[j]) / dt},
                               {QStringLiteral("vr"), std::isnan(tr.r[j]) ? 0.0 : (tr.r[i] - tr.r[j]) / dt}});
    }
    return out;
}

QString MLFlightAnalysis::defaultReportPath() const
{
    return QDir(logDir()).filePath(QStringLiteral("ACACT_report_%1.pdf").arg(_stamp));
}

// ---------------------------------------------------------------------------
// PDF report
// ---------------------------------------------------------------------------
void MLFlightAnalysis::_drawTracks(QPainter &p, const QRectF &rc) const
{
    const double fMin = _extent.value(QStringLiteral("fMin")).toDouble(), fMax = _extent.value(QStringLiteral("fMax")).toDouble();
    const double rMin = _extent.value(QStringLiteral("rMin")).toDouble(), rMax = _extent.value(QStringLiteral("rMax")).toDouble();
    const double span = std::max(fMax - fMin, rMax - rMin);
    const double sc = std::min(rc.width(), rc.height()) / span;
    const QPointF c0(rc.center().x() - (rMin + rMax) / 2 * sc, rc.center().y() + (fMin + fMax) / 2 * sc);
    auto P = [&](double f, double r) { return QPointF(c0.x() + r * sc, c0.y() - f * sc); };
    p.save();
    p.setClipRect(rc);
    p.fillRect(rc, QColor(QStringLiteral("#F7F8FA")));
    // 10 m grid
    p.setPen(QPen(QColor(QStringLiteral("#E3E6EA")), 0.6));
    const double g = span > 300 ? 50 : (span > 120 ? 20 : 10);
    for (double f = std::floor(fMin / g) * g; f <= fMax; f += g) {
        p.drawLine(P(f, rMin), P(f, rMax));
    }
    for (double r = std::floor(rMin / g) * g; r <= rMax; r += g) {
        p.drawLine(P(fMin, r), P(fMax, r));
    }
    for (const Track &tr : _tr) {
        const QColor col = paperColor(tr.sysid);
        QPainterPath path;
        bool started = false;
        for (int i = 0; i < _t.size(); i += 2) {
            if (std::isnan(tr.f[i])) {
                continue;
            }
            const QPointF q = P(tr.f[i], tr.r[i]);
            if (!started) {
                path.moveTo(q);
                started = true;
            } else {
                path.lineTo(q);
            }
        }
        p.setPen(QPen(col, 1.6));
        p.drawPath(path);
        // guard-flown parts in brand red over the track
        p.setPen(QPen(QColor(QStringLiteral("#D80E18")), 3.0, Qt::SolidLine, Qt::RoundCap));
        for (int i = 2; i < _t.size(); i += 2) {
            if (tr.own[i] && tr.own[i - 2] && !std::isnan(tr.f[i]) && !std::isnan(tr.f[i - 2])) {
                p.drawLine(P(tr.f[i - 2], tr.r[i - 2]), P(tr.f[i], tr.r[i]));
            }
        }
        for (int i = 0; i < _t.size(); i++) {
            if (!std::isnan(tr.f[i])) {
                p.setPen(Qt::NoPen);
                p.setBrush(col);
                p.drawEllipse(P(tr.f[i], tr.r[i]), 3.5, 3.5);
                p.setPen(col);
                p.drawText(P(tr.f[i], tr.r[i]) + QPointF(6, -4), tr.id);
                break;
            }
        }
    }
    // scale bar
    p.setPen(QPen(QColor(QStringLiteral("#333")), 1.2));
    const QPointF s0(rc.left() + 12, rc.bottom() - 12);
    p.drawLine(s0, s0 + QPointF(g * sc, 0));
    p.drawText(s0 + QPointF(0, -5), QStringLiteral("%1 m").arg(g));
    p.drawText(QRectF(rc.right() - 60, rc.top() + 4, 56, 16), Qt::AlignRight, QStringLiteral("F ↑"));
    p.restore();
    p.setPen(QPen(QColor(QStringLiteral("#C9CED4")), 0.8));
    p.setBrush(Qt::NoBrush);
    p.drawRect(rc);
}

void MLFlightAnalysis::_drawSeries(QPainter &p, const QRectF &rc, bool altitude) const
{
    const double T = std::max(1.0, duration());
    const double yMax = altitude ? _extent.value(QStringLiteral("altMax")).toDouble() : std::max(30.0, _dSafe * 3);
    auto X = [&](double t) { return rc.left() + t / T * rc.width(); };
    auto Y = [&](double v) { return rc.bottom() - std::clamp(v / yMax, 0.0, 1.0) * rc.height(); };
    p.save();
    p.fillRect(rc, QColor(QStringLiteral("#F7F8FA")));
    // intervention bands
    for (const QVariant &iv : _intV) {
        const QVariantMap m = iv.toMap();
        p.fillRect(QRectF(QPointF(X(m.value(QStringLiteral("t0")).toDouble()), rc.top()), QPointF(X(m.value(QStringLiteral("t1")).toDouble()), rc.bottom())),
                   QColor(216, 14, 24, 28));
    }
    QFont small = p.font();
    small.setPointSizeF(6.5);
    p.setFont(small);
    p.setPen(QPen(QColor(QStringLiteral("#E3E6EA")), 0.6));
    for (int k = 1; k <= 4; k++) {
        const double v = yMax * k / 4;
        p.drawLine(QPointF(rc.left(), Y(v)), QPointF(rc.right(), Y(v)));
        p.setPen(QColor(QStringLiteral("#888")));
        p.drawText(QPointF(rc.left() + 2, Y(v) - 2), QString::number(v, 'f', 0) + QStringLiteral(" m"));
        p.setPen(QPen(QColor(QStringLiteral("#E3E6EA")), 0.6));
    }
    if (!altitude) {
        for (const auto &[val, col, name] : {std::tuple<double, const char *, QString>{_dSafe, "#E0A000", QStringLiteral("D_SAFE")},
                                             std::tuple<double, const char *, QString>{_dEmerg, "#D80E18", QStringLiteral("D_EMERG")}}) {
            p.setPen(QPen(QColor(QLatin1String(col)), 0.9, Qt::DashLine));
            p.drawLine(QPointF(rc.left(), Y(val)), QPointF(rc.right(), Y(val)));
            p.drawText(QPointF(rc.right() - 44, Y(val) - 2), name);
        }
        for (int k = 0; k < _pairsV.size(); k++) {
            const QVariantMap pm = _pairsV[k].toMap();
            QPainterPath path;
            bool started = false;
            for (const QVariant &sv : pm.value(QStringLiteral("series")).toList()) {
                const QVariantList s = sv.toList();
                if (!s[3].toBool()) {     // not both airborne
                    started = false;
                    continue;
                }
                const QPointF q(X(s[0].toDouble()), Y(std::fabs(s[2].toDouble()) < _vSep ? s[1].toDouble() : std::hypot(s[1].toDouble(), s[2].toDouble())));
                if (!started) {
                    path.moveTo(q);
                    started = true;
                } else {
                    path.lineTo(q);
                }
            }
            p.setPen(QPen(QColor(QLatin1String(kPaper[k % 6])), 1.3));
            p.drawPath(path);
            p.drawText(QPointF(rc.left() + 60 + k * 70, rc.top() + 10), pm.value(QStringLiteral("a")).toString() + QStringLiteral("–") + pm.value(QStringLiteral("b")).toString());
        }
    } else {
        for (const Track &tr : _tr) {
            QPainterPath path;
            bool started = false;
            for (int i = 0; i < _t.size(); i += 4) {
                if (std::isnan(tr.alt[i])) {
                    started = false;
                    continue;
                }
                const QPointF q(X(_t[i] - _t.first()), Y(tr.alt[i]));
                if (!started) {
                    path.moveTo(q);
                    started = true;
                } else {
                    path.lineTo(q);
                }
            }
            p.setPen(QPen(paperColor(tr.sysid), 1.3));
            p.drawPath(path);
        }
    }
    // time axis
    p.setPen(QColor(QStringLiteral("#888")));
    const double tick = T > 900 ? 120 : (T > 300 ? 60 : 30);
    for (double t = 0; t <= T; t += tick) {
        p.drawText(QPointF(X(t) - 8, rc.bottom() + 9), fmtDur(t));
    }
    p.restore();
    p.setPen(QPen(QColor(QStringLiteral("#C9CED4")), 0.8));
    p.setBrush(Qt::NoBrush);
    p.drawRect(rc);
}

QString MLFlightAnalysis::exportPdf(const QString &pathIn)
{
    if (!loaded()) {
        return QString();
    }
    QString path = pathIn.startsWith(QLatin1String("file:")) ? QUrl(pathIn).toLocalFile() : pathIn;
    if (path.isEmpty()) {
        path = defaultReportPath();
    }
    if (!path.endsWith(QLatin1String(".pdf"), Qt::CaseInsensitive)) {
        path += QStringLiteral(".pdf");
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    QPdfWriter w(path);
    w.setPageSize(QPageSize(QPageSize::A4));
    w.setPageMargins(QMarginsF(14, 14, 14, 14), QPageLayout::Millimeter);
    w.setResolution(144);
    w.setTitle(QStringLiteral("ACACT test report %1").arg(_stamp));
    w.setCreator(QStringLiteral("MobilityLab GCS"));
    QPainter p(&w);
    if (!p.isActive()) {
        return QString();
    }
    const QRectF page(QPointF(0, 0), QSizeF(w.width(), w.height()));
    const QString sans = QStringLiteral("IBM Plex Sans KR"), mono = QStringLiteral("IBM Plex Mono");
    auto font = [&](double pt, bool bold = false, bool m = false) {
        QFont f(m ? mono : sans);
        f.setPointSizeF(pt);
        f.setBold(bold);
        p.setFont(f);
    };
    const QColor ink(QStringLiteral("#15191E")), sub(QStringLiteral("#5A626B")), brand(QStringLiteral("#D80E18")), rule(QStringLiteral("#D5DAE0"));
    double y = 0;
    int pageNo = 1;
    QSvgRenderer logo(QStringLiteral(":/MobilityLab/logo.svg"));
    const bool demoLog = _info.value(QStringLiteral("opMode")).toString() == QLatin1String("demo");
    auto header = [&]() {
        p.fillRect(QRectF(0, 0, page.width(), 4), brand);
        if (logo.isValid()) {
            logo.render(&p, QRectF(0, 8, 30, 30));
        }
        font(8.5, true);
        p.setPen(ink);
        p.drawText(QRectF(36, 10, page.width(), 26), Qt::AlignLeft | Qt::AlignVCenter, QStringLiteral("MOBILITY LAB  ·  GCS"));
        font(7.5);
        p.setPen(sub);
        p.drawText(QRectF(0, 10, page.width(), 26), Qt::AlignRight | Qt::AlignVCenter, tr("ACACT 비행 시험 보고서 · %1 · %2쪽").arg(_stamp).arg(pageNo));
        // footer
        p.setPen(QPen(rule, 0.8));
        p.drawLine(QPointF(0, page.height() - 22), QPointF(page.width(), page.height() - 22));
        font(6.8);
        p.setPen(sub);
        p.drawText(QRectF(0, page.height() - 20, page.width(), 18), Qt::AlignLeft | Qt::AlignVCenter,
                   tr("MOBILITY LAB Co., Ltd. · MobilityLab GCS %1 · ACACT 가드 로그에서 자동 생성").arg(QStringLiteral(ML_GCS_VERSION)));
        p.drawText(QRectF(0, page.height() - 20, page.width(), 18), Qt::AlignRight | Qt::AlignVCenter,
                   tr("시뮬레이션 결과는 실제 비행 안전성을 보증하지 않음"));
        if (demoLog) {
            // demo runs are never test evidence: watermark every page
            p.save();
            p.translate(page.center());
            p.rotate(-30);
            QFont wf(sans);
            wf.setPointSizeF(54);
            wf.setBold(true);
            p.setFont(wf);
            p.setPen(QColor(106, 53, 184, 40));
            p.drawText(QRectF(-page.width(), -60, page.width() * 2, 120), Qt::AlignCenter, tr("데모 · 시험 기록 아님"));
            p.restore();
        }
        y = 50;
    };
    auto newPage = [&]() {
        w.newPage();
        pageNo++;
        header();
    };
    auto need = [&](double h) {
        if (y + h > page.height() - 30) {
            newPage();
        }
    };
    auto section = [&](const QString &t) {
        need(40);
        y += 8;
        font(10.5, true);
        p.setPen(ink);
        p.drawText(QRectF(0, y, page.width(), 30), Qt::AlignLeft | Qt::AlignVCenter, t);
        y += 32;
        p.setPen(QPen(rule, 1));
        p.drawLine(QPointF(0, y), QPointF(page.width(), y));
        y += 8;
    };
    auto table = [&](const QStringList &heads, const QList<QStringList> &rows, const QList<double> &widths) {
        const double rh = 25;
        need(rh * 2);
        double x = 0;
        font(7.5, true);
        p.setPen(sub);
        for (int c = 0; c < heads.size(); c++) {
            p.drawText(QRectF(x + 2, y, widths[c] * page.width() - 4, rh), Qt::AlignLeft | Qt::AlignVCenter, heads[c]);
            x += widths[c] * page.width();
        }
        y += rh;
        p.setPen(QPen(rule, 0.8));
        p.drawLine(QPointF(0, y), QPointF(page.width(), y));
        for (const QStringList &r : rows) {
            need(rh);
            x = 0;
            font(8);
            p.setPen(ink);
            for (int c = 0; c < r.size() && c < widths.size(); c++) {
                p.drawText(QRectF(x + 2, y, widths[c] * page.width() - 4, rh), Qt::AlignLeft | Qt::AlignVCenter, r[c]);
                x += widths[c] * page.width();
            }
            y += rh;
            p.setPen(QPen(QColor(QStringLiteral("#EDF0F3")), 0.6));
            p.drawLine(QPointF(0, y), QPointF(page.width(), y));
        }
        y += 6;
    };
    auto m1 = [](const QVariant &v) { return v.isValid() && !v.isNull() ? QString::number(v.toDouble(), 'f', 1) + QStringLiteral(" m") : QStringLiteral("—"); };

    // ---- page 1: title, verdict, conditions, results ----
    header();
    font(19, true);
    p.setPen(ink);
    p.drawText(QRectF(0, y, page.width(), 50), Qt::AlignLeft | Qt::AlignVCenter, tr("ACACT 충돌 회피 비행 시험 보고서"));
    y += 54;
    font(9.5);
    p.setPen(sub);
    const QString plan = _info.value(QStringLiteral("plan")).toString();
    const QString mode = _info.value(QStringLiteral("opMode")).toString();
    const QDateTime dt = QDateTime::fromString(_stamp, QStringLiteral("yyyyMMdd_HHmmss"));
    p.drawText(QRectF(0, y, page.width(), 24), Qt::AlignLeft | Qt::AlignVCenter,
               QStringLiteral("%1 · %2 · %3").arg(dt.isValid() ? dt.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")) : _stamp,
                                                  plan.isEmpty() ? tr("계획 정보 없음") : plan,
                                                  mode == QLatin1String("field") ? tr("실비행") : (mode == QLatin1String("sim") ? tr("시뮬레이션(SITL)") : (mode == QLatin1String("demo") ? tr("데모 (GCS 내장 시뮬레이션 · 시험 기록 아님)") : tr("운용 모드 기록 없음")))));
    y += 30;
    // verdict box
    const bool pass = _verdict.value(QStringLiteral("pass")).toBool();
    const QRectF vb(0, y, page.width(), 78);
    p.setPen(QPen(pass ? QColor(QStringLiteral("#1E8E4E")) : brand, 1.6));
    p.setBrush(pass ? QColor(30, 142, 78, 18) : QColor(216, 14, 24, 18));
    p.drawRoundedRect(vb, 4, 4);
    font(13, true);
    p.setPen(pass ? QColor(QStringLiteral("#1E8E4E")) : brand);
    p.drawText(vb.adjusted(16, 8, -16, -38), Qt::AlignLeft | Qt::AlignVCenter, pass ? tr("자동 판정: 이격 기준 충족") : tr("자동 판정: 기준 미충족"));
    font(8.5);
    p.setPen(ink);
    const QStringList reasons = _verdict.value(QStringLiteral("reasons")).toStringList();
    p.drawText(vb.adjusted(16, 40, -16, -6), Qt::AlignLeft | Qt::AlignVCenter,
               reasons.isEmpty() ? tr("같은 층(고도차 %1 m 이내) 최소 수평 이격 %2 — 긴급 거리 %3 m 이상, 가드 내부 오류 없음. 시험 책임자 검토 필요.")
                                       .arg(_vSep, 0, 'f', 0).arg(m1(_verdict.value(QStringLiteral("minSame")))).arg(_dEmerg, 0, 'f', 1)
                                 : reasons.join(QStringLiteral(" · ")));
    y += 92;

    section(tr("시험 조건"));
    QList<QStringList> cond;
    cond << QStringList{tr("기록 파일"), QFileInfo(_info.value(QStringLiteral("logFile")).toString()).fileName()};
    cond << QStringList{tr("비행 시간"), fmtDur(duration())};
    const QVariantMap site = _info.value(QStringLiteral("site")).toMap();
    if (!site.isEmpty()) {
        cond << QStringList{tr("시연 구역 원점 · 방위"), QStringLiteral("%1, %2 · %3°").arg(site.value(QStringLiteral("lat")).toDouble(), 0, 'f', 6)
                                                       .arg(site.value(QStringLiteral("lon")).toDouble(), 0, 'f', 6).arg(site.value(QStringLiteral("bearing")).toDouble(), 0, 'f', 0)};
    }
    cond << QStringList{tr("판단 기준"), QStringLiteral("D_SAFE %1 m · D_EMERG %2 m · V_SEP %3 m").arg(_dSafe).arg(_dEmerg).arg(_vSep)};
    cond << QStringList{tr("프로그램"), QStringLiteral("MobilityLab GCS %1").arg(_info.value(QStringLiteral("app")).toString())};
    table({tr("항목"), tr("값")}, cond, {0.3, 0.7});

    section(tr("기체"));
    QList<QStringList> vr;
    for (const QVariant &v : _vehV) {
        const QVariantMap m = v.toMap();
        vr << QStringList{m.value(QStringLiteral("id")).toString(),
                          m.value(QStringLiteral("controlled")).toBool() ? tr("가드 제어") : tr("장애물로만"),
                          m.value(QStringLiteral("sim")).toInt() == 1 ? QStringLiteral("SITL") : (m.value(QStringLiteral("sim")).toInt() == 0 ? tr("실기체") : QStringLiteral("—")),
                          fmtDur(m.value(QStringLiteral("flightTime")).toDouble()),
                          QString::number(m.value(QStringLiteral("maxAlt")).toDouble(), 'f', 1) + QStringLiteral(" m"),
                          QString::number(m.value(QStringLiteral("takeovers")).toInt()),
                          QString::number(m.value(QStringLiteral("ownedTime")).toDouble(), 'f', 1) + QStringLiteral(" s"),
                          QString::number(m.value(QStringLiteral("maxLinkGap")).toDouble(), 'f', 1) + QStringLiteral(" s")};
    }
    table({tr("기체"), tr("역할"), tr("종류"), tr("비행"), tr("최고 고도"), tr("개입"), tr("개입 시간"), tr("최대 링크 공백")}, vr,
          {0.08, 0.13, 0.1, 0.1, 0.13, 0.08, 0.16, 0.22});

    section(tr("기체 간 이격"));
    QList<QStringList> pr;
    for (const QVariant &v : _pairsV) {
        const QVariantMap m = v.toMap();
        pr << QStringList{m.value(QStringLiteral("a")).toString() + QStringLiteral(" – ") + m.value(QStringLiteral("b")).toString(),
                          m1(m.value(QStringLiteral("minSame"))), m.value(QStringLiteral("tMin")).toDouble() >= 0 ? fmtDur(m.value(QStringLiteral("tMin")).toDouble()) : QStringLiteral("—"),
                          m1(m.value(QStringLiteral("min3d"))),
                          QString::number(m.value(QStringLiteral("belowSafe")).toDouble(), 'f', 1) + QStringLiteral(" s"),
                          QString::number(m.value(QStringLiteral("belowEmerg")).toDouble(), 'f', 1) + QStringLiteral(" s")};
    }
    table({tr("쌍"), tr("같은 층 최소"), tr("시각"), tr("3D 최소"), tr("D_SAFE 미만"), tr("D_EMERG 미만")}, pr, {0.14, 0.18, 0.12, 0.16, 0.2, 0.2});

    // ---- page 2: figures ----
    newPage();
    section(tr("비행 궤적 (위에서 본 모습, 시연 좌표계 · 빨강 = 가드가 비행한 구간)"));
    const double side = std::min(page.width(), page.height() * 0.42);
    _drawTracks(p, QRectF((page.width() - side) / 2, y, side, side));
    y += side + 10;
    section(tr("기체 간 거리 (같은 층이면 수평, 아니면 3D · 붉은 띠 = 가드 개입)"));
    _drawSeries(p, QRectF(0, y, page.width(), 150), false);
    y += 170;
    section(tr("고도"));
    _drawSeries(p, QRectF(0, y, page.width(), 120), true);
    y += 140;

    // ---- interventions + events ----
    section(tr("가드 개입 이력"));
    QList<QStringList> ir;
    for (const QVariant &v : _intV) {
        const QVariantMap m = v.toMap();
        ir << QStringList{m.value(QStringLiteral("id")).toString(), fmtDur(m.value(QStringLiteral("t0")).toDouble()),
                          QString::number(m.value(QStringLiteral("dur")).toDouble(), 'f', 1) + QStringLiteral(" s"),
                          m.value(QStringLiteral("other")).toString(), m1(m.value(QStringLiteral("nearest")))};
    }
    if (ir.isEmpty()) {
        ir << QStringList{QStringLiteral("—"), QString(), QString(), QString(), QString()};
    }
    table({tr("기체"), tr("시작"), tr("길이"), tr("상대 기체"), tr("개입 중 최근접 (3D)")}, ir, {0.12, 0.15, 0.15, 0.2, 0.38});

    section(tr("가드 이벤트"));
    QList<QStringList> er;
    for (const QVariant &v : _evV) {
        const QVariantMap m = v.toMap();
        er << QStringList{fmtDur(std::max(0.0, m.value(QStringLiteral("t")).toDouble())), m.value(QStringLiteral("who")).toString(), m.value(QStringLiteral("text")).toString()};
    }
    table({tr("시각"), tr("대상"), tr("내용")}, er, {0.1, 0.1, 0.8});

    need(90);
    y += 20;
    font(8.5);
    p.setPen(ink);
    p.drawText(QRectF(0, y, page.width() / 2, 18), Qt::AlignLeft, tr("시험 책임자:                         (서명)"));
    p.drawText(QRectF(page.width() / 2, y, page.width() / 2, 18), Qt::AlignLeft, tr("검토자:                         (서명)"));
    y += 30;
    font(7);
    p.setPen(sub);
    p.drawText(QRectF(0, y, page.width(), 30), Qt::AlignLeft | Qt::TextWordWrap,
               tr("이 보고서는 GCS 가드 기록(20 Hz)에서 자동으로 만들었습니다. 판정은 기록 기준이며, 실비행 적용 여부는 시험 책임자가 결정합니다."));
    p.end();
    return path;
}
