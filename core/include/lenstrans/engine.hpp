#pragma once

#include "lenstrans/router.hpp"

#include <memory>
#include <string>

namespace lenstrans {

struct TranslateRequest {
  std::string text;
  std::string src_lang = "auto";
  std::string tgt_lang = "zh";
  bool quality = false;
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

inline std::string TargetLanguageName(const std::string& code) {
  if (code == "zh" || code == "zh-CN") return "Simplified Chinese";
  if (code == "en") return "English";
  if (code == "ja") return "Japanese";
  if (code == "ko") return "Korean";
  return code;
}

inline std::string BuildTranslatePrompt(const TranslateRequest& req) {
  if (req.tgt_lang == "zh" || req.tgt_lang == "zh-CN") {
    return "英译简体中文。习语按含义意译，勿逐字直译。输出完整且简洁的译文，不要解释。\n\n" + req.text;
  }
  return "Translate the following segment into " + TargetLanguageName(req.tgt_lang) +
         ", without additional explanation.\n\n" + req.text;
}

inline std::string WrapQwenChat(const std::string& user) {
  return "<|im_start|>system\nYou translate English into Simplified Chinese. Idioms: translate by "
         "meaning, not literally (e.g. on the house=免费供应, piece of cake=轻而易举). Output a "
         "complete but concise translation; no explanation."
         "<|im_end|>\n<|im_start|>user\n" +
         user + "<|im_end|>\n<|im_start|>assistant\n";
}

class IEngine {
 public:
  virtual ~IEngine() = default;
  virtual bool Ready() const = 0;
  virtual TranslateResult Translate(const TranslateRequest& req) = 0;
};

std::unique_ptr<IEngine> MakeLocalEngine(const std::string& model_path, const std::string& cli_path);
std::unique_ptr<IEngine> MakeCloudEngine(const std::string& base_url, const std::string& api_key,
                                         const std::string& model);
std::unique_ptr<IEngine> MakeFakeEngine(EngineKind kind, bool ready, std::string reply,
                                        std::string error, int fail_times = 0);

}  // namespace lenstrans
