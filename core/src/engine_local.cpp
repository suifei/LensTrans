#include "lenstrans/engine.hpp"
#include "lenstrans/model_meta.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#ifdef LENSTRANS_WITH_LLAMA
#include "llama.h"
#endif

#ifdef _WIN32
#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

namespace lenstrans {
namespace {

std::string StripThink(std::string s) {
  const auto a = s.find("<think>");
  const auto b = s.find("</think>");
  if (a != std::string::npos && b != std::string::npos && b > a) {
    s.erase(a, b + 8 - a);
  }
  while (!s.empty() && (s.front() == ' ' || s.front() == '\n' || s.front() == '"')) s.erase(s.begin());
  while (!s.empty() && (s.back() == ' ' || s.back() == '\n' || s.back() == '"')) s.pop_back();
  return s;
}

#ifdef LENSTRANS_WITH_LLAMA
class LlamaEngine final : public IEngine {
 public:
  explicit LlamaEngine(std::string path) : path_(std::move(path)) {
    last_activity_ = std::chrono::steady_clock::now();
  }
  ~LlamaEngine() override { Unload(); }

  bool Ready() const override {
    std::lock_guard<std::mutex> lock(mu_);
    if (ctx_) return true;
#ifdef _WIN32
    return GetFileAttributesA(path_.c_str()) != INVALID_FILE_ATTRIBUTES;
#else
    FILE* f = std::fopen(path_.c_str(), "rb");
    if (!f) return false;
    std::fclose(f);
    return true;
#endif
  }

  void NoteActivity() override { last_activity_ = std::chrono::steady_clock::now(); }

  void Unload() override {
    std::lock_guard<std::mutex> lock(mu_);
    if (ctx_) {
      llama_free(ctx_);
      ctx_ = nullptr;
    }
    if (model_) {
      llama_model_free(model_);
      model_ = nullptr;
    }
  }

  void MaybeIdleUnload(std::int64_t idle_ms) override {
    const auto limit = idle_ms > 0 ? idle_ms : kLocalIdleUnloadMs;
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - last_activity_)
                             .count();
    if (elapsed < limit) return;
    Unload();
  }

  bool Load() {
    std::lock_guard<std::mutex> lock(mu_);
    if (ctx_) return true;
    llama_backend_init();
    auto mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    model_ = llama_model_load_from_file(path_.c_str(), mp);
    if (!model_) return false;
    auto cp = llama_context_default_params();
    cp.n_ctx = 1024;
    cp.n_batch = 512;
    ctx_ = llama_init_from_model(model_, cp);
    if (!ctx_) {
      llama_model_free(model_);
      model_ = nullptr;
      return false;
    }
    return true;
  }

  TranslateResult Translate(const TranslateRequest& req) override {
    TranslateResult r;
    r.engine = EngineKind::Local;
    NoteActivity();
    if (!Load()) {
      r.error = "local model load failed";
      return r;
    }
    const auto t0 = std::chrono::steady_clock::now();
    std::lock_guard<std::mutex> lock(mu_);
    const std::string prompt = WrapQwenChat(BuildTranslatePrompt(req));
    const llama_vocab* vocab = llama_model_get_vocab(model_);
    std::vector<llama_token> tokens(prompt.size() + 16);
    int n = llama_tokenize(vocab, prompt.c_str(), static_cast<int>(prompt.size()), tokens.data(),
                           static_cast<int>(tokens.size()), true, true);
    if (n < 0) {
      tokens.resize(static_cast<std::size_t>(-n));
      n = llama_tokenize(vocab, prompt.c_str(), static_cast<int>(prompt.size()), tokens.data(),
                         static_cast<int>(tokens.size()), true, true);
    }
    if (n <= 0) {
      r.error = "tokenize failed";
      return r;
    }
    tokens.resize(static_cast<std::size_t>(n));
    const int n_vocab = llama_vocab_n_tokens(vocab);
    const int max_new = req.quality ? 96 : 48;
    auto decode_prompt = [&]() -> bool {
      llama_memory_clear(llama_get_memory(ctx_), true);
      llama_batch batch = llama_batch_get_one(tokens.data(), n);
      return llama_decode(ctx_, batch) == 0;
    };
    auto piece = [&](llama_token id) {
      char buf[256];
      const int m = llama_token_to_piece(vocab, id, buf, sizeof(buf), 0, true);
      return m > 0 ? std::string(buf, static_cast<std::size_t>(m)) : std::string();
    };
    auto logprob_of = [&](llama_token id) {
      const float* logits = llama_get_logits(ctx_);
      float mx = logits[0];
      for (int i = 1; i < n_vocab; ++i)
        if (logits[i] > mx) mx = logits[i];
      double z = 0;
      for (int i = 0; i < n_vocab; ++i) z += std::exp(static_cast<double>(logits[i] - mx));
      return static_cast<float>(logits[id] - mx - std::log(z));
    };
    auto greedy_from_here = [&](std::string& out, float& score, int remain) {
      llama_sampler* smpl = llama_sampler_init_greedy();
      for (int i = 0; i < remain; ++i) {
        const llama_token id = llama_sampler_sample(smpl, ctx_, -1);
        llama_sampler_accept(smpl, id);
        if (llama_vocab_is_eog(vocab, id)) break;
        const std::string tok = piece(id);
        if (tok.find("<|im_end|>") != std::string::npos ||
            tok.find("<|endoftext|>") != std::string::npos)
          break;
        score += logprob_of(id);
        out += tok;
        llama_batch one = llama_batch_get_one(const_cast<llama_token*>(&id), 1);
        if (llama_decode(ctx_, one) != 0) break;
      }
      llama_sampler_free(smpl);
    };
    auto top2 = [&](llama_token ids[2], float lps[2]) {
      const float* logits = llama_get_logits(ctx_);
      int a = 0, b = 0;
      float va = logits[0], vb = -1e30f;
      for (int i = 1; i < n_vocab; ++i) {
        if (logits[i] > va) {
          vb = va;
          b = a;
          va = logits[i];
          a = i;
        } else if (logits[i] > vb) {
          vb = logits[i];
          b = i;
        }
      }
      ids[0] = a;
      ids[1] = b;
      lps[0] = logprob_of(a);
      lps[1] = logprob_of(b);
    };

    if (!decode_prompt()) {
      r.error = "decode prompt failed";
      return r;
    }
    r.first_token_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0)
            .count());

