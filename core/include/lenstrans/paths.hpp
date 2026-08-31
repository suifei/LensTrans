#pragma once

#include "lenstrans/model_meta.hpp"

#include <cstdlib>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace lenstrans {

inline std::string ExeDir() {
#ifdef _WIN32
  char buf[MAX_PATH]{};
  const DWORD n = GetModuleFileNameA(nullptr, buf, MAX_PATH);
  if (!n) return ".";
  return std::filesystem::path(buf).parent_path().string();
#else
  std::error_code ec;
  auto p = std::filesystem::read_symlink("/proc/self/exe", ec);
  if (ec) return ".";
  return p.parent_path().string();
#endif
}

inline bool FileExists(const std::string& path) {
  std::error_code ec;
  return std::filesystem::is_regular_file(path, ec);
}

inline std::string JoinPath(const std::string& a, const std::string& b) {
  return (std::filesystem::path(a) / b).string();
}

// Prefer LENSTRANS_ROOT, then walk up from exe looking for CMakeLists.txt + models/.
inline std::string DetectRepoRoot() {
  if (const char* env = std::getenv("LENSTRANS_ROOT"); env && *env) {
    if (FileExists(JoinPath(env, "CMakeLists.txt"))) return env;
  }
  std::filesystem::path cur = ExeDir();
  for (int i = 0; i < 8; ++i) {
    if (std::filesystem::exists(cur / "CMakeLists.txt") &&
        std::filesystem::exists(cur / "models")) {
      return cur.string();
    }
    if (!cur.has_parent_path() || cur == cur.root_path()) break;
    cur = cur.parent_path();
  }
  return ExeDir();
}

inline std::string EvalOutDir() {
  if (const char* env = std::getenv("LENSTRANS_EVAL_OUT"); env && *env) return env;
  return JoinPath(DetectRepoRoot(), "tools/eval/out");
}

inline bool EnsureDir(const std::string& dir) {
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  return !ec;
}

inline std::vector<std::string> GgufFilesIn(const std::string& dir) {
  std::vector<std::string> files;
  std::error_code ec;
  for (const auto& entry : std::filesystem::directory_iterator(dir, ec)) {
    if (ec) break;
    if (!entry.is_regular_file(ec)) continue;
    auto extension = entry.path().extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (extension == ".gguf") files.push_back(entry.path().string());
  }
  std::sort(files.begin(), files.end());
  return files;
}

inline std::string ActiveModelIn(const std::string& dir) {
  std::ifstream input(JoinPath(dir, "active-model.txt"), std::ios::binary);
  std::string name;
  if (!input || !std::getline(input, name)) return {};
  while (!name.empty() && std::isspace(static_cast<unsigned char>(name.back()))) name.pop_back();
  while (!name.empty() && std::isspace(static_cast<unsigned char>(name.front()))) name.erase(name.begin());
  if (name.empty()) return {};
  const auto path = std::filesystem::path(name).is_absolute() ? name : JoinPath(dir, name);
  return FileExists(path) ? path : std::string();
}

inline std::vector<std::string> DefaultModelDirectories() {
  const std::string root = DetectRepoRoot();
  const std::string exe = ExeDir();
  std::vector<std::string> dirs = {
      JoinPath(root, "models"), exe, JoinPath(exe, "models"),
      JoinPath(JoinPath(exe, ".."), "models"),
      JoinPath(JoinPath(exe, "../.."), "models"),
  };
#ifdef _WIN32
  if (const char* local = std::getenv("LOCALAPPDATA"); local && *local)
    dirs.insert(dirs.begin(), JoinPath(JoinPath(local, "LensTrans"), "models"));
#endif
  return dirs;
}

inline std::string FindDefaultModelPath(const std::string& override_path = {}) {
  if (!override_path.empty() && FileExists(override_path)) return override_path;
  if (const char* env = std::getenv("LENSTRANS_MODEL_PATH"); env && *env && FileExists(env))
    return env;
  const std::string name = kDefaultGgufFileName;
  const std::string root = DetectRepoRoot();
  const auto dirs = DefaultModelDirectories();
  for (const auto& dir : dirs) {
    const auto active = ActiveModelIn(dir);
    if (!active.empty()) return active;
  }
  for (const auto& dir : dirs) {
    const auto p = JoinPath(dir, name);
    if (FileExists(p)) return p;
  }
  for (const auto& dir : dirs) {
    const auto files = GgufFilesIn(dir);
    if (!files.empty()) return files.front();
  }
  return JoinPath(root, JoinPath("models", name));
}

inline std::string FindFallbackModelPath(const std::string& primary_path) {
  for (const auto& dir : DefaultModelDirectories()) {
    const auto candidate = JoinPath(dir, kDefaultGgufFileName);
    if (candidate != primary_path && FileExists(candidate)) return candidate;
  }
  return {};
}

inline std::string FindLlamaCliPath() {
  const std::string root = DetectRepoRoot();
  const std::string exe = ExeDir();
  const std::vector<std::string> cands = {
      JoinPath(root, "third_party/llama.cpp/build/bin/Release/llama-cli.exe"),
      JoinPath(root, "third_party/llama.cpp/build/bin/llama-cli"),
      JoinPath(exe, "llama-cli.exe"),
      JoinPath(exe, "llama-cli"),
  };
  for (const auto& p : cands) {
    if (FileExists(p)) return p;
  }
  return {};
}

inline bool WriteTextFile(const std::string& path, const std::string& body) {
  EnsureDir(std::filesystem::path(path).parent_path().string());
  std::ofstream f(path, std::ios::binary);
  if (!f) return false;
  f << body;
  return static_cast<bool>(f);
}

}  // namespace lenstrans
