#include "LlamaBridge.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(LENSTRANS_WITH_LLAMA)
#include "llama.h"
#endif

struct LenstransLlamaEngine {
  std::string path;
  mutable std::mutex mu;
#if defined(LENSTRANS_WITH_LLAMA)
  llama_model *model = nullptr;
  llama_context *ctx = nullptr;
#endif
};

extern "C" int lenstrans_llama_available(void) {
#if defined(LENSTRANS_WITH_LLAMA)
  return 1;
#else
  return 0;
#endif
}

extern "C" LenstransLlamaEngine *lenstrans_llama_create(const char *model_path) {
  if (!model_path || !model_path[0]) return nullptr;
  auto *eng = new LenstransLlamaEngine();
  eng->path = model_path;
  return eng;
}

extern "C" void lenstrans_llama_destroy(LenstransLlamaEngine *eng) {
  if (!eng) return;
  lenstrans_llama_unload(eng);
  delete eng;
}

extern "C" int lenstrans_llama_ready(const LenstransLlamaEngine *eng) {
  if (!eng) return 0;
#if defined(LENSTRANS_WITH_LLAMA)
  std::lock_guard<std::mutex> lock(eng->mu);
  if (eng->ctx) return 1;
#endif
  FILE *f = std::fopen(eng->path.c_str(), "rb");
  if (!f) return 0;
  std::fclose(f);
  return 1;
}

extern "C" void lenstrans_llama_unload(LenstransLlamaEngine *eng) {
  if (!eng) return;
#if defined(LENSTRANS_WITH_LLAMA)
  std::lock_guard<std::mutex> lock(eng->mu);
  if (eng->ctx) {
    llama_free(eng->ctx);
    eng->ctx = nullptr;
  }
  if (eng->model) {
    llama_model_free(eng->model);
    eng->model = nullptr;
  }
#else
  (void)eng;
#endif
}

extern "C" int lenstrans_llama_load(LenstransLlamaEngine *eng) {
  if (!eng) return 0;
#if !defined(LENSTRANS_WITH_LLAMA)
  (void)eng;
  return 0;
#else
  std::lock_guard<std::mutex> lock(eng->mu);
  if (eng->ctx) return 1;
  llama_backend_init();
  auto mp = llama_model_default_params();
  // Metal: offload as many layers as possible (parity with CLI -ngl 99).
  mp.n_gpu_layers = 99;
  eng->model = llama_model_load_from_file(eng->path.c_str(), mp);
  if (!eng->model) return 0;
  auto cp = llama_context_default_params();
  cp.n_ctx = 1024;
  cp.n_batch = 512;
  eng->ctx = llama_init_from_model(eng->model, cp);
  if (!eng->ctx) {
    llama_model_free(eng->model);
    eng->model = nullptr;
    return 0;
  }
  return 1;
#endif
}

namespace {

void set_err(char *err_buf, int err_cap, const char *msg) {
  if (!err_buf || err_cap <= 0) return;
  std::snprintf(err_buf, static_cast<size_t>(err_cap), "%s", msg ? msg : "");
}

#if defined(LENSTRANS_WITH_LLAMA)
std::string strip_think(std::string s) {
  const auto a = s.find("<think>");
  const auto b = s.find("</think>");
  if (a != std::string::npos && b != std::string::npos && b > a) {
    s.erase(a, b + 8 - a);
  }
  for (const char *m : {"<|im_end|>", "[end of text]"}) {
    const auto p = s.find(m);
    if (p != std::string::npos) s.erase(p);
  }
  while (!s.empty() && (s.front() == ' ' || s.front() == '\n' || s.front() == '"' || s.front() == '\t'))
    s.erase(s.begin());
  while (!s.empty() && (s.back() == ' ' || s.back() == '\n' || s.back() == '"' || s.back() == '\t'))
    s.pop_back();
  return s;
}
#endif

}  // namespace

extern "C" int lenstrans_llama_translate(LenstransLlamaEngine *eng,
                                         const char *prompt,
                                         int max_new_tokens,
                                         char *out_buf,
                                         int out_cap,
                                         int *latency_ms,
                                         char *err_buf,
                                         int err_cap) {
  if (latency_ms) *latency_ms = 0;
  if (out_buf && out_cap > 0) out_buf[0] = '\0';
  if (err_buf && err_cap > 0) err_buf[0] = '\0';

#if !defined(LENSTRANS_WITH_LLAMA)
  (void)eng;
  (void)prompt;
  (void)max_new_tokens;
  set_err(err_buf, err_cap, "in-process llama not linked");
  return -1;
#else
  if (!eng || !prompt || !out_buf || out_cap <= 1) {
    set_err(err_buf, err_cap, "bad args");
    return -1;
  }
  if (!lenstrans_llama_load(eng)) {
    set_err(err_buf, err_cap, "local model load failed");
    return -1;
  }

  const auto t0 = std::chrono::steady_clock::now();
  std::lock_guard<std::mutex> lock(eng->mu);

  const llama_vocab *vocab = llama_model_get_vocab(eng->model);
  std::vector<llama_token> tokens(std::strlen(prompt) + 16);
  int n = llama_tokenize(vocab, prompt, static_cast<int>(std::strlen(prompt)), tokens.data(),
                         static_cast<int>(tokens.size()), true, true);
  if (n < 0) {
    tokens.resize(static_cast<std::size_t>(-n));
    n = llama_tokenize(vocab, prompt, static_cast<int>(std::strlen(prompt)), tokens.data(),
                       static_cast<int>(tokens.size()), true, true);
  }
  if (n <= 0) {
    set_err(err_buf, err_cap, "tokenize failed");
    return -1;
  }
  tokens.resize(static_cast<std::size_t>(n));

  llama_memory_clear(llama_get_memory(eng->ctx), true);
  llama_batch batch = llama_batch_get_one(tokens.data(), n);
  if (llama_decode(eng->ctx, batch) != 0) {
    set_err(err_buf, err_cap, "decode prompt failed");
    return -1;
  }

  const int max_new = max_new_tokens > 0 ? max_new_tokens : 96;
  std::string out;
  llama_sampler *smpl = llama_sampler_init_greedy();
  for (int i = 0; i < max_new; ++i) {
    const llama_token id = llama_sampler_sample(smpl, eng->ctx, -1);
    llama_sampler_accept(smpl, id);
    if (llama_vocab_is_eog(vocab, id)) break;
    char buf[256];
    const int m = llama_token_to_piece(vocab, id, buf, sizeof(buf), 0, true);
    if (m <= 0) break;
    const std::string tok(buf, static_cast<std::size_t>(m));
    if (tok.find("<|im_end|>") != std::string::npos || tok.find("<|endoftext|>") != std::string::npos)
      break;
    out += tok;
    llama_batch one = llama_batch_get_one(const_cast<llama_token *>(&id), 1);
    if (llama_decode(eng->ctx, one) != 0) break;
  }
  llama_sampler_free(smpl);

  out = strip_think(std::move(out));
  if (out.empty()) {
    set_err(err_buf, err_cap, "empty local output");
    return -1;
  }
  std::snprintf(out_buf, static_cast<size_t>(out_cap), "%s", out.c_str());
  if (latency_ms) {
    *latency_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0)
            .count());
  }
  return 0;
#endif
}
