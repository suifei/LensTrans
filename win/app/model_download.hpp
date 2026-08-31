#pragma once

#include <cstdint>
#include <functional>
#include <string>

namespace lenstrans::win {

struct ModelDownloadProgress {
  std::uint64_t bytes_done = 0;
  std::uint64_t bytes_total = 0;
  std::string phase;  // fetch / hash / done / error
  std::string detail;
};

// Range-resume download of official Q4_K_M GGUF into dest_path.
// Writes to dest_path + ".part", verifies SHA256, then renames.
// Prefer ModelScope URL, fall back to Hugging Face. Never blocks "cloud-only".
bool DownloadDefaultGguf(const std::string& dest_path,
                         const std::function<void(const ModelDownloadProgress&)>& on_progress,
                         std::string& error_out);

// True if dest exists, size matches, and SHA256 matches (reads full file).
bool VerifyDefaultGguf(const std::string& dest_path, std::string& error_out);

}  // namespace lenstrans::win
