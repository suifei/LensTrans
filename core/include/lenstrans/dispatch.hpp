#pragma once

#include "lenstrans/cache.hpp"
#include "lenstrans/cloud_http.hpp"
#include "lenstrans/engine.hpp"
#include "lenstrans/router.hpp"
#include "lenstrans/settings.hpp"

#include <utility>

namespace lenstrans {

inline TranslateResult DispatchTranslate(const Settings& settings, IEngine* local, IEngine* cloud,
                                         TranslationCache* cache, const TranslateRequest& req) {
  TranslateResult out;
  const std::string key = CacheKey(settings.src_lang, req.text);
  if (cache) {
    std::string hit;
    if (cache->Get(key, hit)) {
      out.text = hit;
      out.from_cache = true;
      out.engine = EngineKind::Local;
      out.latency_ms = 0;
      return out;
    }
  }
  const bool local_ok = local && local->Ready();
  const bool cloud_ok = cloud && cloud->Ready() && !settings.privacy;
  const EngineKind kind =
      RouteEngine({settings.engine, settings.privacy, req.text.size(), local_ok, cloud_ok});
  if (kind == EngineKind::Cloud && cloud) {
    out = cloud->Translate(req);
    if ((out.text.empty() || !out.error.empty()) && ShouldRetryCloud(out.error)) {
      out = cloud->Translate(req);
    }
    if ((out.text.empty() || !out.error.empty()) && local_ok) {
      auto local_r = local->Translate(req);
      if (!local_r.text.empty()) local_r.error.clear();
      out = std::move(local_r);
    }
  } else if (kind == EngineKind::Local && local) {
    out = local->Translate(req);
  } else {
    out.error = "no engine";
    out.engine = EngineKind::None;
  }
  if (cache && !out.text.empty()) cache->Put(key, out.text);
  return out;
}

}  // namespace lenstrans
