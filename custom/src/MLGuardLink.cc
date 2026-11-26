#include "MLGuardLink.h"

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLoggingCategory>
#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtCore/QProcess>
#include <QtCore/QSettings>
#include <QtCore/QStandardPaths>
#include <QtNetwork/QNetworkDatagram>
#include <QtNetwork/QUdpSocket>

#include <cmath>

Q_LOGGING_CATEGORY(MLGuardLinkLog, "MobilityLab.GuardLink")

namespace {
int envPort(const char *name, int fallback)
{
    bool ok = false;
    const int v = qEnvironmentVariableIntValue(name, &ok);
    return (ok && v > 0 && v < 65536) ? v : fallback;
}
}

MLGuardLink::MLGuardLink(QObject *parent)
    : QObject(parent)
    , _socket(new QUdpSocket(this))
{
    _listenPort  = envPort("ML_GUARD_PORT", 47001);
    _commandPort = envPort("ML_GUARD_CMD_PORT", 47002);

    _listening = _socket->bind(QHostAddress::AnyIPv4, static_cast<quint16>(_listenPort),
                               QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);
    if (_listening) {
        connect(_socket, &QUdpSocket::readyRead, this, &MLGuardLink::_readPending);
    } else {
        qCWarning(MLGuardLinkLog) << "Cannot listen for ACACT Guard on UDP" << _listenPort << _socket->errorString();
    }

    _agentPort = envPort("ML_GUARD_AGENT_PORT", 47003);
    QSettings settings;
    settings.beginGroup(QStringLiteral("MobilityLab/Guard"));
    _autoStart    = settings.value(QStringLiteral("autoStart"), true).toBool();
    _profile      = settings.value(QStringLiteral("profile"), QStringLiteral("hwaseong")).toString();
    _bearing      = settings.value(QStringLiteral("bearing"), 0.0).toDouble();
    _agentAddress = settings.value(QStringLiteral("agentAddress"), QString()).toString();
    settings.endGroup();

    _agentTimer.setInterval(1500);
    connect(&_agentTimer, &QTimer::timeout, this, &MLGuardLink::_agentTick);
    if (_listening) {
        _agentTimer.start();
        QTimer::singleShot(300, this, &MLGuardLink::_agentTick);
    }

    _staleTimer.setInterval(500);
    connect(&_staleTimer, &QTimer::timeout, this, &MLGuardLink::_checkStale);
    _staleTimer.start();
}

void MLGuardLink::_readPending()
{
    while (_socket->hasPendingDatagrams()) {
        const QNetworkDatagram dg = _socket->receiveDatagram();
        if (dg.isValid()) {
            _handle(dg.data(), dg.senderAddress());
        }
    }
}

void MLGuardLink::_checkStale()
{
    if (_agentFound && _agentSince.isValid() && _agentSince.elapsed() > 4000) {
        _agentFound = false;
        _agentState.clear();
        emit agentChanged();
    }
    if (_active && _sinceLast.isValid() && _sinceLast.elapsed() > 2000) {
        _setActive(false);
    }
}

void MLGuardLink::_setActive(bool active)
{
    if (_active != active) {
        _active = active;
        if (active) {
            _seen = true;
        }
        emit activeChanged();
    }
}

void MLGuardLink::_handle(const QByteArray &datagram, const QHostAddress &sender)
{
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(datagram, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        return;
    }
    const QJsonObject o = doc.object();
    const QString src = o.value(QStringLiteral("src")).toString();
    if (src == QStringLiteral("acact_agent")) {
        _handleAgent(o, sender);
        return;
    }
    if (src != QStringLiteral("acact_guard")) {
        return;
    }

    if (_guardHost != sender) {
        _guardHost = sender;
        emit activeChanged();
    }
    _sinceLast.restart();
    _setActive(true);

    _guardTime = o.value(QStringLiteral("t")).toDouble();
    _drones    = o.value(QStringLiteral("drones")).toArray().toVariantList();
    _pairs     = o.value(QStringLiteral("pairs")).toArray().toVariantList();
    _site      = o.value(QStringLiteral("site")).toObject().toVariantMap();
    _config    = o.value(QStringLiteral("cfg")).toObject().toVariantMap();
    _autoMode  = o.value(QStringLiteral("auto")).toBool();

    const QJsonArray loaded = o.value(QStringLiteral("loaded")).toArray();
    _scenario     = loaded.size() > 0 ? loaded.at(0).toString() : QString();
    _scenarioMode = loaded.size() > 1 ? loaded.at(1).toString() : QString();

    _avoiding = 0;
    for (const QVariant &d : std::as_const(_drones)) {
        if (d.toMap().value(QStringLiteral("own")).toBool()) {
            _avoiding++;
        }
    }
    _closest = qQNaN();
    _worstLevel = 0;
    for (const QVariant &p : std::as_const(_pairs)) {
        const QVariantMap m = p.toMap();
        const double d = m.value(QStringLiteral("d")).toDouble();
        const double dz = m.value(QStringLiteral("dz")).toDouble();
        const double sep = std::hypot(d, dz);
        if (std::isnan(_closest) || sep < _closest) {
            _closest = sep;
        }
        _worstLevel = qMax(_worstLevel, m.value(QStringLiteral("level")).toInt());
    }

    const QJsonArray events = o.value(QStringLiteral("events")).toArray();
    for (const QJsonValue &ev : events) {
        const QJsonObject e = ev.toObject();
        const int seq = e.value(QStringLiteral("n")).toInt();
        if (seq > _lastEventSeq) {
            _lastEventSeq = seq;
            emit guardEvent(seq, e.value(QStringLiteral("t")).toDouble(),
                            e.value(QStringLiteral("who")).toString(), e.value(QStringLiteral("text")).toString());
        }
    }
    // Guard restarted: its event numbering starts again
    if (!events.isEmpty() && events.last().toObject().value(QStringLiteral("n")).toInt() < _lastEventSeq - 100) {
        _lastEventSeq = 0;
    }

    emit updated();
}

