#pragma once

#include "lenstrans/translation.hpp"

#include <cctype>
#include <sstream>
#include <string>
#include <vector>

namespace lenstrans {

inline std::string TrimBatchText(std::string text) {
  while (!text.empty() && std::isspace(static_cast<unsigned char>(text.front()))) text.erase(text.begin());
  while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back()))) text.pop_back();
  return text;
}

inline std::string BuildBatchSource(const std::vector<OcrBlock>& blocks) {
  std::ostringstream out;
  for (std::size_t i = 0; i < blocks.size(); ++i) {
    out << i << "|||" << blocks[i].text << "\n";
  }
  return out.str();
}

inline std::string BuildBatchUserPrompt(const std::string& source, const std::string& source_language,
                                        const std::string& target) {
  if (target == "Simplified Chinese") {
    return "任务：把以下全部OCR文本从" + source_language +
           "结合上下文翻译成简体中文。输入可能包含多种语言；绝对不能照抄非中文原文。"
           "每行格式是 ID|||原文，输出必须是 ID|||中文译文，并保留全部ID。\n"
           "示例输入：\n0|||Hello\n1|||Settings\n"
           "示例输出：\n0|||你好\n1|||设置\n"
           "现在翻译下面的正式输入。每个ID严格输出一行；不要合并、拆分、省略、解释或输出英文原文：\n\n" +
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
  // Never shift text onto the wrong coordinates when a model violates the protocol.
  if (hits == 0 && count > 0) parsed[0] = TrimBatchText(output);
  return parsed;
}

inline std::vector<TranslatedBlock> BindBatchTranslation(
    const std::vector<OcrBlock>& blocks, const std::string& output) {
  return BindTranslations(blocks, ParseBatchTranslation(output, blocks.size()));
}

inline bool BatchTranslationUsable(const std::vector<OcrBlock>& blocks,
                                   const std::string& output) {
  if (blocks.empty()) return false;
  const auto parsed = ParseBatchTranslation(output, blocks.size());
  std::size_t present = 0;
  std::size_t changed = 0;
  for (std::size_t i = 0; i < blocks.size(); ++i) {
    if (parsed[i].empty()) continue;
    ++present;
    if (TrimBatchText(parsed[i]) != TrimBatchText(blocks[i].text)) ++changed;
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
