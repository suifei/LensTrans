#pragma once

#include "lenstrans/ocr_block.hpp"

#include <string>
#include <vector>

namespace lenstrans {

// A translation is always carried with its source block. Parallel vectors are only an adapter concern.
struct TranslatedBlock {
  OcrBlock source;
  std::string translation;
  std::string error;
  bool from_cache = false;
};

inline std::vector<TranslatedBlock> BindTranslations(const std::vector<OcrBlock>& blocks,
                                                     const std::vector<std::string>& translations) {
  std::vector<TranslatedBlock> out;
  out.reserve(blocks.size());
  for (std::size_t i = 0; i < blocks.size(); ++i) {
    TranslatedBlock bound;
    bound.source = blocks[i];
    if (i < translations.size()) bound.translation = translations[i];
    out.push_back(std::move(bound));
  }
  return out;
}

}  // namespace lenstrans
