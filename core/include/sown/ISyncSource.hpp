#pragma once
#include "SyncState.hpp"

namespace sown {
class ISyncSource {
public:
    virtual ~ISyncSource() = default;
    virtual bool start() = 0;
    virtual void stop() = 0;
    virtual bool isConnected() const = 0;
    virtual SyncState getState() const = 0;
};
}
