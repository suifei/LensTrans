#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

namespace lenstrans {

struct FrameDiff {
  int cols = 0;
  int rows = 0;
  int block = 8;
  std::vector<std::uint8_t> changed;  // rows*cols, 1 = dirty
  int changed_count = 0;
};

// 1/4 downsample (every 4th pixel, luma), then 8×8 block SSD.
// BGRA, origin top-left. stride_bytes = width * 4 if packed.
inline FrameDiff DiffFrames(const std::uint8_t* prev, const std::uint8_t* curr, int w, int h,
                            int stride_bytes, int ssd_threshold = 1600) {
  FrameDiff out;
  if (!prev || !curr || w < 4 || h < 4) return out;
  const int dw = w / 4;
  const int dh = h / 4;
  if (dw < 1 || dh < 1) return out;
  std::vector<std::uint8_t> a(static_cast<std::size_t>(dw) * dh);
  std::vector<std::uint8_t> b(static_cast<std::size_t>(dw) * dh);
  for (int y = 0; y < dh; ++y) {
    const std::uint8_t* pr = prev + static_cast<std::size_t>(y * 4) * stride_bytes;
    const std::uint8_t* cr = curr + static_cast<std::size_t>(y * 4) * stride_bytes;
    for (int x = 0; x < dw; ++x) {
      const int sx = x * 4 * 4;
      const int pb = pr[sx], pg = pr[sx + 1], prr = pr[sx + 2];
      const int cb = cr[sx], cg = cr[sx + 1], crr = cr[sx + 2];
      a[static_cast<std::size_t>(y) * dw + x] =
          static_cast<std::uint8_t>((pb + pg + prr) / 3);
      b[static_cast<std::size_t>(y) * dw + x] =
          static_cast<std::uint8_t>((cb + cg + crr) / 3);
    }
  }
  out.cols = (dw + 7) / 8;
  out.rows = (dh + 7) / 8;
  out.changed.assign(static_cast<std::size_t>(out.cols) * out.rows, 0);
  for (int by = 0; by < out.rows; ++by) {
    for (int bx = 0; bx < out.cols; ++bx) {
      int ssd = 0;
      for (int iy = 0; iy < 8; ++iy) {
        const int y = by * 8 + iy;
        if (y >= dh) break;
        for (int ix = 0; ix < 8; ++ix) {
          const int x = bx * 8 + ix;
          if (x >= dw) break;
          const int d = int(a[static_cast<std::size_t>(y) * dw + x]) -
                        int(b[static_cast<std::size_t>(y) * dw + x]);
          ssd += d * d;
        }
      }
      if (ssd >= ssd_threshold) {
        out.changed[static_cast<std::size_t>(by) * out.cols + bx] = 1;
        ++out.changed_count;
      }
    }
  }
  return out;
}

inline void UnionChangedAndDilated(const FrameDiff& diff, const std::vector<int>& last_blocks,
                                   int dilate, std::vector<std::uint8_t>& mask) {
  mask.assign(static_cast<std::size_t>(diff.cols) * diff.rows, 0);
  auto mark = [&](int x, int y) {
    if (x < 0 || y < 0 || x >= diff.cols || y >= diff.rows) return;
    mask[static_cast<std::size_t>(y) * diff.cols + x] = 1;
  };
  for (int i = 0; i < diff.rows * diff.cols; ++i) {
    if (diff.changed[static_cast<std::size_t>(i)]) {
      const int x = i % diff.cols;
      const int y = i / diff.cols;
      for (int dy = -dilate; dy <= dilate; ++dy)
        for (int dx = -dilate; dx <= dilate; ++dx) mark(x + dx, y + dy);
    }
  }
  for (int idx : last_blocks) {
    if (idx < 0 || idx >= diff.cols * diff.rows) continue;
    const int x = idx % diff.cols;
    const int y = idx / diff.cols;
    for (int dy = -dilate; dy <= dilate; ++dy)
      for (int dx = -dilate; dx <= dilate; ++dx) mark(x + dx, y + dy);
  }
}

// Map a capture-space bbox (pixels) onto 8×8 blocks of the 1/4 grid.
inline void BlocksForBBox(int frame_w, int frame_h, float x, float y, float w, float h, int cols,
                          int rows, std::vector<int>& out) {
  const int x0 = std::max(0, static_cast<int>(x) / 4 / 8);
  const int y0 = std::max(0, static_cast<int>(y) / 4 / 8);
  const int x1 = std::min(cols - 1, static_cast<int>(x + w) / 4 / 8);
  const int y1 = std::min(rows - 1, static_cast<int>(y + h) / 4 / 8);
  (void)frame_w;
  (void)frame_h;
  for (int by = y0; by <= y1; ++by)
    for (int bx = x0; bx <= x1; ++bx) out.push_back(by * cols + bx);
}

}  // namespace lenstrans
