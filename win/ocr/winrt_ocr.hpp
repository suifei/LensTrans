#pragma once

#include "lenstrans/ocr_block.hpp"
#include "win/capture/capture.hpp"

#include <string>
#include <vector>

namespace lenstrans::win {

struct OcrRoi {
  int x = 0, y = 0, w = 0, h = 0;
};

// Windows.Media.OCR on (union of ROIs) or full frame if rois empty.
std::vector<lenstrans::OcrBlock> RecognizeOcr(const BgraFrame& frame,
                                              const std::vector<OcrRoi>& rois,
                                              std::string& err);

void SampleColorAndVariance(const BgraFrame& frame, OcrBlock& block);

}  // namespace lenstrans::win
