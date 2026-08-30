#pragma once

#include <string>

namespace lenstrans {

// HKCU Run REG_SZ: quote if the path contains spaces.
inline std::string QuoteRunPath(const std::string& exe) {
  if (exe.empty()) return {};
  if (exe.front() == '"') return exe;
  if (exe.find(' ') == std::string::npos && exe.find('\t') == std::string::npos) return exe;
  return "\"" + exe + "\"";
}

inline std::string UnquoteRunPath(const std::string& value) {
  if (value.size() >= 2 && value.front() == '"' && value.back() == '"')
    return value.substr(1, value.size() - 2);
  return value;
}

inline bool RunValuePointsTo(const std::string& stored, const std::string& exe) {
  return !exe.empty() && UnquoteRunPath(stored) == exe;
}

}  // namespace lenstrans
