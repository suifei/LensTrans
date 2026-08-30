#pragma once

#include "lenstrans/sha1.hpp"

#include <mutex>
#include <string>
#include <unordered_map>

namespace lenstrans {

inline std::string CacheKey(const std::string& src_lang, const std::string& text) {
  return Sha1Hex(src_lang + text);
}

class TranslationCache {
 public:
  bool Get(const std::string& key, std::string& out) const {
    std::lock_guard<std::mutex> lock(mu_);
    auto it = map_.find(key);
    if (it == map_.end()) return false;
    out = it->second;
    return true;
  }

  void Put(const std::string& key, std::string value) {
    std::lock_guard<std::mutex> lock(mu_);
    map_[key] = std::move(value);
  }

  void Clear() {
    std::lock_guard<std::mutex> lock(mu_);
    map_.clear();
  }

  std::size_t Size() const {
    std::lock_guard<std::mutex> lock(mu_);
    return map_.size();
  }

  std::size_t Bytes() const {
    std::lock_guard<std::mutex> lock(mu_);
    std::size_t n = 0;
    for (const auto& kv : map_) n += kv.first.size() + kv.second.size();
    return n;
  }

 private:
  mutable std::mutex mu_;
  std::unordered_map<std::string, std::string> map_;
};

}  // namespace lenstrans
