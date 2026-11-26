// MobilityLab GCS — post-flight analysis of ACACT guard logs: session list, replay,
// separation / altitude series, intervention history, link gaps, PDF test report.
//
// Reads what MLAcactRuntime writes to its log folder:
//   guard_<stamp>.csv           20 Hz state of every vehicle (demo frame F/R, altitude, mode, guard ownership, freshness)
//   guard_<stamp>_events.csv    guard events
//   guard_<stamp>_meta.json     site, vehicles, thresholds, plan, operating mode (written by this version and later)
#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtCore/QVector>

class QPainter;
class QRectF;

class MLFlightAnalysis : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList sessions   READ sessions   NOTIFY sessionsChanged)
    Q_PROPERTY(bool         loaded     READ loaded     NOTIFY loadedChanged)
    Q_PROPERTY(QString      stamp      READ stamp      NOTIFY loadedChanged)
    Q_PROPERTY(QVariantMap  info       READ info       NOTIFY loadedChanged)
    Q_PROPERTY(double       duration   READ duration   NOTIFY loadedChanged)
    Q_PROPERTY(QVariantList tracks     READ tracks     NOTIFY loadedChanged)   // per vehicle: id, sysid, points [[t,f,r,alt,own]]
    Q_PROPERTY(QVariantList pairs      READ pairs      NOTIFY loadedChanged)   // per pair: stats + series [[t,dh,dz]]
    Q_PROPERTY(QVariantList vehicles   READ vehicles   NOTIFY loadedChanged)   // per vehicle stats
    Q_PROPERTY(QVariantList interventions READ interventions NOTIFY loadedChanged)
    Q_PROPERTY(QVariantList events     READ events     NOTIFY loadedChanged)
    Q_PROPERTY(QVariantMap  verdict    READ verdict    NOTIFY loadedChanged)
    Q_PROPERTY(QVariantMap  extent     READ extent     NOTIFY loadedChanged)   // fMin fMax rMin rMax altMax

public:
    explicit MLFlightAnalysis(QObject *parent = nullptr);

    QVariantList sessions() const { return _sessions; }
    bool loaded() const { return !_t.isEmpty(); }
    QString stamp() const { return _stamp; }
    QVariantMap info() const { return _info; }
    double duration() const { return _t.isEmpty() ? 0.0 : _t.last() - _t.first(); }
    QVariantList tracks() const { return _tracksV; }
    QVariantList pairs() const { return _pairsV; }
    QVariantList vehicles() const { return _vehV; }
    QVariantList interventions() const { return _intV; }
    QVariantList events() const { return _evV; }
    QVariantMap verdict() const { return _verdict; }
    QVariantMap extent() const { return _extent; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool load(const QString &stamp);
    /// replay: every vehicle at time t (from the start of the log)
    Q_INVOKABLE QVariantList stateAt(double t) const;
    /// A4 PDF test report; returns the written path (empty on failure)
    Q_INVOKABLE QString exportPdf(const QString &path);
    Q_INVOKABLE QString defaultReportPath() const;
    Q_INVOKABLE QString logDir() const;

    /// for the regression test (no GUI): load a log folder other than the runtime's
    void setLogDir(const QString &d) { _dirOverride = d; }

signals:
    void sessionsChanged();
    void loadedChanged();

private:
    struct Track {
        QString id;
        int sysid = 0;
        bool controlled = true;
        int sim = -1;
        QVector<float> f, r, alt;
        QVector<quint8> own, fresh;
        QVector<QString> mode;
    };
    int _row(double t) const;
    void _compute();
    void _drawTracks(QPainter &p, const QRectF &rc) const;
    void _drawSeries(QPainter &p, const QRectF &rc, bool altitude) const;

    QString _dirOverride;
    QVariantList _sessions;
    QString _stamp;
    QVariantMap _info;
    QVector<double> _t;
    QVector<Track> _tr;
    double _dSafe = 10, _dEmerg = 5.5, _vSep = 4;
    QVariantList _tracksV, _pairsV, _vehV, _intV, _evV;
    QVariantMap _verdict, _extent;
};