QVariantMap MLGuardLink::droneForSysid(int sysid) const
{
    for (const QVariant &d : _drones) {
        const QVariantMap m = d.toMap();
        if (m.value(QStringLiteral("sysid")).toInt() == sysid) {
            return m;
        }
    }
    return {};
}

bool MLGuardLink::sendCommand(const QString &command)
{
    static const QStringList allowed = { QStringLiteral("h"), QStringLiteral("r"), QStringLiteral("g"),
                                         QStringLiteral("g!"), QStringLiteral("auto on"), QStringLiteral("auto off") };
    const QString cmd = command.trimmed().toLower();
    if (!allowed.contains(cmd) || !_active || _guardHost.isNull()) {
        return false;
    }
    QJsonObject o;
    o.insert(QStringLiteral("cmd"), cmd);
    o.insert(QStringLiteral("id"), ++_commandId);
    o.insert(QStringLiteral("from"), QStringLiteral("MobilityLabGCS"));
    const QByteArray data = QJsonDocument(o).toJson(QJsonDocument::Compact);
    // Sent once: "g" is not idempotent (a second one could start the next leg).
    // The guard logs every command it accepts; that event confirms delivery.
    const bool ok = _socket->writeDatagram(data, _guardHost, static_cast<quint16>(_commandPort)) == data.size();
    qCInfo(MLGuardLinkLog) << "Guard command" << cmd << (ok ? "sent" : "failed");
    return ok;
}

/*---------------------------------------------------------------------------*/
/* Guard agent                                                                */
/*---------------------------------------------------------------------------*/

void MLGuardLink::_agentTick()
{
    QJsonObject hello;
    hello.insert(QStringLiteral("op"), QStringLiteral("hello"));
    const QByteArray data = QJsonDocument(hello).toJson(QJsonDocument::Compact);
    const quint16 port = static_cast<quint16>(_agentPort);
    if (_agentFound) {
        _socket->writeDatagram(data, _agentHost, port);    // keep-alive: the agent sends to who said hello
        return;
    }
    // look for an agent: this PC, the configured address, and the local network
    _socket->writeDatagram(data, QHostAddress::LocalHost, port);
    if (!_agentAddress.isEmpty()) {
        const QHostAddress configured(_agentAddress);
        if (!configured.isNull()) {
            _socket->writeDatagram(data, configured, port);
        }
    }
    _socket->writeDatagram(data, QHostAddress::Broadcast, port);
}

void MLGuardLink::_handleAgent(const QJsonObject &o, const QHostAddress &sender)
{
    _agentSince.restart();
    bool changed = false;
    if (!_agentFound || _agentHost != sender) {
        _agentFound = true;
        _agentHost = sender;
        changed = true;
    }
    const QString state = o.value(QStringLiteral("state")).toString();
    const QString dir = o.value(QStringLiteral("dir")).toString();
    QStringList args;
    for (const QJsonValue &a : o.value(QStringLiteral("args")).toArray()) {
        args.append(a.toString());
    }
    const QVariantList scen = o.value(QStringLiteral("scenarios")).toArray().toVariantList();
    QStringList profiles;
    for (const QJsonValue &p : o.value(QStringLiteral("profiles")).toArray()) {
        profiles.append(p.toString());
    }
    if (state != _agentState || dir != _agentDir || args != _agentArgs || scen != _scenarios || profiles != _profiles) {
        _agentState = state;
        _agentDir = dir;
        _agentArgs = args;
        _scenarios = scen;
        _profiles = profiles;
        changed = true;
    }
    _agentUptime = o.value(QStringLiteral("uptime")).toDouble();
    if (changed) {
        emit agentChanged();
    }

    bool consoleGrew = false;
    const QJsonArray lines = o.value(QStringLiteral("lines")).toArray();
    if (!lines.isEmpty() && lines.last().toObject().value(QStringLiteral("n")).toInt() < _consoleSeq) {
        _consoleSeq = 0;    // agent restarted
    }
    for (const QJsonValue &v : lines) {
        const QJsonObject l = v.toObject();
        const int n = l.value(QStringLiteral("n")).toInt();
        if (n > _consoleSeq) {
            _consoleSeq = n;
            _console.append(l.value(QStringLiteral("text")).toString());
            consoleGrew = true;
        }
    }
    if (consoleGrew) {
        while (_console.size() > 500) {
            _console.removeFirst();
        }
        emit consoleChanged();
    }
}

