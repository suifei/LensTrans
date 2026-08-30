#pragma once

#include <string>

namespace lenstrans {

// PRD cloud: resolve 3s / connect 3s / send 5s / receive 15s.
struct CloudTimeoutsMs {
  int resolve = 3000;
  int connect = 3000;
  int send = 5000;
  int receive = 15000;
};

inline bool ShouldRetryCloud(const std::string& error) {
  if (error.empty()) return false;
  if (error.find("not configured") != std::string::npos) return false;
  if (error.find("bad base") != std::string::npos) return false;
  if (error.find("privacy") != std::string::npos) return false;
  return error.find("timeout") != std::string::npos || error.find("send") != std::string::npos ||
         error.find("connect") != std::string::npos || error.find("empty") != std::string::npos ||
         error.find("http") != std::string::npos;
}

inline std::string ExtractJsonContent(const std::string& json) {
  const auto p = json.find("\"content\"");
  if (p == std::string::npos) return {};
  const auto colon = json.find(':', p + 9);
  if (colon == std::string::npos) return {};
  const auto start = json.find('"', colon + 1);
  if (start == std::string::npos) return {};
  std::string out;
  for (std::size_t i = start + 1; i < json.size(); ++i) {
    if (json[i] == '\\' && i + 1 < json.size()) {
      const char n = json[i + 1];
      if (n == 'n')
        out += '\n';
      else if (n == '"')
        out += '"';
      else
        out += n;
      ++i;
      continue;
    }
    if (json[i] == '"') break;
    out += json[i];
  }
  return out;
}

// OpenAI-compatible SSE or one-shot JSON body. No network.
inline std::string ParseChatCompletionBody(const std::string& body) {
  std::string out;
  std::string line;
  for (std::size_t i = 0, start = 0; i <= body.size(); ++i) {
    if (i < body.size() && body[i] != '\n') continue;
    line = body.substr(start, i - start);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    start = i + 1;
    if (line.rfind("data:", 0) == 0) {
      auto json = line.substr(5);
      while (!json.empty() && json.front() == ' ') json.erase(json.begin());
      if (json.find("[DONE]") != std::string::npos) break;
      out += ExtractJsonContent(json);
    } else if (line.find("\"content\"") != std::string::npos) {
      out += ExtractJsonContent(line);
    }
  }
  if (out.empty()) out = ExtractJsonContent(body);
  return out;
}

inline std::string BuildChatCompletionsJson(const std::string& model, const std::string& prompt,
                                            bool stream) {
  auto esc = [](const std::string& s) {
    std::string o;
    for (unsigned char c : s) {
      if (c == '"')
        o += "\\\"";
      else if (c == '\\')
        o += "\\\\";
      else if (c == '\n')
        o += "\\n";
      else
        o += static_cast<char>(c);
    }
    return o;
  };
  return std::string("{\"model\":\"") + esc(model) + "\",\"stream\":" + (stream ? "true" : "false") +
         ",\"messages\":[{\"role\":\"user\",\"content\":\"" + esc(prompt) + "\"}]}";
}

}  // namespace lenstrans
