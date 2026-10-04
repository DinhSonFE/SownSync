#pragma once
#include "ISyncSource.hpp"
#include <memory>

namespace sown {
class SyncEngine {
public:
    explicit SyncEngine(std::shared_ptr<ISyncSource> source);
    bool start();
    void stop();
    SyncState state() const;
private:
    std::shared_ptr<ISyncSource> source_;
};
}
