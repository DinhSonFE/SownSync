#pragma once
#include "ISyncSource.hpp"
#include "SyncSourceManager.hpp"
#include <memory>

namespace sown {
class SyncEngine {
public:
    explicit SyncEngine(std::shared_ptr<ISyncSource> source);
    explicit SyncEngine(std::shared_ptr<SyncSourceManager> manager);
    void setSource(std::shared_ptr<ISyncSource> source);
    void setSourceManager(std::shared_ptr<SyncSourceManager> manager);
    SyncState state() const;
private:
    std::shared_ptr<ISyncSource> source_;
    std::shared_ptr<SyncSourceManager> manager_;
};
}
