#include "sown/SyncSourceManager.hpp"
#include <algorithm>
#include <limits>

namespace sown {

const char* toString(SourceRole r){
    switch(r){case SourceRole::Primary:return "PRIMARY";case SourceRole::Backup:return "BACKUP";default:return "DISABLED";}
}

bool SyncSourceManager::addSource(std::string id,std::string name,std::shared_ptr<ISyncSource> source,SourceRole role,int priority){
    if(id.empty()||!source)return false;
    std::lock_guard<std::mutex> g(mutex_);
    if(entries_.count(id))return false;
    entries_.emplace(id,Entry{id,std::move(name),std::move(source),role,priority});
    return true;
}
bool SyncSourceManager::removeSource(const std::string& id){
    std::lock_guard<std::mutex> g(mutex_);
    if(activeId_==id)activeId_.clear();
    return entries_.erase(id)>0;
}
bool SyncSourceManager::setRole(const std::string& id,SourceRole role){
    std::lock_guard<std::mutex> g(mutex_);auto it=entries_.find(id);if(it==entries_.end())return false;it->second.role=role;return true;
}
bool SyncSourceManager::setPriority(const std::string& id,int priority){
    std::lock_guard<std::mutex> g(mutex_);auto it=entries_.find(id);if(it==entries_.end())return false;it->second.priority=priority;return true;
}
bool SyncSourceManager::selectSource(const std::string& id){
    std::lock_guard<std::mutex> g(mutex_);auto it=entries_.find(id);if(it==entries_.end()||it->second.role==SourceRole::Disabled)return false;activeId_=id;return true;
}
void SyncSourceManager::setAutoSelect(bool e){std::lock_guard<std::mutex> g(mutex_);autoSelect_=e;}
bool SyncSourceManager::autoSelect() const{std::lock_guard<std::mutex> g(mutex_);return autoSelect_;}

std::shared_ptr<ISyncSource> SyncSourceManager::chooseUnlocked() const{
    std::shared_ptr<ISyncSource> best;int bestClass=std::numeric_limits<int>::max(),bestPriority=std::numeric_limits<int>::max();
    for(const auto& [id,e]:entries_){
        if(e.role==SourceRole::Disabled)continue;
        const auto st=e.source->getState();
        if(!st.connected)continue;
        const int cls=e.role==SourceRole::Primary?0:1;
        if(cls<bestClass||(cls==bestClass&&e.priority<bestPriority)){best=e.source;bestClass=cls;bestPriority=e.priority;}
    }
    return best;
}
SyncState SyncSourceManager::state(){
    std::lock_guard<std::mutex> g(mutex_);
    if(autoSelect_){
        auto best=chooseUnlocked();
        if(best){
            for(const auto& [id,e]:entries_)if(e.source==best){activeId_=id;break;}
        }else activeId_.clear();
    }
    auto it=entries_.find(activeId_);
    return it==entries_.end()?SyncState{}:it->second.source->getState();
}
std::shared_ptr<ISyncSource> SyncSourceManager::activeSource() const{
    std::lock_guard<std::mutex> g(mutex_);auto it=entries_.find(activeId_);return it==entries_.end()?nullptr:it->second.source;
}
std::string SyncSourceManager::activeId() const{std::lock_guard<std::mutex> g(mutex_);return activeId_;}
std::vector<SyncSourceInfo> SyncSourceManager::sources() const{
    std::lock_guard<std::mutex> g(mutex_);std::vector<SyncSourceInfo> out;out.reserve(entries_.size());
    for(const auto& [id,e]:entries_){auto st=e.source->getState();out.push_back({id,e.name,e.role,e.priority,st.connected,st.locked,id==activeId_});}
    std::sort(out.begin(),out.end(),[](const auto&a,const auto&b){if(a.role!=b.role)return (int)a.role<(int)b.role;return a.priority<b.priority;});
    return out;
}
} // namespace sown
