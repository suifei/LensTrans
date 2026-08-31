#include "lenstrans/engine.hpp"

#include <chrono>
#include <thread>
#include <utility>

namespace lenstrans {
namespace {

class FakeEngine final : public IEngine {
 public:
  FakeEngine(EngineKind kind, bool ready, std::string reply, std::string error, int fail_times)
      : kind_(kind), ready_(ready), reply_(std::move(reply)), error_(std::move(error)),
        fail_times_(fail_times) {}

  bool Ready() const override { return ready_; }
  bool Preload() override { return ready_; }

  TranslateResult Translate(const TranslateRequest&) override {
    TranslateResult r;
    r.engine = kind_;
    if (fail_times_ > 0) {
      --fail_times_;
      r.error = error_.empty() ? "timeout" : error_;
      if (r.error == "timeout") std::this_thread::sleep_for(std::chrono::milliseconds(1));
      return r;
    }
    if (!error_.empty() && fail_times_ == 0 && reply_.empty()) {
      r.error = error_;
      return r;
    }
    r.text = reply_;
    r.latency_ms = 1;
    r.first_token_ms = 1;
    return r;
  }

 private:
  EngineKind kind_;
  bool ready_;
  std::string reply_;
  std::string error_;
  int fail_times_ = 0;
};

}  // namespace

std::unique_ptr<IEngine> MakeFakeEngine(EngineKind kind, bool ready, std::string reply,
                                        std::string error, int fail_times) {
  return std::make_unique<FakeEngine>(kind, ready, std::move(reply), std::move(error), fail_times);
}

}  // namespace lenstrans
