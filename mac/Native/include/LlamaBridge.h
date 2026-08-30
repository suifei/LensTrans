#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 1 when this binary was linked against third_party llama.cpp (Metal).
int lenstrans_llama_available(void);

typedef struct LenstransLlamaEngine LenstransLlamaEngine;

LenstransLlamaEngine *lenstrans_llama_create(const char *model_path);
void lenstrans_llama_destroy(LenstransLlamaEngine *eng);

/// Model file exists (or already loaded).
int lenstrans_llama_ready(const LenstransLlamaEngine *eng);

int lenstrans_llama_load(LenstransLlamaEngine *eng);
void lenstrans_llama_unload(LenstransLlamaEngine *eng);

/// Run greedy completion on a ChatML-wrapped prompt. Returns 0 on success.
/// `max_new_tokens` ≤ 0 defaults to 96.
int lenstrans_llama_translate(LenstransLlamaEngine *eng,
                              const char *prompt,
                              int max_new_tokens,
                              char *out_buf,
                              int out_cap,
                              int *latency_ms,
                              char *err_buf,
                              int err_cap);

#ifdef __cplusplus
}
#endif
