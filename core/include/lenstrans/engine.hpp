#pragma once

#include "lenstrans/batch_translation.hpp"
#include "lenstrans/model_meta.hpp"
#include "lenstrans/present.hpp"
#include "lenstrans/router.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace lenstrans {

struct TranslateRequest {
  std::string text;
  std::string src_lang = "auto";
  std::string tgt_lang = "zh";
  bool quality = false;
  bool batch_protocol = false;
  PresentationSemantics presentation{};
};

struct TranslateResult {
  std::string text;
  bool from_cache = false;
  EngineKind engine = EngineKind::None;
  int latency_ms = 0;
  int first_token_ms = 0;
  int beam_width = 1;
  std::string error;
};

inline std::string LanguageName(const std::string& code) {
  if (code.empty() || code == "auto") return "its automatically detected source language";
  if (code == "zh" || code == "zh-CN") return "Simplified Chinese";
  if (code == "en") return "English";
  if (code == "ja") return "Japanese";
  if (code == "ko") return "Korean";
  return code;
}

inline std::string BuildTranslatePrompt(const TranslateRequest& req) {
  const auto source = LanguageName(req.src_lang);
  const auto target = LanguageName(req.tgt_lang);
  if (req.batch_protocol) return BuildBatchUserPrompt(req.text, source, target);
  return "Translate the following text from " + source + " into " + target +
         ". Preserve meaning and idioms. Output only the complete translation, without "
         "explanation.\n\n" + req.text;
}

inline std::string WrapQwenChat(const std::string& user) {
  return "<|im_start|>system\nYou are a multilingual translator. Detect source languages when "
         "requested, preserve meaning and idioms, and output only complete translations without "
         "explanation."
         "<|im_end|>\n<|im_start|>user\n" +
         user + "<|im_end|>\n<|im_start|>assistant\n";
}

class IEngine {
 public:
  virtual ~IEngine() = default;
  virtual bool Ready() const = 0;
  virtual TranslateResult Translate(const TranslateRequest& req) = 0;
  // Local llama: unload weights after kLocalIdleUnloadMs with no Translate (PRD).
  virtual void NoteActivity() {}
  virtual void MaybeIdleUnload(std::int64_t /*idle_ms*/ = 0) {}
  virtual void Unload() {}
};

std::unique_ptr<IEngine> MakeLocalEngine(const std::string& model_path, const std::string& cli_path);
std::unique_ptr<IEngine> MakeCloudEngine(const std::string& base_url, const std::string& api_key,
                                         const std::string& model);
std::unique_ptr<IEngine> MakeFakeEngine(EngineKind kind, bool ready, std::string reply,
                                        std::string error, int fail_times = 0);

}  // namespace lenstrans
