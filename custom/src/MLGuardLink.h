#pragma once

#include <QtCore/QElapsedTimer>
#include <QtCore/QtNumeric>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtNetwork/QHostAddress>

class QUdpSocket;
class QProcess;
class MLGuardRouter;
class QJsonObject;

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

    // ---- guard agent (guard_agent.py): start/stop the guard and type into it
    Q_PROPERTY(bool         agentFound      READ agentFound     NOTIFY agentChanged)
    Q_PROPERTY(QString      agentHost       READ agentHost      NOTIFY agentChanged)
    Q_PROPERTY(QString      agentState      READ agentState     NOTIFY agentChanged)
    Q_PROPERTY(QString      agentDir        READ agentDir       NOTIFY agentChanged)
    Q_PROPERTY(QStringList  agentArgs       READ agentArgs      NOTIFY agentChanged)
    Q_PROPERTY(double       agentUptime     READ agentUptime    NOTIFY agentChanged)
    Q_PROPERTY(QVariantList scenarios       READ scenarios      NOTIFY agentChanged)
    Q_PROPERTY(QStringList  profiles        READ profiles       NOTIFY agentChanged)
    Q_PROPERTY(QStringList  console         READ console        NOTIFY consoleChanged)
    Q_PROPERTY(bool         autoStart       READ autoStart      WRITE setAutoStart  NOTIFY settingsChanged)
    Q_PROPERTY(QString      profile         READ profile        WRITE setProfile    NOTIFY settingsChanged)
    Q_PROPERTY(double       bearing         READ bearing        WRITE setBearing    NOTIFY settingsChanged)
    Q_PROPERTY(QString      agentAddress    READ agentAddress   WRITE setAgentAddress NOTIFY settingsChanged)
    Q_PROPERTY(bool         canLaunchLocal  READ canLaunchLocal CONSTANT)
    // ---- guard run by the GCS itself (bundled Python on Windows) ----------
    Q_PROPERTY(bool         local           READ local          CONSTANT)
    Q_PROPERTY(QString      localDir        READ localDir       CONSTANT)
    Q_PROPERTY(QString      localPython     READ localPython    CONSTANT)
    Q_PROPERTY(bool         routeVehicles   READ routeVehicles  WRITE setRouteVehicles NOTIFY settingsChanged)
    Q_PROPERTY(int          routedVehicles  READ routedVehicles NOTIFY agentChanged)

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

    bool agentFound() const { return _agentFound; }
    QString agentHost() const { return local() ? QStringLiteral("이 PC") : (_agentHost.isNull() ? QString() : _agentHost.toString()); }
    QString agentState() const { return _agentState; }
    QString agentDir() const { return _agentDir; }
    QStringList agentArgs() const { return _agentArgs; }
    double agentUptime() const { return _agentUptime; }
    QVariantList scenarios() const { return _scenarios; }
    QStringList profiles() const { return _profiles; }
    QStringList console() const { return _console; }
    bool autoStart() const { return _autoStart; }
    void setAutoStart(bool v);
    QString profile() const { return _profile; }
    void setProfile(const QString &v);
    double bearing() const { return _bearing; }
    void setBearing(double v);
    QString agentAddress() const { return _agentAddress; }
    void setAgentAddress(const QString &v);
    bool canLaunchLocal() const;
    bool local() const { return !_localPython.isEmpty() && !_localDir.isEmpty(); }
    QString localDir() const { return _localDir; }
    QString localPython() const { return _localPython; }
    bool routeVehicles() const { return _routeVehicles; }
    void setRouteVehicles(bool v);
    int routedVehicles() const;
    /// Open the guard's working folder (plans, logs, site.json)
    Q_INVOKABLE void openFolder();

    /// Start the guard through the agent, e.g. drones "D1,D2" (profile from settings)
    Q_INVOKABLE bool startGuard(const QString &drones);
    /// Stop the guard ("q": it holds any drone it is flying, then exits); force = SIGINT
    Q_INVOKABLE bool stopGuard(bool force = false);
    /// Type one line into the guard terminal (load, start, g, g!, h, r, auto on|off, s)
    Q_INVOKABLE bool sendLine(const QString &line);
    /// plan_gen.py --from-vehicles with the profile and bearing from settings
    Q_INVOKABLE bool runPlan(const QString &drones);
    /// set_params.py (check only, or apply)
    Q_INVOKABLE bool runParams(const QString &drones, bool apply);
    /// Linux: start guard_agent.py from ~/acact_guard when no agent answers
    Q_INVOKABLE bool launchLocalAgent();
    Q_INVOKABLE void clearConsole();

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
    void agentChanged();
    void consoleChanged();
    void settingsChanged();

private slots:
    void _readPending();
    void _checkStale();

private:
    void _handle(const QByteArray &datagram, const QHostAddress &sender);
    void _handleAgent(const QJsonObject &o, const QHostAddress &sender);
    void _agentTick();
    bool _toAgent(const QJsonObject &o);
    QString _guardDir() const;
    void _findLocal();
    bool _startLocal(const QString &kind, const QStringList &args, const QString &drones, const QString &profile);
    void _localOutput();
    void _localFinished();
    void _appendConsole(const QString &line);
    void _updateRouting();
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

    // agent
    QTimer        _agentTimer;
    QElapsedTimer _agentSince;
    bool          _agentFound = false;
    QHostAddress  _agentHost;
    QString       _agentState;
    QString       _agentDir;
    QStringList   _agentArgs;
    double        _agentUptime = 0;
    QVariantList  _scenarios;
    QStringList   _profiles;
    QStringList   _console;
    int           _consoleSeq = 0;
    int           _agentPort = 47003;
    bool          _autoStart = true;
    QString       _profile;
    double        _bearing = 0;
    QString       _agentAddress;

    // local runner
    QString        _localDir;
    QString        _localPython;
    QProcess      *_proc = nullptr;
    QString        _procKind;
    QStringList    _procArgs;
    QElapsedTimer  _procSince;
    QByteArray     _procBuf;
    MLGuardRouter *_router = nullptr;
    bool           _routeVehicles = true;

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
