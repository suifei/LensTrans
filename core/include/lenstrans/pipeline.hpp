#pragma once

#include "lenstrans/cache.hpp"
#include "lenstrans/engine.hpp"
#include "lenstrans/ocr_block.hpp"
#include "lenstrans/present_layout.hpp"
#include "lenstrans/settings.hpp"
#include "lenstrans/translation.hpp"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace lenstrans {

enum class BoxState { Hidden, Editing, Watching, Translating, Paused };

class CancellationToken {
 public:
  CancellationToken() : cancelled_(std::make_shared<std::atomic_bool>(false)) {}
  void Cancel() const { cancelled_->store(true, std::memory_order_relaxed); }
  bool IsCancelled() const { return cancelled_->load(std::memory_order_relaxed); }

 private:
  std::shared_ptr<std::atomic_bool> cancelled_;
};

struct CapturedFrame {
  int width = 0;
  int height = 0;
  int stride_bytes = 0;
  std::uint64_t sequence = 0;
  std::vector<std::uint8_t> bgra;
  bool IsValid() const { return width > 0 && height > 0; }
};

class ICaptureProvider {
 public:
  virtual ~ICaptureProvider() = default;
  virtual bool Capture(CapturedFrame& frame, const CancellationToken& token) = 0;
};

class IOcrProvider {
 public:
  virtual ~IOcrProvider() = default;
  virtual bool Recognize(const CapturedFrame& frame, const CancellationToken& token,
                         std::vector<OcrBlock>& blocks) = 0;
};

struct PresentationFrame {
  int width = 0;
  int height = 0;
  std::vector<TranslatedBlock> blocks;
  std::vector<PresentBlockLayout> layout;
};

class IPresentationSink {
 public:
  virtual ~IPresentationSink() = default;
  virtual bool Present(const PresentationFrame& frame, const CancellationToken& token) = 0;
};

enum class PipelineState { Idle, Capturing, Recognizing, Watching, Translating, Presenting, Paused,
                          Cancelled, Failed };

struct PipelineServices {
  ICaptureProvider* capture = nullptr;
  IOcrProvider* ocr = nullptr;
  IPresentationSink* presenter = nullptr;
  IEngine* local = nullptr;
  IEngine* cloud = nullptr;
  TranslationCache* cache = nullptr;
};

struct PipelineOptions {
  Settings settings;
  int target_width = 0;
  int target_height = 0;
  OcrMergeOptions merge{};
};

struct PipelineResult {
  PipelineState state = PipelineState::Idle;
  bool stabilized = false;
  bool rendered = false;
  bool cancelled = false;
  std::string error;
  CapturedFrame frame;
  std::vector<TranslatedBlock> blocks;
  std::vector<PresentBlockLayout> layout;
};

class Pipeline final {
 public:
  Pipeline(PipelineServices services, PipelineOptions options = {});
  Pipeline(const Pipeline&) = delete;
  Pipeline& operator=(const Pipeline&) = delete;

  // One cooperative, synchronous state-machine step. Each instance is independent and reusable.
  PipelineResult Step();
  void Cancel();
  void Pause();
  void Resume();
  void Reset();
  PipelineState state() const { return state_; }

 private:
  PipelineServices services_;
  PipelineOptions options_;
  PipelineState state_ = PipelineState::Idle;
  CancellationToken token_;
  std::vector<OcrBlock> previous_;
  bool has_previous_ = false;
};

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
