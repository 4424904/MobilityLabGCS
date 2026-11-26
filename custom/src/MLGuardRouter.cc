#include "MLGuardRouter.h"

#include "LinkInterface.h"
#include "LinkManager.h"
#include "MultiVehicleManager.h"
#include "QmlObjectListModel.h"
#include "Vehicle.h"
#include "VehicleLinkManager.h"

#include <QtCore/QLoggingCategory>
#include <QtNetwork/QUdpSocket>

Q_LOGGING_CATEGORY(MLGuardRouterLog, "MobilityLab.GuardRouter")

MLGuardRouter::MLGuardRouter(QObject *parent)
    : QObject(parent)
{
    bool ok = false;
    const int base = qEnvironmentVariableIntValue("ML_GUARD_UDP_BASE", &ok);
    if (ok && base > 1000 && base < 65000) {
        _basePort = base;
    }
}

MLGuardRouter::~MLGuardRouter()
{
    setEnabled(false);
}

void MLGuardRouter::setEnabled(bool enabled)
{
    if (enabled == _enabled) {
        return;
    }
    _enabled = enabled;
    MultiVehicleManager *mvm = MultiVehicleManager::instance();
    if (enabled) {
        connect(mvm, &MultiVehicleManager::vehicleAdded, this, &MLGuardRouter::_vehicleAdded);
        connect(mvm, &MultiVehicleManager::vehicleRemoved, this, &MLGuardRouter::_vehicleRemoved);
        QmlObjectListModel *vehicles = mvm->vehicles();
        for (int i = 0; i < vehicles->count(); i++) {
            _open(vehicles->value<Vehicle*>(i));
        }
        qCInfo(MLGuardRouterLog) << "Guard routing on," << _bridges.size() << "vehicle(s)";
    } else {
        disconnect(mvm, nullptr, this, nullptr);
        const QList<int> ids = _bridges.keys();
        for (int id : ids) {
            _close(id);
        }
        qCInfo(MLGuardRouterLog) << "Guard routing off";
    }
    emit bridgesChanged();
}

void MLGuardRouter::_vehicleAdded(Vehicle *vehicle)
{
    _open(vehicle);
    emit bridgesChanged();
}

void MLGuardRouter::_vehicleRemoved(Vehicle *vehicle)
{
    if (vehicle) {
        _close(vehicle->id());
        emit bridgesChanged();
    }
}

void MLGuardRouter::_open(Vehicle *vehicle)
{
    if (!vehicle) {
        return;
    }
    const int id = vehicle->id();
    if (id < 1 || id > 4 || _bridges.contains(id)) {
        return;
    }

    Bridge *b = new Bridge;
    b->vehicle = vehicle;
    b->port = static_cast<quint16>(_basePort + id);
    b->channel = LinkManager::instance()->allocateMavlinkChannel();
    if (b->channel == LinkManager::invalidMavlinkChannel()) {
        qCWarning(MLGuardRouterLog) << "No free MAVLink channel for guard bridge, vehicle" << id;
        delete b;
        return;
    }
    b->socket = new QUdpSocket(this);
    if (!b->socket->bind(QHostAddress::LocalHost, 0)) {
        qCWarning(MLGuardRouterLog) << "Guard bridge bind failed" << b->socket->errorString();
    }
    connect(b->socket, &QUdpSocket::readyRead, this, [this, b]() { _readGuard(b); });

    b->fromVehicle = connect(vehicle, &Vehicle::mavlinkMessageReceived, this, [b](const mavlink_message_t &message) {
        uint8_t buffer[MAVLINK_MAX_PACKET_LEN];
        const uint16_t len = mavlink_msg_to_send_buffer(buffer, &message);
        b->socket->writeDatagram(reinterpret_cast<const char *>(buffer), len, QHostAddress::LocalHost, b->port);
        b->toGuard++;
    });

    _bridges.insert(id, b);
    qCInfo(MLGuardRouterLog) << "Vehicle" << id << "<-> guard udp" << b->port;
}

void MLGuardRouter::_close(int id)
{
    Bridge *b = _bridges.take(id);
    if (!b) {
        return;
    }
    disconnect(b->fromVehicle);
    b->socket->deleteLater();
    LinkManager::instance()->freeMavlinkChannel(b->channel);
    qCInfo(MLGuardRouterLog) << "Vehicle" << id << "bridge closed, to guard" << b->toGuard << "to vehicle" << b->toVehicle;
    delete b;
}

void MLGuardRouter::_readGuard(Bridge *b)
{
    while (b->socket->hasPendingDatagrams()) {
        QByteArray data;
        data.resize(static_cast<int>(b->socket->pendingDatagramSize()));
        b->socket->readDatagram(data.data(), data.size());
        if (!b->vehicle) {
            continue;
        }
        SharedLinkInterfacePtr link = b->vehicle->vehicleLinkManager()->primaryLink().lock();
        if (!link) {
            continue;
        }
        mavlink_message_t message;
        mavlink_status_t status;
        for (const char c : std::as_const(data)) {
            if (mavlink_parse_char(b->channel, static_cast<uint8_t>(c), &message, &status) == MAVLINK_FRAMING_OK) {
                b->vehicle->sendMessageOnLinkThreadSafe(link.get(), message);
                b->toVehicle++;
            }
        }
    }
}
