#pragma once

#include "lenstrans/router.hpp"
#include "lenstrans/settings.hpp"

#include <sstream>
#include <string>
#include <vector>

namespace lenstrans {

struct BoxPersist {
  int x = 0, y = 0, w = 480, h = 320;
  std::string src_lang = "auto";
  std::string tgt_lang = "zh";
  EnginePref engine = EnginePref::Auto;
  RenderLock render = RenderLock::Auto;
};

inline std::string SerializeBoxes(const std::vector<BoxPersist>& boxes) {
  std::ostringstream o;
  for (const auto& b : boxes) {
    o << "box=" << b.x << "," << b.y << "," << b.w << "," << b.h << "," << b.src_lang << ","
      << b.tgt_lang << ","
      << (b.engine == EnginePref::Local ? "local" : b.engine == EnginePref::Cloud ? "cloud" : "auto")
      << ","
      << (b.render == RenderLock::Sticker ? "sticker"
                                          : b.render == RenderLock::Immersive ? "immersive" : "auto")
      << "\n";
  }
  return o.str();
}

inline std::vector<BoxPersist> ParseBoxes(const std::string& text) {
  std::vector<BoxPersist> out;
  std::istringstream in(text);
  std::string line;
  while (std::getline(in, line)) {
    if (line.rfind("box=", 0) != 0) continue;
    const std::string v = line.substr(4);
    std::vector<std::string> p;
    std::string cur;
    for (char c : v) {
      if (c == ',') {
        p.push_back(cur);
        cur.clear();
      } else {
        cur += c;
      }
    }
    p.push_back(cur);
    if (p.size() < 8) continue;
    BoxPersist b;
    try {
      b.x = std::stoi(p[0]);
      b.y = std::stoi(p[1]);
      b.w = std::max(160, std::stoi(p[2]));
      b.h = std::max(160, std::stoi(p[3]));
    } catch (...) {
      continue;
    }
    b.src_lang = p[4];
    b.tgt_lang = p[5];
    if (p[6] == "local")
      b.engine = EnginePref::Local;
    else if (p[6] == "cloud")
      b.engine = EnginePref::Cloud;
    if (p[7] == "sticker")
      b.render = RenderLock::Sticker;
    else if (p[7] == "immersive")
      b.render = RenderLock::Immersive;
    out.push_back(std::move(b));
  }
  return out;
}

}  // namespace lenstrans
