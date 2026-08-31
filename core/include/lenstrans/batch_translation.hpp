#pragma once

#include "lenstrans/text.hpp"
#include "lenstrans/translation.hpp"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

namespace lenstrans {

inline std::string TrimBatchText(std::string text) {
  while (!text.empty() && std::isspace(static_cast<unsigned char>(text.front()))) text.erase(text.begin());
  while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back()))) text.pop_back();
  return text;
}

inline bool StartsWithAsciiInsensitive(const std::string& text, const std::string& prefix) {
  if (text.size() < prefix.size()) return false;
  for (std::size_t i = 0; i < prefix.size(); ++i) {
    if (std::tolower(static_cast<unsigned char>(text[i])) !=
        std::tolower(static_cast<unsigned char>(prefix[i])))
      return false;
  }
  return true;
}

inline bool IsChineseTarget(const std::string& target) {
  return StartsWithAsciiInsensitive(target, "zh") ||
         StartsWithAsciiInsensitive(target, "chinese") ||
         StartsWithAsciiInsensitive(target, "simplified chinese") ||
         StartsWithAsciiInsensitive(target, "traditional chinese");
}

inline bool IsJapaneseTarget(const std::string& target) {
  return StartsWithAsciiInsensitive(target, "ja") ||
         StartsWithAsciiInsensitive(target, "japanese");
}

inline bool IsKoreanTarget(const std::string& target) {
  return StartsWithAsciiInsensitive(target, "ko") ||
         StartsWithAsciiInsensitive(target, "korean");
}

struct ScriptCounts {
  std::size_t han = 0;
  std::size_t kana = 0;
  std::size_t hangul = 0;
  std::size_t latin = 0;
  std::size_t other_letters = 0;
};

inline ScriptCounts CountScripts(const std::string& text) {
  ScriptCounts counts;
  for (std::size_t i = 0; i < text.size();) {
    const auto cp = Utf8CodepointAt(text, i);
    i = Utf8Next(text, i);
    if ((cp >= 0x3400 && cp <= 0x4dbf) || (cp >= 0x4e00 && cp <= 0x9fff) ||
        (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x20000 && cp <= 0x323af))
      ++counts.han;
    else if ((cp >= 0x3040 && cp <= 0x30ff) || (cp >= 0x31f0 && cp <= 0x31ff))
      ++counts.kana;
    else if ((cp >= 0x1100 && cp <= 0x11ff) || (cp >= 0x3130 && cp <= 0x318f) ||
             (cp >= 0xac00 && cp <= 0xd7af))
      ++counts.hangul;
    else if ((cp >= 'A' && cp <= 'Z') || (cp >= 'a' && cp <= 'z'))
      ++counts.latin;
    else if ((cp >= 0x0370 && cp <= 0x052f) || (cp >= 0x0590 && cp <= 0x08ff) ||
             (cp >= 0x0900 && cp <= 0x1cff) || (cp >= 0x2c00 && cp <= 0x2dff) ||
             (cp >= 0xa640 && cp <= 0xa69f))
      ++counts.other_letters;
  }
  return counts;
}

