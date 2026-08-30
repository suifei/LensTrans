#pragma once

#include "lenstrans/ocr_block.hpp"

#include <chrono>
#include <cmath>
#include <string>
#include <vector>

namespace lenstrans {

enum class BoxState { Hidden, Editing, Watching, Translating, Paused };

inline bool SameBlock(const OcrBlock& a, const OcrBlock& b, float px_tol = 2.0f) {
  if (a.text != b.text) return false;
  return std::abs(a.bbox.x - b.bbox.x) <= px_tol && std::abs(a.bbox.y - b.bbox.y) <= px_tol &&
         std::abs(a.bbox.w - b.bbox.w) <= px_tol && std::abs(a.bbox.h - b.bbox.h) <= px_tol;
}

inline bool SameBlocks(const std::vector<OcrBlock>& a, const std::vector<OcrBlock>& b) {
  if (a.size() != b.size()) return false;
  for (std::size_t i = 0; i < a.size(); ++i) {
    if (!SameBlock(a[i], b[i])) return false;
  }
  return true;
}

// Commit only after two consecutive identical OCR snapshots (PRD §5).
struct Stabilizer {
  std::vector<OcrBlock> prev;
  bool has_prev = false;

  bool Feed(const std::vector<OcrBlock>& cur, std::vector<OcrBlock>& committed) {
    if (!has_prev) {
      prev = cur;
      has_prev = true;
      return false;
    }
    if (SameBlocks(prev, cur)) {
      committed = cur;
      return true;
    }
    prev = cur;
    return false;
  }

  void Reset() {
    prev.clear();
    has_prev = false;
  }
};

// 300ms quiet after last text change before enqueue.
struct Debounce {
  std::chrono::steady_clock::time_point last_change{};
  std::string last_sig;
  bool pending = false;

  static std::string Sig(const std::vector<OcrBlock>& blocks) {
    std::string s;
    for (const auto& b : blocks) {
      s += b.text;
      s += '|';
    }
    return s;
  }

  // Returns true when `now` is ≥300ms after the last signature change.
  bool Tick(const std::vector<OcrBlock>& committed, std::chrono::steady_clock::time_point now,
            int ms = 300) {
    const std::string sig = Sig(committed);
    if (sig != last_sig) {
      last_sig = sig;
      last_change = now;
      pending = true;
      return false;
    }
    if (!pending) return false;
    if (now - last_change >= std::chrono::milliseconds(ms)) {
      pending = false;
      return true;
    }
    return false;
  }
};

// Idle ≥2s → sleep (caller should drop capture rate).
struct IdleWatch {
  std::chrono::steady_clock::time_point last_motion{};
  bool sleeping = false;

  void Motion(std::chrono::steady_clock::time_point now) {
    last_motion = now;
    sleeping = false;
  }

  bool ShouldSleep(std::chrono::steady_clock::time_point now, int idle_ms = 2000) {
    if (last_motion.time_since_epoch().count() == 0) last_motion = now;
    sleeping = now - last_motion >= std::chrono::milliseconds(idle_ms);
    return sleeping;
  }
};

}  // namespace lenstrans
