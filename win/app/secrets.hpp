#pragma once

#include <string>

namespace lenstrans::win {

std::string ConfigDir();
bool ProtectToFile(const std::string& path, const std::string& plain);
bool UnprotectFromFile(const std::string& path, std::string& plain);
void SetAutostart(bool on);
bool AutostartEnabled();
// Empty fields → "disabled". No key required for TCP probe. Never logs the key.
std::string ProbeCloud(const std::string& base_url, const std::string& model);

}  // namespace lenstrans::win
