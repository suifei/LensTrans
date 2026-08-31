#pragma once

#include <cctype>
#include <cstdint>
#include <string>

namespace lenstrans {

// Official Qwen2.5-0.5B Instruct Q4_K_M (Apache-2.0). Locked for EU/UK/KR redistributable default.
inline constexpr const char* kDefaultGgufFileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf";
inline constexpr std::uint64_t kDefaultGgufBytes = 491400032ull;
inline constexpr const char* kDefaultGgufSha256 =
    "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db";

// Prefer ModelScope; fall back to Hugging Face (PRD D-path).
inline constexpr const char* kDefaultGgufUrlModelscope =
    "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/"
    "qwen2.5-0.5b-instruct-q4_k_m.gguf";
inline constexpr const char* kDefaultGgufUrlHuggingFace =
    "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/"
    "qwen2.5-0.5b-instruct-q4_k_m.gguf";

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
