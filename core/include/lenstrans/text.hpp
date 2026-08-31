#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace lenstrans {

inline bool IsUtf8Continuation(unsigned char c) { return (c & 0xc0u) == 0x80u; }

// Returns the next byte offset. Invalid UTF-8 consumes one byte, never half a sequence.
inline std::size_t Utf8Next(const std::string& text, std::size_t offset) {
  if (offset >= text.size()) return offset;
  const unsigned char c = static_cast<unsigned char>(text[offset]);
  std::size_t length = 1;
  if (c >= 0xc2u && c <= 0xdfu) length = 2;
  if (c >= 0xe0u && c <= 0xefu) length = 3;
  if (c >= 0xf0u && c <= 0xf4u) length = 4;
  if (length == 1 || offset + length > text.size()) return offset + 1;
  for (std::size_t i = 1; i < length; ++i) {
    if (!IsUtf8Continuation(static_cast<unsigned char>(text[offset + i]))) return offset + 1;
  }
  if ((c == 0xe0u && static_cast<unsigned char>(text[offset + 1]) < 0xa0u) ||
      (c == 0xedu && static_cast<unsigned char>(text[offset + 1]) >= 0xa0u) ||
      (c == 0xf0u && static_cast<unsigned char>(text[offset + 1]) < 0x90u) ||
      (c == 0xf4u && static_cast<unsigned char>(text[offset + 1]) > 0x8fu))
    return offset + 1;
  return offset + length;
}

inline std::size_t Utf8CodepointCount(const std::string& text) {
  std::size_t count = 0;
  for (std::size_t i = 0; i < text.size();) {
    i = Utf8Next(text, i);
    ++count;
  }
  return count;
}

inline std::uint32_t Utf8CodepointAt(const std::string& text, std::size_t offset) {
  if (offset >= text.size()) return 0;
  const auto c0 = static_cast<unsigned char>(text[offset]);
  const auto next = Utf8Next(text, offset);
  if (next == offset + 1) return c0;
  if (next == offset + 2)
    return ((c0 & 0x1fu) << 6) |
           (static_cast<unsigned char>(text[offset + 1]) & 0x3fu);
  if (next == offset + 3)
    return ((c0 & 0x0fu) << 12) |
           ((static_cast<unsigned char>(text[offset + 1]) & 0x3fu) << 6) |
           (static_cast<unsigned char>(text[offset + 2]) & 0x3fu);
  return ((c0 & 0x07u) << 18) |
         ((static_cast<unsigned char>(text[offset + 1]) & 0x3fu) << 12) |
         ((static_cast<unsigned char>(text[offset + 2]) & 0x3fu) << 6) |
         (static_cast<unsigned char>(text[offset + 3]) & 0x3fu);
}

inline std::vector<std::string> WrapUtf8(const std::string& text, int columns) {
  columns = std::max(1, columns);
  std::vector<std::string> lines;
  std::string line;
  int used = 0;
  auto flush = [&] {
    lines.push_back(line);
    line.clear();
    used = 0;
  };
  for (std::size_t i = 0; i < text.size();) {
    const std::size_t next = Utf8Next(text, i);
    if (text[i] == '\n') {
      flush();
      i = next;
      continue;
    }
    if (text[i] == ' ' || text[i] == '\t' || text[i] == '\r') {
      if (!line.empty() && used + 1 <= columns) {
        line.push_back(' ');
        ++used;
      }
      i = next;
      continue;
    }
    const int width = static_cast<unsigned char>(text[i]) < 0x80u ? 1 : 2;
    if (!line.empty() && used + width > columns) flush();
    line.append(text, i, next - i);
    used += width;
    i = next;
  }
  if (!line.empty() || lines.empty()) flush();
  return lines;
}

}  // namespace lenstrans
