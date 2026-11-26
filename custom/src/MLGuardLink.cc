#include "MLGuardLink.h"

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLoggingCategory>
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
    if (o.value(QStringLiteral("src")).toString() != QStringLiteral("acact_guard")) {
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
