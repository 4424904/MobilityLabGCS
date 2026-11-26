#pragma once

#include <QtCore/QHash>
#include <QtCore/QObject>
#include <QtCore/QPointer>

#include "MAVLinkLib.h"

class QUdpSocket;
class Vehicle;

/// Connects the ACACT Guard's mavsdk_server instances to the vehicles the GCS
/// already talks to, so the guard needs no mavlink-router (and runs on Windows).
///
/// For vehicle n (MAVLink system id 1…4) every message received from it is
/// sent to 127.0.0.1:(basePort + n) — where the guard's mavsdk_server for Dn
/// listens (config.py: udp 14541…14544) — and every message that server sends
/// back (heartbeats, offboard setpoints, commands, mission upload) goes out on
/// that vehicle's primary link unchanged.
class MLGuardRouter : public QObject
{
    Q_OBJECT
public:
    explicit MLGuardRouter(QObject *parent = nullptr);
    ~MLGuardRouter() override;

    void setEnabled(bool enabled);
    bool enabled() const { return _enabled; }
    int bridgeCount() const { return _bridges.size(); }

signals:
    void bridgesChanged();

private slots:
    void _vehicleAdded(Vehicle *vehicle);
    void _vehicleRemoved(Vehicle *vehicle);

private:
    struct Bridge {
        QPointer<Vehicle>       vehicle;
        QUdpSocket             *socket = nullptr;
        uint8_t                 channel = 0;
        quint16                 port = 0;
        QMetaObject::Connection fromVehicle;
        quint64                 toGuard = 0;
        quint64                 toVehicle = 0;
    };

    void _open(Vehicle *vehicle);
    void _close(int id);
    void _readGuard(Bridge *b);

    bool                _enabled = false;
    int                 _basePort = 14540;
    QHash<int, Bridge*> _bridges;
};
