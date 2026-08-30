#include "lenstrans/engine.hpp"
#include "lenstrans/model_meta.hpp"
#include "lenstrans/paths.hpp"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#pragma comment(lib, "psapi.lib")
#endif

#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

static std::string ModelPath() {
  const std::string p = lenstrans::FindDefaultModelPath();
  return lenstrans::FileExists(p) ? p : std::string{};
}

static std::string OutPath(const char* name) {
  return lenstrans::JoinPath(lenstrans::EvalOutDir(), name);
}

#ifdef _WIN32
static double WorkingSetMiB() {
  PROCESS_MEMORY_COUNTERS_EX c{};
  c.cb = sizeof(c);
  if (!GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&c),
                            sizeof(c))) {
    return 0;
  }
  return static_cast<double>(c.WorkingSetSize) / (1024.0 * 1024.0);
}
#endif

static bool HasCjk(const std::string& s) {
  for (unsigned char c : s)
    if (c >= 0x80) return true;
  return false;
}

static int WordCount(const char* s) {
  int n = 0;
  bool in = false;
  for (; *s; ++s) {
    if (*s == ' ') {
      in = false;
    } else if (!in) {
      in = true;
      ++n;
    }
  }
  return n;
}

static int RunOne(lenstrans::IEngine* eng, bool quality, const char* src, const char* tag,
                  std::string& line, double& ws, lenstrans::TranslateResult* saved) {
  lenstrans::TranslateRequest req;
  req.text = src;
  req.src_lang = "en";
  req.tgt_lang = "zh";
  req.quality = quality;
  const auto r = eng->Translate(req);
  if (saved) *saved = r;
#ifdef _WIN32
  ws = WorkingSetMiB();
#else
  ws = 0;
#endif
  char buf[2048];
  std::snprintf(buf, sizeof(buf),
                "%s text=\"%s\" err=\"%s\" first_ms=%d total_ms=%d beam=%d ws_mib=%.1f", tag,
                r.text.c_str(), r.error.c_str(), r.first_token_ms, r.latency_ms, r.beam_width, ws);
  line = buf;
  std::printf("%s\n", buf);
  if (!r.error.empty() || r.text.empty() || !HasCjk(r.text)) return 1;
  if (quality && r.beam_width != 2) return 1;
  if (r.first_token_ms > 800) return 1;
  if (ws > 550.0) return 1;
  return 0;
}

struct QualityRow {
  const char* kind;
  const char* text;
};

static int RunQualitySuite(lenstrans::IEngine* eng, const char* outp, const char* title,
                           const QualityRow* rows, int n) {
  std::ofstream f(outp, std::ios::binary);
  if (f) {
    f << title << "\n\n"
      << "- model: qwen2.5-0.5b-instruct-q4_k_m.gguf\n"
      << "- beam: 1 (greedy)\n"
      << "- note: record output as-is. Literal or wrong translations are expected on 0.5B.\n\n"
      << "| # | kind | words | first_ms | total_ms | ws_mib | src | hyp |\n"
      << "| ---: | --- | ---: | ---: | ---: | ---: | --- | --- |\n";
  }
  int engine_fail = 0;
  double max_ws = 0;
  for (int i = 0; i < n; ++i) {
    if (std::strcmp(rows[i].kind, "long40") == 0 && WordCount(rows[i].text) < 40) {
      std::fprintf(stderr, "%s: row %d has %d words want >=40\n", outp, i + 1,
                   WordCount(rows[i].text));
    }
    lenstrans::TranslateResult r;
    double ws = 0;
    std::string line;
    const int e = RunOne(eng, false, rows[i].text, "q", line, ws, &r);
    if (ws > max_ws) max_ws = ws;
    if (e && (r.error.size() || r.text.empty())) ++engine_fail;
    if (f) {
      auto esc = [](const std::string& s) {
        std::string o;
        for (char c : s) {
          if (c == '|')
            o += "/";
          else if (c == '\n')
            o += " ";
          else
            o += c;
        }
        return o;
      };
      f << "| " << (i + 1) << " | " << rows[i].kind << " | " << WordCount(rows[i].text) << " | "
        << r.first_token_ms << " | " << r.latency_ms << " | " << ws << " | "
        << esc(rows[i].text) << " | " << esc(r.text.empty() ? r.error : r.text) << " |\n";
    }
  }
  if (f) {
    f << "\n- engine_hard_fail_rows: " << engine_fail << "\n"
      << "- max_ws_mib: " << max_ws << "\n"
      << "- ws_le_550: " << (max_ws <= 550.0 ? "yes" : "no") << "\n"
      << "- this is Goal test evidence, not W1 acceptance.\n";
  }
  std::printf("%s wrote %s engine_hard_fail=%d max_ws=%.1f\n", title, outp, engine_fail, max_ws);
  return engine_fail ? 1 : 0;
}