inline bool SourceNeedsTranslationForTarget(const std::string& source,
                                            const std::string& target_code) {
  const auto clean = TrimBatchText(source);
  if (clean.empty()) return false;
  auto first_token = clean.substr(0, clean.find_first_of(" \t\r\n"));
  std::transform(first_token.begin(), first_token.end(), first_token.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  for (const char* extension : {".txt", ".exe", ".app", ".dll", ".json", ".md", ".png", ".jpg"}) {
    if (first_token.size() >= std::strlen(extension) &&
        first_token.rfind(extension) == first_token.size() - std::strlen(extension))
      return false;
  }
  const auto scripts = CountScripts(clean);
  if (IsChineseTarget(target_code)) {
    if (scripts.latin < 2 && scripts.kana + scripts.hangul + scripts.other_letters == 0)
      return false;
    const bool no_space = clean.find_first_of(" \t\r\n") == std::string::npos;
    const auto dot = clean.rfind('.');
    if (no_space && dot != std::string::npos && dot > 0 && clean.size() - dot <= 6)
      return false;
    return true;
  }
  if (IsJapaneseTarget(target_code))
    return scripts.kana == 0 &&
           scripts.latin + scripts.han + scripts.hangul + scripts.other_letters > 0;
  if (IsKoreanTarget(target_code))
    return scripts.hangul == 0 &&
           scripts.latin + scripts.han + scripts.kana + scripts.other_letters > 0;
  if (StartsWithAsciiInsensitive(target_code, "en") ||
      StartsWithAsciiInsensitive(target_code, "english"))
    return scripts.han + scripts.kana + scripts.hangul + scripts.other_letters > 0;
  return true;
}

inline bool TranslationUsableForTarget(const std::string& source,
                                       const std::string& translation,
                                       const std::string& target_code) {
  const auto clean_source = TrimBatchText(source);
  const auto clean_translation = TrimBatchText(translation);
  if (clean_translation.empty() || clean_translation == clean_source) return false;
  if (clean_translation.find("<|") != std::string::npos ||
      clean_translation.find("不要额外解释") != std::string::npos ||
      clean_translation.find("ID|||原文") != std::string::npos)
    return false;
  const auto scripts = CountScripts(clean_translation);
  if (IsChineseTarget(target_code)) {
    // Product names and short code fragments may remain Latin, but a copied English
    // sentence must never be painted as a Chinese translation.
    return scripts.han > 0 && scripts.latin <= scripts.han * 4 + 16;
  }
  if (IsJapaneseTarget(target_code)) return scripts.han + scripts.kana > 0;
  if (IsKoreanTarget(target_code)) return scripts.hangul > 0;
  if (StartsWithAsciiInsensitive(target_code, "en") ||
      StartsWithAsciiInsensitive(target_code, "english")) {
    const auto non_latin = scripts.han + scripts.kana + scripts.hangul + scripts.other_letters;
    return scripts.latin > 0 && non_latin <= scripts.latin * 2 + 8;
  }
  return true;
}

inline std::string BuildBatchSource(const std::vector<OcrBlock>& blocks) {
  std::ostringstream out;
  for (std::size_t i = 0; i < blocks.size(); ++i) {
    out << i << "|||" << blocks[i].text << "\n";
  }
  return out.str();
}

inline std::string EscapeBatchXml(const std::string& text) {
  std::string escaped;
  escaped.reserve(text.size());
  for (const char c : text) {
    if (c == '&') escaped += "&amp;";
    else if (c == '<') escaped += "&lt;";
    else if (c == '>') escaped += "&gt;";
    else escaped.push_back(c);
  }
  return escaped;
}

inline std::string UnescapeBatchXml(std::string text) {
  for (const auto& pair : {std::pair{"&lt;", "<"}, std::pair{"&gt;", ">"},
                           std::pair{"&amp;", "&"}}) {
    for (std::size_t pos = 0; (pos = text.find(pair.first, pos)) != std::string::npos;) {
      text.replace(pos, std::strlen(pair.first), pair.second);
      pos += std::strlen(pair.second);
    }
  }
  return text;
}

inline std::string BuildHunyuanFormattedBatchSource(const std::string& source) {
  std::ostringstream out;
  out << "<source>\n";
  std::istringstream lines(source);
  std::string line;
  while (std::getline(lines, line)) {
    if (line.empty()) continue;
    out << "<sn>" << EscapeBatchXml(line) << "</sn>\n";
  }
  out << "</source>";
  return out.str();
}

inline std::string BuildBatchUserPrompt(const std::string& source, const std::string& source_language,
                                        const std::string& target) {
  if (target == "Simplified Chinese") {
    return "你是屏幕OCR翻译器。逐行检测语言，结合所有行的上下文，把每一行完整翻译成简体中文。"
           "输入格式是 ID|||原文，输出格式必须是 ID|||中文译文，并保留全部ID。\n"
           "示例输入：\n0|||Hello\n1|||Settings\n"
           "示例输出：\n0|||你好\n1|||设置\n"
           "每个ID严格输出一行；不要合并、拆分、省略、解释，不要整句照抄非中文原文。"
           "品牌名、代码和符号可保留。现在翻译正式输入：\n\n" +
           source;
  }
  return "Translate every OCR line from " + source_language + " into " + target +
         " using context across lines. Input is ID|||source. Return every ID exactly once as "
         "ID|||translation, one per line. Do not merge, split, omit, explain, or repeat source.\n\n" +
         source;
}

inline std::vector<std::string> ParseBatchTranslation(const std::string& output,
                                                      std::size_t count) {
  std::vector<std::string> parsed(count);
  std::size_t hits = 0;
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    line = TrimBatchText(line);
    if (line.rfind("```", 0) == 0) continue;
    const auto separator = line.find("|||");
    if (separator == std::string::npos) continue;
    const auto id_text = TrimBatchText(line.substr(0, separator));
    std::size_t used = 0;
    try {
      const auto id = static_cast<std::size_t>(std::stoul(id_text, &used));
      if (used != id_text.size() || id >= count || !parsed[id].empty()) continue;
      parsed[id] = TrimBatchText(line.substr(separator + 3));
      if (!parsed[id].empty()) ++hits;
    } catch (...) {
    }
  }
  // HY-MT formatted-translation profile preserves each ID line inside <sn>.
  std::size_t scan_begin = 0;
  std::size_t scan_end = output.size();
  for (std::size_t cursor = 0;;) {
    const auto target = output.find("<target>", cursor);
    if (target == std::string::npos) break;
    const auto target_end = output.find("</target>", target + 8);
    if (target_end == std::string::npos) break;
    if (output.find("<sn", target + 8) < target_end) {
      scan_begin = target + 8;
      scan_end = target_end;
    }
    cursor = target_end + 9;
  }
  for (std::size_t cursor = scan_begin;;) {
    const auto open = output.find("<sn", cursor);
    if (open == std::string::npos || open >= scan_end) break;
    const auto content = output.find('>', open);
    if (content == std::string::npos || content >= scan_end) break;
    const auto close = output.find("</sn>", content + 1);
    if (close == std::string::npos || close > scan_end) break;
    const auto item = UnescapeBatchXml(TrimBatchText(
        output.substr(content + 1, close - content - 1)));
    const auto separator = item.find("|||");
    if (separator != std::string::npos) {
      const auto id_text = TrimBatchText(item.substr(0, separator));
      std::size_t used = 0;
      try {
        const auto id = static_cast<std::size_t>(std::stoul(id_text, &used));
        if (used == id_text.size() && id < count && parsed[id].empty()) {
          parsed[id] = TrimBatchText(item.substr(separator + 3));
          if (!parsed[id].empty()) ++hits;
        }
      } catch (...) {
      }
    }
    cursor = close + 5;
  }
  // Accept the original marker form for compatibility with cached/in-flight results.
  for (std::size_t i = 0; i < count; ++i) {
    if (!parsed[i].empty()) continue;
    const std::string open = "[[LT:" + std::to_string(i) + "]]";
    const std::string close = "[[/LT:" + std::to_string(i) + "]]";
    const auto begin = output.find(open);
    if (begin == std::string::npos) continue;
    const auto content = begin + open.size();
    const auto end = output.find(close, content);
    if (end == std::string::npos) continue;
    parsed[i] = TrimBatchText(output.substr(content, end - content));
    if (!parsed[i].empty()) ++hits;
  }
  // If the model violates the protocol, leave entries empty. Assigning the entire
  // response to block zero would paint unrelated text at the wrong coordinates.
  (void)hits;
  return parsed;
}

