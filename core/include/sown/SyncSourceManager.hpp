#pragma once
#include "ISyncSource.hpp"
#include <cstddef>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace sown {

enum class SourceRole { Primary, Backup, Disabled };

struct SyncSourceInfo {
    std::string id;
    std::string name;
    SourceRole role{SourceRole::Backup};
    int priority{100};
    bool connected{false};
    bool locked{false};
    bool selected{false};
};

class SyncSourceManager {
public:
    bool addSource(std::string id, std::string name, std::shared_ptr<ISyncSource> source,
                   SourceRole role=SourceRole::Backup, int priority=100);
    bool removeSource(const std::string& id);
    bool setRole(const std::string& id, SourceRole role);
    bool setPriority(const std::string& id, int priority);
    bool selectSource(const std::string& id);
    void setAutoSelect(bool enabled);
    bool autoSelect() const;

    SyncState state();
    std::shared_ptr<ISyncSource> activeSource() const;
    std::string activeId() const;
    std::vector<SyncSourceInfo> sources() const;

private:
    struct Entry {
        std::string id, name;
        std::shared_ptr<ISyncSource> source;
        SourceRole role{SourceRole::Backup};
        int priority{100};
    };

    std::shared_ptr<ISyncSource> chooseUnlocked() const;
    mutable std::mutex mutex_;
    std::unordered_map<std::string,Entry> entries_;
    std::string activeId_;
    bool autoSelect_{true};
};

const char* toString(SourceRole role);

} // namespace sown
