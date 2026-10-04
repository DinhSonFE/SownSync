#include "sown/SyncEngine.hpp"
namespace sown {
SyncEngine::SyncEngine(std::shared_ptr<ISyncSource> source) : source_(std::move(source)) {}
bool SyncEngine::start() { return source_ && source_->start(); }
void SyncEngine::stop() { if (source_) source_->stop(); }
SyncState SyncEngine::state() const { return source_ ? source_->getState() : SyncState{}; }
}
