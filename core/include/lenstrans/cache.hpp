#pragma once

#include "lenstrans/present.hpp"
#include "lenstrans/sha1.hpp"

#include <algorithm>
#include <mutex>
#include <string>
#include <unordered_map>

namespace lenstrans {

inline void AppendCacheField(std::string& key, const std::string& value) {
  key += std::to_string(value.size());
  key.push_back(':');
  key += value;
  key.push_back('|');
}

inline std::string CacheKey(const std::string& src_lang, const std::string& tgt_lang,
                            const std::string& text, bool quality = false,
                            const PresentationSemantics& presentation = {},
                            const std::string& settings_src = {},
                            const std::string& settings_tgt = {}) {
  std::string raw = "lenstrans-cache-v2|";
  AppendCacheField(raw, src_lang);
  AppendCacheField(raw, tgt_lang);
  AppendCacheField(raw, text);
  AppendCacheField(raw, quality ? "1" : "0");
  AppendCacheField(raw, std::to_string(static_cast<int>(presentation.lock)));
  AppendCacheField(raw, std::to_string(static_cast<int>(presentation.mode)));
  AppendCacheField(raw, presentation.contrast ? "1" : "0");
  AppendCacheField(raw, std::to_string(std::max(0, std::min(100, presentation.sticker_alpha))));
  AppendCacheField(raw, std::to_string(std::max(0, std::min(200, presentation.font_scale))));
  AppendCacheField(raw, settings_src);
  AppendCacheField(raw, settings_tgt);
  return Sha1Hex(raw);
}

// Compatibility overload for the old test helper. Production code uses the full key above.
inline std::string CacheKey(const std::string& src_lang, const std::string& text) {
  return Sha1Hex(src_lang + text);
}

class TranslationCache {
 public:
  bool Get(const std::string& key, std::string& out) const {
    std::lock_guard<std::mutex> lock(mu_);
    const auto it = map_.find(key);
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
    std::size_t total = 0;
    for (const auto& entry : map_) total += entry.first.size() + entry.second.size();
    return total;
  }

 private:
  mutable std::mutex mu_;
  std::unordered_map<std::string, std::string> map_;
};

}  // namespace lenstrans
