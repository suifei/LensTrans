#pragma once

#include <cstddef>

namespace lenstrans {

enum class EnginePref { Auto, Local, Cloud };
enum class EngineKind { Local, Cloud, None };

struct RouteInput {
  EnginePref pref = EnginePref::Auto;
  bool privacy = false;
  std::size_t text_chars = 0;
  bool local_ready = false;
  bool cloud_ready = false;
};

// PRD 6.3: privacy -> local; <=200 -> local; else cloud; local not ready -> cloud.
inline EngineKind RouteEngine(const RouteInput& in) {
  const bool want_cloud = in.pref == EnginePref::Cloud ||
                          (in.pref == EnginePref::Auto && in.text_chars > 200);
  if (in.privacy || in.pref == EnginePref::Local) {
    if (in.local_ready) return EngineKind::Local;
    return EngineKind::None;
  }
  if (want_cloud) {
    if (in.cloud_ready) return EngineKind::Cloud;
    if (in.local_ready) return EngineKind::Local;  // degrade
    return EngineKind::None;
  }
  if (in.local_ready) return EngineKind::Local;
  if (in.cloud_ready) return EngineKind::Cloud;
  return EngineKind::None;
}

}  // namespace lenstrans