static std::vector<std::string> ReadLines(const char* path) {
  std::vector<std::string> lines;
  std::ifstream in(path);
  std::string line;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (!line.empty()) lines.push_back(line);
  }
  return lines;
}

static int RunFlores50(lenstrans::IEngine* eng) {
  const std::string enPath = OutPath("flores50-en.txt");
  const std::string refPath = OutPath("flores50-ref.txt");
  const std::string outp = OutPath("flores50.md");
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  const auto en = ReadLines(enPath.c_str());
  const auto refs = ReadLines(refPath.c_str());
  if (en.empty()) {
    std::fprintf(stderr, "flores50: missing or empty %s\n", enPath.c_str());
    return 1;
  }
  const int n = static_cast<int>(en.size());
  auto esc = [](const std::string& s) {
    std::string o;
    for (char c : s) {
      if (c == '|')
        o += "/";
      else if (c == '\n')
        o += " ";
      else
        o += c;
    }
    return o;
  };
  std::ofstream f(outp.c_str(), std::ios::binary);
      << "- model: qwen2.5-0.5b-instruct-q4_k_m.gguf\n"
      << "- source: FLORES-200 dev eng_Latn / zho_Hans (first " << n << " lines)\n"
      << "- beam: 1 (greedy)\n"
      << "- note: record output as-is; not W1 acceptance; no COMET/BLEU.\n\n"
      << "| # | words | first_ms | total_ms | ws_mib | src | ref | hyp |\n"
      << "| ---: | ---: | ---: | ---: | ---: | --- | --- | --- |\n";
  }
  int engine_fail = 0;
  double max_ws = 0;
  for (int i = 0; i < n; ++i) {
    lenstrans::TranslateResult r;
    double ws = 0;
    std::string line;
    const int e = RunOne(eng, false, en[static_cast<size_t>(i)].c_str(), "q", line, ws, &r);
    if (ws > max_ws) max_ws = ws;
    if (e && (r.error.size() || r.text.empty())) ++engine_fail;
    const std::string ref = i < static_cast<int>(refs.size()) ? refs[static_cast<size_t>(i)] : "";
    if (f) {
      f << "| " << (i + 1) << " | " << WordCount(en[static_cast<size_t>(i)].c_str()) << " | "
        << r.first_token_ms << " | " << r.latency_ms << " | " << ws << " | "
        << esc(en[static_cast<size_t>(i)]) << " | " << esc(ref) << " | "
        << esc(r.text.empty() ? r.error : r.text) << " |\n";
    }
  }
  if (f) {
    f << "\n- sentences: " << n << "\n"
      << "- engine_hard_fail_rows: " << engine_fail << "\n"
      << "- max_ws_mib: " << max_ws << "\n"
      << "- ws_le_550: " << (max_ws <= 550.0 ? "yes" : "no") << "\n"
      << "- this is Goal test evidence, not W1 acceptance.\n";
  }
  std::printf("flores50 wrote %s sentences=%d engine_hard_fail=%d max_ws=%.1f\n", outp, n,
              engine_fail, max_ws);
  return engine_fail ? 1 : 0;
}

static int RunQuality10(lenstrans::IEngine* eng) {
  static const QualityRow kRows[] = {
      {"ui", "Hello"},
      {"ui", "Thank you"},
      {"ui", "Settings"},
      {"ui", "Cancel"},
      {"ui", "Save"},
      {"ui", "Click here"},
      {"ui", "Please wait"},
      {"idiom", "It's raining cats and dogs."},
      {"ui", "How are you?"},
      {"long40",
       "The settings dialog lets you choose a local engine or an empty cloud endpoint, and you "
       "should click Save after you change the target language so the overlay can restore boxes "
       "on the next start without asking you to place them again."},
  };
  const std::string out = OutPath("quality-10.md");
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  return RunQualitySuite(eng, out.c_str(), "# quality-10 greedy EN-ZH (not FLORES, not W1)", kRows,
                         static_cast<int>(sizeof(kRows) / sizeof(kRows[0])));
}