bool MLGuardLink::_toAgent(const QJsonObject &o)
{
    if (!_agentFound || _agentHost.isNull()) {
        return false;
    }
    const QByteArray data = QJsonDocument(o).toJson(QJsonDocument::Compact);
    return _socket->writeDatagram(data, _agentHost, static_cast<quint16>(_agentPort)) == data.size();
}

bool MLGuardLink::startGuard(const QString &drones)
{
    QJsonObject o;
    o.insert(QStringLiteral("op"), QStringLiteral("start"));
    o.insert(QStringLiteral("drones"), drones);
    o.insert(QStringLiteral("profile"), _profile);
    return _toAgent(o);
}

bool MLGuardLink::stopGuard(bool force)
{
    QJsonObject o;
    o.insert(QStringLiteral("op"), QStringLiteral("stop"));
    o.insert(QStringLiteral("force"), force);
    return _toAgent(o);
}

bool MLGuardLink::sendLine(const QString &line)
{
    const QString l = line.simplified();
    if (l.isEmpty()) {
        return false;
    }
    if (_agentFound && _agentState == QStringLiteral("guard")) {
        QJsonObject o;
        o.insert(QStringLiteral("op"), QStringLiteral("line"));
        o.insert(QStringLiteral("line"), l);
        return _toAgent(o);
    }
    // No agent holding the guard: the guard's own GCS command port (h, r, g, g!, auto)
    return sendCommand(l);
}

bool MLGuardLink::runPlan(const QString &drones)
{
    QJsonObject o;
    o.insert(QStringLiteral("op"), QStringLiteral("plan"));
    o.insert(QStringLiteral("drones"), drones);
    o.insert(QStringLiteral("profile"), _profile);
    o.insert(QStringLiteral("bearing"), _bearing);
    return _toAgent(o);
}

bool MLGuardLink::runParams(const QString &drones, bool apply)
{
    QJsonObject o;
    o.insert(QStringLiteral("op"), QStringLiteral("params"));
    o.insert(QStringLiteral("drones"), drones);
    o.insert(QStringLiteral("apply"), apply);
    return _toAgent(o);
}

QString MLGuardLink::_guardDir() const
{
    const QString env = qEnvironmentVariable("ACACT_GUARD_DIR");
    if (!env.isEmpty()) {
        return env;
    }
    return QDir::home().filePath(QStringLiteral("acact_guard"));
}

bool MLGuardLink::canLaunchLocal() const
{
#if defined(Q_OS_LINUX)
    return QFileInfo::exists(QDir(_guardDir()).filePath(QStringLiteral("guard_agent.py")));
#else
    return false;
#endif
}

bool MLGuardLink::launchLocalAgent()
{
    if (_agentFound || !canLaunchLocal()) {
        return false;
    }
    const QString dir = _guardDir();
    QString python = QDir::home().filePath(QStringLiteral("acact-venv/bin/python"));
    if (!QFileInfo::exists(python)) {
        python = QStandardPaths::findExecutable(QStringLiteral("python3"));
    }
    if (python.isEmpty()) {
        return false;
    }
    // Detached: the agent (and the guard it holds) keeps running if the GCS closes
    const bool ok = QProcess::startDetached(python, { QStringLiteral("-u"), QDir(dir).filePath(QStringLiteral("guard_agent.py")) }, dir);
    qCInfo(MLGuardLinkLog) << "Launch local guard agent" << dir << ok;
    QTimer::singleShot(800, this, &MLGuardLink::_agentTick);
    return ok;
}

void MLGuardLink::clearConsole()
{
    _console.clear();
    emit consoleChanged();
}

void MLGuardLink::setAutoStart(bool v)
{
    if (v != _autoStart) {
        _autoStart = v;
        QSettings().setValue(QStringLiteral("MobilityLab/Guard/autoStart"), v);
        emit settingsChanged();
    }
}

void MLGuardLink::setProfile(const QString &v)
{
    if (v != _profile) {
        _profile = v;
        QSettings().setValue(QStringLiteral("MobilityLab/Guard/profile"), v);
        emit settingsChanged();
    }
}

void MLGuardLink::setBearing(double v)
{
    if (!qFuzzyCompare(v + 1000.0, _bearing + 1000.0)) {
        _bearing = v;
        QSettings().setValue(QStringLiteral("MobilityLab/Guard/bearing"), v);
        emit settingsChanged();
    }
}

void MLGuardLink::setAgentAddress(const QString &v)
{
    if (v != _agentAddress) {
        _agentAddress = v.trimmed();
        QSettings().setValue(QStringLiteral("MobilityLab/Guard/agentAddress"), _agentAddress);
        emit settingsChanged();
        _agentTick();
    }
}
