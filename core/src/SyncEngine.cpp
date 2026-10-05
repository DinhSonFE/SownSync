#include "sown/SyncEngine.hpp"
#include <stdexcept>
namespace sown {
SyncEngine::SyncEngine(std::shared_ptr<ISyncSource> source):source_(std::move(source)){if(!source_)throw std::invalid_argument("sync source is null");}
SyncEngine::SyncEngine(std::shared_ptr<SyncSourceManager> manager):manager_(std::move(manager)){if(!manager_)throw std::invalid_argument("sync source manager is null");}
void SyncEngine::setSource(std::shared_ptr<ISyncSource> source){if(!source)throw std::invalid_argument("sync source is null");source_=std::move(source);manager_.reset();}
void SyncEngine::setSourceManager(std::shared_ptr<SyncSourceManager> manager){if(!manager)throw std::invalid_argument("sync source manager is null");manager_=std::move(manager);source_.reset();}
SyncState SyncEngine::state() const{if(manager_)return manager_->state();return source_->getState();}
}