static int RunQuality30(lenstrans::IEngine* eng) {
  static const QualityRow kRows[] = {
      {"ui", "Hello"},
      {"ui", "Thank you"},
      {"ui", "Settings"},
      {"ui", "Cancel"},
      {"ui", "Save"},
      {"ui", "Click here"},
      {"ui", "Please wait"},
      {"idiom", "It's raining cats and dogs."},
      {"ui", "How are you?"},
      {"ui", "OK"},
      {"ui", "Back"},
      {"ui", "Next"},
      {"ui", "Close"},
      {"ui", "Open"},
      {"ui", "Delete"},
      {"ui", "Edit"},
      {"ui", "Search"},
      {"ui", "Loading..."},
      {"ui", "Retry"},
      {"ui", "Apply"},
      {"idiom", "Break a leg!"},
      {"idiom", "Piece of cake."},
      {"idiom", "Once in a blue moon."},
      {"idiom", "It's on the house."},
      {"idiom", "Bite the bullet."},
      {"long40",
       "The settings dialog lets you choose a local engine or an empty cloud endpoint, and you "
       "should click Save after you change the target language so the overlay can restore boxes "
       "on the next start without asking you to place them again."},
      {"long40",
       "When you install the application for the first time, the onboarding wizard walks you "
       "through selecting a capture region, granting screen recording permission, and confirming "
       "that the local translation engine can load the bundled model without downloading anything "
       "from the network."},
      {"long40",
       "If the overlay detects that the same English paragraph has remained unchanged for two "
       "consecutive frames, it will skip retranslation and reuse the cached Chinese text so that "
       "scrolling and minor flicker do not trigger unnecessary GPU or CPU work on low-end "
       "laptops."},
      {"long40",
       "The product requirements document states that users in the European Union and the United "
       "Kingdom must be able to run the tool entirely offline after the initial package is "
       "installed, which is why every release bundles the quantized model and avoids calling cloud "
       "APIs during normal translation."},
      {"long40",
       "Before shipping a build to testers, verify that hotkeys for toggling immersion mode, "
       "pausing capture, opening settings, and quitting the application all register successfully "
       "and unregister cleanly when the tray icon is destroyed during a full automated smoke test "
       "run."},
  };
  const std::string out = OutPath("quality-30.md");
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  return RunQualitySuite(eng, out.c_str(), "# quality-30 greedy EN-ZH (not FLORES, not W1)", kRows,
                         static_cast<int>(sizeof(kRows) / sizeof(kRows[0])));
}

int main(int argc, char** argv) {
#ifndef LENSTRANS_WITH_LLAMA
  std::fprintf(stderr, "test_llama: LENSTRANS_WITH_LLAMA not defined\n");
  return 1;
#else
  const bool q10 = argc > 1 && std::strcmp(argv[1], "--quality-10") == 0;
  const bool q30 = argc > 1 && std::strcmp(argv[1], "--quality-30") == 0;
  const bool f50 = argc > 1 && std::strcmp(argv[1], "--flores50") == 0;
  const std::string path = ModelPath();
  if (path.empty()) {
    std::fprintf(stderr, "test_llama: GGUF missing\n");
    return 1;
  }
  auto eng = lenstrans::MakeLocalEngine(path, "");
  if (!eng || !eng->Ready()) {
    std::fprintf(stderr, "test_llama: engine not ready path=%s\n", path.c_str());
    return 1;
  }
  if (q10) return RunQuality10(eng.get());
  if (q30) return RunQuality30(eng.get());
  if (f50) return RunFlores50(eng.get());

  std::string greedy, beam;
  double ws_g = 0, ws_b = 0;
  const int e1 = RunOne(eng.get(), false, "It's on the house.", "greedy", greedy, ws_g, nullptr);
  const int e2 = RunOne(eng.get(), true, "It's on the house.", "beam2", beam, ws_b, nullptr);
  const std::string outp = OutPath("beam2-smoke.md");
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  std::ofstream f(outp.c_str(), std::ios::binary);
  if (f) {
    f << "# beam=2 smoke (2026-08-30, in-process llama.cpp b10688)\n\n"
      << "- model: qwen2.5-0.5b-instruct-q4_k_m.gguf\n"
      << "- prompt: It's on the house. → zh\n"
      << "- " << greedy << "\n"
      << "- " << beam << "\n"
      << "- greedy_exit=" << e1 << " beam2_exit=" << e2 << "\n"
      << "- note: quality is literal; not FLORES / not W1.\n";
  }
  if (e1 || e2) return 1;
  std::printf("test_llama: ok\n");
  return 0;
#endif
}
