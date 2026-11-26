#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QtNumeric>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtNetwork/QHostAddress>

class QUdpSocket;

/// Link to the ACACT Guard (acact_guard/guard.py + gcs_link.py).
///
/// The guard runs the collision prediction and ACACT avoidance on the
/// operator laptop and sends its state as JSON over UDP (5 Hz, port 47001).
/// This class receives that state for the fly view (rings, pair distances,
/// who is avoiding) and sends the operator commands the guard accepts from a
/// GCS (h, r, g, g!, auto on|off) to its command port (47002).
/// The GCS never makes avoidance decisions itself.
class MLGuardLink : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool         active          READ active         NOTIFY activeChanged)
    Q_PROPERTY(bool         seen            READ seen           NOTIFY activeChanged)
    Q_PROPERTY(QString      guardHost       READ guardHost      NOTIFY activeChanged)
    Q_PROPERTY(int          listenPort      READ listenPort     CONSTANT)
    Q_PROPERTY(bool         listening       READ listening      CONSTANT)
    Q_PROPERTY(QVariantList drones          READ drones         NOTIFY updated)
    Q_PROPERTY(QVariantList pairs           READ pairs          NOTIFY updated)
    Q_PROPERTY(QVariantMap  site            READ site           NOTIFY updated)
    Q_PROPERTY(QVariantMap  config          READ config         NOTIFY updated)
    Q_PROPERTY(bool         autoMode        READ autoMode       NOTIFY updated)
    Q_PROPERTY(QString      scenario        READ scenario       NOTIFY updated)
    Q_PROPERTY(QString      scenarioMode    READ scenarioMode   NOTIFY updated)
    Q_PROPERTY(int          avoiding        READ avoiding       NOTIFY updated)
    Q_PROPERTY(double       closest         READ closest        NOTIFY updated)
    Q_PROPERTY(int          worstLevel      READ worstLevel     NOTIFY updated)
    Q_PROPERTY(double       guardTime       READ guardTime      NOTIFY updated)

public:
    explicit MLGuardLink(QObject *parent = nullptr);

    bool active() const { return _active; }
    bool seen() const { return _seen; }
    QString guardHost() const { return _guardHost.isNull() ? QString() : _guardHost.toString(); }
    int listenPort() const { return _listenPort; }
    bool listening() const { return _listening; }
    QVariantList drones() const { return _drones; }
    QVariantList pairs() const { return _pairs; }
    QVariantMap site() const { return _site; }
    QVariantMap config() const { return _config; }
    bool autoMode() const { return _autoMode; }
    QString scenario() const { return _scenario; }
    QString scenarioMode() const { return _scenarioMode; }
    int avoiding() const { return _avoiding; }
    double closest() const { return _closest; }
    int worstLevel() const { return _worstLevel; }
    double guardTime() const { return _guardTime; }

    /// Guard drone entry ("D1"…) for a MAVLink system id, or an empty map.
    Q_INVOKABLE QVariantMap droneForSysid(int sysid) const;

    /// Send one operator command: "h", "r", "g", "g!", "auto on", "auto off".
    /// Returns false when no guard is connected or the command is not allowed.
    Q_INVOKABLE bool sendCommand(const QString &command);

signals:
    void activeChanged();
    void updated();
    /// New guard event (Korean text as the guard logs it)
    void guardEvent(int seq, double time, const QString &who, const QString &text);

private slots:
    void _readPending();
    void _checkStale();

private:
    void _handle(const QByteArray &datagram, const QHostAddress &sender);
    void _setActive(bool active);

    QUdpSocket   *_socket = nullptr;
    QTimer        _staleTimer;
    QElapsedTimer _sinceLast;
    bool          _active = false;
    bool          _seen = false;
    bool          _listening = false;
    int           _listenPort = 47001;
    int           _commandPort = 47002;
    QHostAddress  _guardHost;
    int           _lastEventSeq = 0;
    double        _guardTime = 0;
    int           _commandId = 0;

    QVariantList  _drones;
    QVariantList  _pairs;
    QVariantMap   _site;
    QVariantMap   _config;
    bool          _autoMode = false;
    QString       _scenario;
    QString       _scenarioMode;
    int           _avoiding = 0;
    double        _closest = qQNaN();
    int           _worstLevel = 0;
};
