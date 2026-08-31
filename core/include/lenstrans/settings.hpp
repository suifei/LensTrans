#pragma once

#include "lenstrans/model_meta.hpp"
#include "lenstrans/present.hpp"
#include "lenstrans/router.hpp"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>

namespace lenstrans {

struct Settings {
  EnginePref engine = EnginePref::Auto;
  bool privacy = false;
  std::string ui_lang = "zh";
  std::string src_lang = "auto";
  std::string tgt_lang = "zh";
  bool quality = false;  // beam=2
  RenderLock render = RenderLock::Auto;
  int sticker_alpha = 92;  // 60–100
  bool contrast = false;
  int font_scale = 100;  // 80–150
  float overlay_alpha = 0.01f;
  bool restore_boxes = true;
  bool autostart = false;
  bool download_model = true;
  std::string cloud_base_url;  // empty = disabled
  std::string cloud_model;
  // api key never stored here in plaintext; see DPAPI blob path
  std::string model_path;  // empty → default next to repo/exe
  int hotkey_new = 1;      // reserved ids; actual VK stored below
  int vk_new = 'L';
  int mod_new = 6;  // CTRL|SHIFT
  int vk_edit = 'E';
  int mod_edit = 2;  // CTRL
  int vk_pause = 'T';
  int mod_pause = 2;
  int vk_hide = 'H';
  int mod_hide = 6;
  int vk_settings = 0xBC;  // VK_OEM_COMMA
  int mod_settings = 2;
};

inline std::string DefaultModelFileName() {
  return kDefaultGgufFileName;
}

inline bool CloudConfigured(const Settings& s, const std::string& api_key) {
  return !s.cloud_base_url.empty() && !s.cloud_model.empty() && !api_key.empty();
}

inline std::string SerializeSettings(const Settings& s) {
  std::ostringstream o;
  o << "engine=" << (s.engine == EnginePref::Local ? "local" : s.engine == EnginePref::Cloud ? "cloud" : "auto")
    << "\nprivacy=" << (s.privacy ? 1 : 0) << "\nui_lang=" << s.ui_lang << "\nsrc_lang=" << s.src_lang
    << "\ntgt_lang=" << s.tgt_lang << "\nquality=" << (s.quality ? 1 : 0) << "\nrender="
    << (s.render == RenderLock::Sticker ? "sticker" : s.render == RenderLock::Immersive ? "immersive" : "auto")
    << "\nsticker_alpha=" << s.sticker_alpha << "\ncontrast=" << (s.contrast ? 1 : 0)
    << "\nfont_scale=" << s.font_scale << "\noverlay_alpha=" << s.overlay_alpha
    << "\nrestore_boxes=" << (s.restore_boxes ? 1 : 0) << "\nautostart=" << (s.autostart ? 1 : 0)
    << "\ndownload_model=" << (s.download_model ? 1 : 0) << "\ncloud_base_url=" << s.cloud_base_url
    << "\ncloud_model=" << s.cloud_model << "\nmodel_path=" << s.model_path << "\nvk_new=" << s.vk_new
    << "\nmod_new=" << s.mod_new << "\nvk_edit=" << s.vk_edit << "\nmod_edit=" << s.mod_edit
    << "\nvk_pause=" << s.vk_pause << "\nmod_pause=" << s.mod_pause << "\nvk_hide=" << s.vk_hide
    << "\nmod_hide=" << s.mod_hide << "\nvk_settings=" << s.vk_settings
    << "\nmod_settings=" << s.mod_settings << "\n";
  return o.str();
}

inline Settings ParseSettings(const std::string& text) {
  Settings s;
  std::istringstream in(text);
  std::string line;
  auto parse_int = [](const std::string& value, int fallback) {
    try {
      std::size_t used = 0;
      const int parsed = std::stoi(value, &used);
      return used == value.size() ? parsed : fallback;
    } catch (...) {
      return fallback;
    }
  };
  auto parse_float = [](const std::string& value, float fallback) {
    try {
      std::size_t used = 0;
      const float parsed = std::stof(value, &used);
      return used == value.size() ? parsed : fallback;
    } catch (...) {
      return fallback;
    }
  };
  auto eq = [](const std::string& k, const std::string& key) { return k == key; };
  while (std::getline(in, line)) {
    const auto p = line.find('=');
    if (p == std::string::npos) continue;
    const std::string k = line.substr(0, p);
    const std::string v = line.substr(p + 1);
    if (eq(k, "engine")) {
      s.engine = v == "local" ? EnginePref::Local : v == "cloud" ? EnginePref::Cloud : EnginePref::Auto;
    } else if (eq(k, "privacy")) {
      s.privacy = v == "1";
    } else if (eq(k, "ui_lang")) {
      s.ui_lang = v;
    } else if (eq(k, "src_lang")) {
      s.src_lang = v;
    } else if (eq(k, "tgt_lang")) {
      s.tgt_lang = v;
    } else if (eq(k, "quality")) {
      s.quality = v == "1";
    } else if (eq(k, "render")) {
      s.render = v == "sticker" ? RenderLock::Sticker : v == "immersive" ? RenderLock::Immersive
                                                                        : RenderLock::Auto;
    } else if (eq(k, "sticker_alpha")) {
      s.sticker_alpha = std::max(60, std::min(100, parse_int(v, s.sticker_alpha)));
    } else if (eq(k, "contrast")) {
      s.contrast = v == "1";
    } else if (eq(k, "font_scale")) {
      s.font_scale = std::max(80, std::min(150, parse_int(v, s.font_scale)));
    } else if (eq(k, "overlay_alpha")) {
      s.overlay_alpha = std::max(0.005f, std::min(0.10f, parse_float(v, s.overlay_alpha)));
    } else if (eq(k, "restore_boxes")) {
      s.restore_boxes = v == "1";
    } else if (eq(k, "autostart")) {
      s.autostart = v == "1";
    } else if (eq(k, "download_model")) {
      s.download_model = v == "1";
    } else if (eq(k, "cloud_base_url")) {
      s.cloud_base_url = v;
    } else if (eq(k, "cloud_model")) {
      s.cloud_model = v;
    } else if (eq(k, "model_path")) {
      s.model_path = v;
    } else if (eq(k, "vk_new")) {
      s.vk_new = parse_int(v, s.vk_new);
    } else if (eq(k, "mod_new")) {
      s.mod_new = parse_int(v, s.mod_new);
    } else if (eq(k, "vk_edit")) {
      s.vk_edit = parse_int(v, s.vk_edit);
    } else if (eq(k, "mod_edit")) {
      s.mod_edit = parse_int(v, s.mod_edit);
    } else if (eq(k, "vk_pause")) {
      s.vk_pause = parse_int(v, s.vk_pause);
    } else if (eq(k, "mod_pause")) {
      s.mod_pause = parse_int(v, s.mod_pause);
    } else if (eq(k, "vk_hide")) {
      s.vk_hide = parse_int(v, s.vk_hide);
    } else if (eq(k, "mod_hide")) {
      s.mod_hide = parse_int(v, s.mod_hide);
    } else if (eq(k, "vk_settings")) {
      s.vk_settings = parse_int(v, s.vk_settings);
    } else if (eq(k, "mod_settings")) {
      s.mod_settings = parse_int(v, s.mod_settings);
    }
  }
  return s;
}

inline bool SaveSettingsFile(const std::string& path, const Settings& s) {
  std::ofstream f(path, std::ios::binary);
  if (!f) return false;
  f << SerializeSettings(s);
  return true;
}

inline Settings LoadSettingsFile(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return Settings{};
  std::ostringstream ss;
  ss << f.rdbuf();
  return ParseSettings(ss.str());
}

}  // namespace lenstrans
