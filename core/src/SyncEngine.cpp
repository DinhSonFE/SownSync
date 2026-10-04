#include "sown/SyncEngine.hpp"
#include <stdexcept>
namespace sown {
SyncEngine::SyncEngine(std::shared_ptr<ISyncSource> source) : source_(std::move(source)) { if(!source_) throw std::invalid_argument("sync source is null"); }
void SyncEngine::setSource(std::shared_ptr<ISyncSource> source) { if(!source) throw std::invalid_argument("sync source is null"); source_=std::move(source); }
SyncState SyncEngine::state() const { return source_->getState(); }
}
