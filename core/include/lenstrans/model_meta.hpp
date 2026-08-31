#pragma once

#include <cctype>
#include <cstdint>
#include <string>

namespace lenstrans {

// Official Qwen2.5-1.5B Instruct Q4_K_M (Apache-2.0). Global redistributable default.
inline constexpr const char* kDefaultGgufFileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf";
inline constexpr std::uint64_t kDefaultGgufBytes = 1117320736ull;
inline constexpr const char* kDefaultGgufSha256 =
    "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e";

// Prefer ModelScope; fall back to Hugging Face (PRD D-path).
inline constexpr const char* kDefaultGgufUrlModelscope =
    "https://www.modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/"
    "qwen2.5-1.5b-instruct-q4_k_m.gguf";
inline constexpr const char* kDefaultGgufUrlHuggingFace =
    "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/"
    "qwen2.5-1.5b-instruct-q4_k_m.gguf";

inline constexpr std::int64_t kLocalIdleUnloadMs = 10 * 60 * 1000;  // 10 min

inline bool HexEqInsensitive(const std::string& a, const std::string& b) {
  if (a.size() != b.size()) return false;
  for (std::size_t i = 0; i < a.size(); ++i) {
    if (std::tolower(static_cast<unsigned char>(a[i])) !=
        std::tolower(static_cast<unsigned char>(b[i])))
      return false;
  }
  return true;
}

inline bool IsDefaultGgufSha256(const std::string& hex) {
  return HexEqInsensitive(hex, kDefaultGgufSha256);
}

}  // namespace lenstrans