    if (!req.quality) {
      std::string out;
      float score = 0;
      greedy_from_here(out, score, max_new);
      r.text = StripThink(out);
      r.beam_width = 1;
    } else {
      llama_token ids[2];
      float lps[2];
      top2(ids, lps);
      std::string best;
      float best_score = -1e30f;
      for (int b = 0; b < 2; ++b) {
        if (!decode_prompt()) break;
        if (llama_vocab_is_eog(vocab, ids[b])) continue;
        llama_token first = ids[b];
        llama_batch one = llama_batch_get_one(&first, 1);
        if (llama_decode(ctx_, one) != 0) continue;
        std::string out = piece(first);
        float score = lps[b];
        greedy_from_here(out, score, max_new - 1);
        if (score > best_score) {
          best_score = score;
          best = std::move(out);
        }
      }
      r.text = StripThink(best);
      r.beam_width = 2;
    }
    r.latency_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0)
            .count());
    NoteActivity();
    return r;
  }

 private:
  std::string path_;
  mutable std::mutex mu_;
  llama_model* model_ = nullptr;
  llama_context* ctx_ = nullptr;
  std::chrono::steady_clock::time_point last_activity_{};
};
#endif

#ifdef _WIN32
class CliEngine final : public IEngine {
 public:
  CliEngine(std::string model, std::string cli) : model_(std::move(model)), cli_(std::move(cli)) {}
  bool Ready() const override {
    return GetFileAttributesA(model_.c_str()) != INVALID_FILE_ATTRIBUTES &&
           GetFileAttributesA(cli_.c_str()) != INVALID_FILE_ATTRIBUTES;
  }
  TranslateResult Translate(const TranslateRequest& req) override {
    TranslateResult r;
    r.engine = EngineKind::Local;
    const auto t0 = std::chrono::steady_clock::now();
    const std::string prompt = BuildTranslatePrompt(req);
    std::string cmd = "\"" + cli_ + "\" -m \"" + model_ + "\" -p \"" + prompt +
                      "\" -n 96 -c 1024 --batch-size 512 -ngl 0 --temp 0 -no-cnv --log-disable";
    SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
    HANDLE rd = nullptr, wr = nullptr;
    CreatePipe(&rd, &wr, &sa, 0);
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);
    STARTUPINFOA si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = wr;
    si.hStdError = wr;
    PROCESS_INFORMATION pi{};
    std::vector<char> buf(cmd.begin(), cmd.end());
    buf.push_back(0);
    if (!CreateProcessA(nullptr, buf.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr,
                        nullptr, &si, &pi)) {
      CloseHandle(rd);
      CloseHandle(wr);
      r.error = "llama-cli spawn failed";
      return r;
    }
    CloseHandle(wr);
    std::string out;
    char chunk[4096];
    DWORD n = 0;
    while (ReadFile(rd, chunk, sizeof(chunk), &n, nullptr) && n) out.append(chunk, n);
    WaitForSingleObject(pi.hProcess, 30000);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    CloseHandle(rd);
    r.text = StripThink(out);
    r.latency_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0)
            .count());
    if (r.text.empty()) r.error = "empty local output";
    return r;
  }

 private:
  std::string model_;
  std::string cli_;
};
#endif

class UnconfiguredLocalEngine final : public IEngine {
 public:
  bool Ready() const override { return false; }
  TranslateResult Translate(const TranslateRequest&) override {
    TranslateResult r;
    r.engine = EngineKind::Local;
    r.error = "local engine unavailable";
    return r;
  }
};

}  // namespace

std::unique_ptr<IEngine> MakeLocalEngine(const std::string& model_path, const std::string& cli_path) {
#ifdef LENSTRANS_WITH_LLAMA
  (void)cli_path;
  return std::make_unique<LlamaEngine>(model_path);
#elif defined(_WIN32)
  return std::make_unique<CliEngine>(model_path, cli_path);
#else
  (void)model_path;
  (void)cli_path;
  return std::make_unique<UnconfiguredLocalEngine>();
#endif
}

}  // namespace lenstrans
