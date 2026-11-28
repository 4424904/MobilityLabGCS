/****************************************************************************
** Meta object code from reading C++ file 'MLFlightAnalysis.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.11.1)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../MobilityLabGCS/MobilityLabGCS/mlgcs/custom/src/MLFlightAnalysis.h"
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'MLFlightAnalysis.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.11.1. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN16MLFlightAnalysisE_t {};
} // unnamed namespace

template <> constexpr inline auto MLFlightAnalysis::qt_create_metaobjectdata<qt_meta_tag_ZN16MLFlightAnalysisE_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "MLFlightAnalysis",
        "sessionsChanged",
        "",
        "loadedChanged",
        "refresh",
        "load",
        "stamp",
        "stateAt",
        "QVariantList",
        "t",
        "exportPdf",
        "path",
        "defaultReportPath",
        "logDir",
        "sessions",
        "loaded",
        "info",
        "QVariantMap",
        "duration",
        "tracks",
        "pairs",
        "vehicles",
        "interventions",
        "events",
        "verdict",
        "extent"
    };

    QtMocHelpers::UintData qt_methods {
        // Signal 'sessionsChanged'
        QtMocHelpers::SignalData<void()>(1, 2, QMC::AccessPublic, QMetaType::Void),
        // Signal 'loadedChanged'
        QtMocHelpers::SignalData<void()>(3, 2, QMC::AccessPublic, QMetaType::Void),
        // Method 'refresh'
        QtMocHelpers::MethodData<void()>(4, 2, QMC::AccessPublic, QMetaType::Void),
        // Method 'load'
        QtMocHelpers::MethodData<bool(const QString &)>(5, 2, QMC::AccessPublic, QMetaType::Bool, {{
            { QMetaType::QString, 6 },
        }}),
        // Method 'stateAt'
        QtMocHelpers::MethodData<QVariantList(double) const>(7, 2, QMC::AccessPublic, 0x80000000 | 8, {{
            { QMetaType::Double, 9 },
        }}),
        // Method 'exportPdf'
        QtMocHelpers::MethodData<QString(const QString &)>(10, 2, QMC::AccessPublic, QMetaType::QString, {{
            { QMetaType::QString, 11 },
        }}),
        // Method 'defaultReportPath'
        QtMocHelpers::MethodData<QString() const>(12, 2, QMC::AccessPublic, QMetaType::QString),
        // Method 'logDir'
        QtMocHelpers::MethodData<QString() const>(13, 2, QMC::AccessPublic, QMetaType::QString),
    };
    QtMocHelpers::UintData qt_properties {
        // property 'sessions'
        QtMocHelpers::PropertyData<QVariantList>(14, 0x80000000 | 8, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 0),
        // property 'loaded'
        QtMocHelpers::PropertyData<bool>(15, QMetaType::Bool, QMC::DefaultPropertyFlags, 1),
        // property 'stamp'
        QtMocHelpers::PropertyData<QString>(6, QMetaType::QString, QMC::DefaultPropertyFlags, 1),
        // property 'info'
        QtMocHelpers::PropertyData<QVariantMap>(16, 0x80000000 | 17, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'duration'
        QtMocHelpers::PropertyData<double>(18, QMetaType::Double, QMC::DefaultPropertyFlags, 1),
        // property 'tracks'
        QtMocHelpers::PropertyData<QVariantList>(19, 0x80000000 | 8, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'pairs'
        QtMocHelpers::PropertyData<QVariantList>(20, 0x80000000 | 8, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'vehicles'
        QtMocHelpers::PropertyData<QVariantList>(21, 0x80000000 | 8, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'interventions'
        QtMocHelpers::PropertyData<QVariantList>(22, 0x80000000 | 8, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'events'
        QtMocHelpers::PropertyData<QVariantList>(23, 0x80000000 | 8, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'verdict'
        QtMocHelpers::PropertyData<QVariantMap>(24, 0x80000000 | 17, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
        // property 'extent'
        QtMocHelpers::PropertyData<QVariantMap>(25, 0x80000000 | 17, QMC::DefaultPropertyFlags | QMC::EnumOrFlag, 1),
    };
    QtMocHelpers::UintData qt_enums {
    };
    return QtMocHelpers::metaObjectData<MLFlightAnalysis, qt_meta_tag_ZN16MLFlightAnalysisE_t>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums);
}
Q_CONSTINIT const QMetaObject MLFlightAnalysis::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN16MLFlightAnalysisE_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN16MLFlightAnalysisE_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN16MLFlightAnalysisE_t>.metaTypes,
    nullptr
} };

void MLFlightAnalysis::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<MLFlightAnalysis *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->sessionsChanged(); break;
        case 1: _t->loadedChanged(); break;
        case 2: _t->refresh(); break;
        case 3: { bool _r = _t->load((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<bool*>(_a[0]) = std::move(_r); }  break;
        case 4: { QVariantList _r = _t->stateAt((*reinterpret_cast<std::add_pointer_t<double>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QVariantList*>(_a[0]) = std::move(_r); }  break;
        case 5: { QString _r = _t->exportPdf((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])));
            if (_a[0]) *reinterpret_cast<QString*>(_a[0]) = std::move(_r); }  break;
        case 6: { QString _r = _t->defaultReportPath();
            if (_a[0]) *reinterpret_cast<QString*>(_a[0]) = std::move(_r); }  break;
        case 7: { QString _r = _t->logDir();
            if (_a[0]) *reinterpret_cast<QString*>(_a[0]) = std::move(_r); }  break;
        default: ;
        }
    }
    if (_c == QMetaObject::IndexOfMethod) {
        if (QtMocHelpers::indexOfMethod<void (MLFlightAnalysis::*)()>(_a, &MLFlightAnalysis::sessionsChanged, 0))
            return;
        if (QtMocHelpers::indexOfMethod<void (MLFlightAnalysis::*)()>(_a, &MLFlightAnalysis::loadedChanged, 1))
            return;
    }
    if (_c == QMetaObject::ReadProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast<QVariantList*>(_v) = _t->sessions(); break;
        case 1: *reinterpret_cast<bool*>(_v) = _t->loaded(); break;
        case 2: *reinterpret_cast<QString*>(_v) = _t->stamp(); break;
        case 3: *reinterpret_cast<QVariantMap*>(_v) = _t->info(); break;
        case 4: *reinterpret_cast<double*>(_v) = _t->duration(); break;
        case 5: *reinterpret_cast<QVariantList*>(_v) = _t->tracks(); break;
        case 6: *reinterpret_cast<QVariantList*>(_v) = _t->pairs(); break;
        case 7: *reinterpret_cast<QVariantList*>(_v) = _t->vehicles(); break;
        case 8: *reinterpret_cast<QVariantList*>(_v) = _t->interventions(); break;
        case 9: *reinterpret_cast<QVariantList*>(_v) = _t->events(); break;
        case 10: *reinterpret_cast<QVariantMap*>(_v) = _t->verdict(); break;
        case 11: *reinterpret_cast<QVariantMap*>(_v) = _t->extent(); break;
        default: break;
        }
    }
}

const QMetaObject *MLFlightAnalysis::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *MLFlightAnalysis::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN16MLFlightAnalysisE_t>.strings))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int MLFlightAnalysis::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 8)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 8;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 8)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 8;
    }
    if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 12;
    }
    return _id;
}

// SIGNAL 0
void MLFlightAnalysis::sessionsChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}

// SIGNAL 1
void MLFlightAnalysis::loadedChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}
QT_WARNING_POP