inline std::vector<TranslatedBlock> BindBatchTranslation(
    const std::vector<OcrBlock>& blocks, const std::string& output) {
  return BindTranslations(blocks, ParseBatchTranslation(output, blocks.size()));
}

inline bool BatchTranslationUsable(const std::vector<OcrBlock>& blocks,
                                   const std::string& output,
                                   const std::string& target_code = "zh") {
  if (blocks.empty()) return false;
  const auto parsed = ParseBatchTranslation(output, blocks.size());
  std::size_t present = 0;
  std::size_t changed = 0;
  for (std::size_t i = 0; i < blocks.size(); ++i) {
    if (parsed[i].empty()) continue;
    ++present;
    if (TranslationUsableForTarget(blocks[i].text, parsed[i], target_code)) ++changed;
  }
  const std::size_t need_present = std::max<std::size_t>(1, (blocks.size() * 2 + 2) / 3);
  const std::size_t need_changed = std::max<std::size_t>(1, (blocks.size() + 2) / 3);
  return present >= need_present && changed >= need_changed;
}

inline std::vector<std::pair<std::size_t, std::size_t>> BatchRanges(
    std::size_t count, std::size_t group_size = 4) {
  std::vector<std::pair<std::size_t, std::size_t>> ranges;
  group_size = std::max<std::size_t>(1, group_size);
  for (std::size_t begin = 0; begin < count; begin += group_size)
    ranges.push_back({begin, std::min(count, begin + group_size)});
  return ranges;
}

inline bool BatchFallbackUsable(std::size_t total_groups, std::size_t usable_groups) {
  return total_groups > 0 && usable_groups > 0 && usable_groups * 2 >= total_groups;
}

}  // namespace lenstrans
