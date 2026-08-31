#include "lenstrans/dispatch.hpp"
#include "lenstrans/pipeline.hpp"

#include <exception>

namespace lenstrans {

Pipeline::Pipeline(PipelineServices services, PipelineOptions options)
    : services_(services), options_(std::move(options)) {}

void Pipeline::Cancel() {
  token_.Cancel();
  state_ = PipelineState::Cancelled;
}

void Pipeline::Pause() {
  if (state_ != PipelineState::Cancelled && state_ != PipelineState::Failed)
    state_ = PipelineState::Paused;
}

void Pipeline::Resume() {
  if (state_ == PipelineState::Paused) state_ = PipelineState::Idle;
}

void Pipeline::Reset() {
  state_ = PipelineState::Idle;
  token_ = CancellationToken{};
  previous_.clear();
  has_previous_ = false;
}

PipelineResult Pipeline::Step() {
  PipelineResult result;
  result.state = state_;
  if (state_ == PipelineState::Paused || state_ == PipelineState::Cancelled ||
      state_ == PipelineState::Failed)
    return result;
  if (!services_.capture || !services_.ocr) {
    state_ = PipelineState::Failed;
    result.state = state_;
    result.error = "capture and OCR providers are required";
    return result;
  }

  try {
    state_ = PipelineState::Capturing;
    if (token_.IsCancelled()) {
      state_ = PipelineState::Cancelled;
      result.cancelled = true;
      result.state = state_;
      return result;
    }
    CapturedFrame frame;
    if (!services_.capture->Capture(frame, token_) || !frame.IsValid()) {
      state_ = PipelineState::Failed;
      result.state = state_;
      result.error = "capture failed";
      return result;
    }
    state_ = PipelineState::Recognizing;
    std::vector<OcrBlock> recognized;
    if (!services_.ocr->Recognize(frame, token_, recognized)) {
      state_ = PipelineState::Failed;
      result.state = state_;
      result.error = "OCR failed";
      return result;
    }
    const auto blocks = NormalizeOcrBlocks(recognized, frame.width, frame.height, options_.merge);
    if (token_.IsCancelled()) {
      state_ = PipelineState::Cancelled;
      result.cancelled = true;
      result.state = state_;
      return result;
    }
    result.frame = frame;
    if (!has_previous_) {
      previous_ = blocks;
      has_previous_ = true;
      state_ = PipelineState::Watching;
      result.state = state_;
      return result;
    }
    if (!SameBlocks(previous_, blocks)) {
      previous_ = blocks;
      state_ = PipelineState::Watching;
      result.state = state_;
      return result;
    }
    result.stabilized = true;
    state_ = PipelineState::Translating;
    std::vector<TranslatedBlock> translated;
    translated.reserve(blocks.size());
    for (const auto& block : blocks) {
      if (token_.IsCancelled()) {
        state_ = PipelineState::Cancelled;
        result.cancelled = true;
        result.state = state_;
        return result;
      }
      TranslateRequest request;
      request.text = block.text;
      request.src_lang = options_.settings.src_lang;
      request.tgt_lang = options_.settings.tgt_lang;
      request.quality = options_.settings.quality;
      request.presentation.lock = options_.settings.render;
      request.presentation.contrast = options_.settings.contrast;
      request.presentation.sticker_alpha = options_.settings.sticker_alpha;
      request.presentation.font_scale = options_.settings.font_scale;
      const auto translation = DispatchTranslate(options_.settings, services_.local, services_.cloud,
                                                 services_.cache, request);
      translated.push_back({block, translation.text, translation.error, translation.from_cache});
    }
    state_ = PipelineState::Presenting;
    LayoutOptions layout_options;
    layout_options.frame_width = frame.width;
    layout_options.frame_height = frame.height;
    layout_options.target_width = options_.target_width > 0 ? options_.target_width : frame.width;
    layout_options.target_height = options_.target_height > 0 ? options_.target_height : frame.height;
    layout_options.presentation.lock = options_.settings.render;
    layout_options.presentation.contrast = options_.settings.contrast;
    layout_options.presentation.sticker_alpha = options_.settings.sticker_alpha;
    layout_options.presentation.font_scale = options_.settings.font_scale;
    const auto layout = BuildPresentLayout(translated, layout_options);
    if (services_.presenter && !services_.presenter->Present(
                                  {frame.width, frame.height, translated, layout}, token_)) {
      state_ = PipelineState::Failed;
      result.state = state_;
      result.error = "presentation failed";
      return result;
    }
    state_ = PipelineState::Watching;
    result.state = state_;
    result.rendered = services_.presenter != nullptr;
    result.blocks = std::move(translated);
    result.layout = layout;
    return result;
  } catch (const std::exception& e) {
    state_ = PipelineState::Failed;
    result.state = state_;
    result.error = e.what();
    return result;
  } catch (...) {
    state_ = PipelineState::Failed;
    result.state = state_;
    result.error = "pipeline provider failed";
    return result;
  }
}

}  // namespace lenstrans
