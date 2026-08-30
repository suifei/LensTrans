#pragma once

#include <array>
#include <cstdint>
#include <cstring>
#include <string>

namespace lenstrans {

// Compact SHA-1 (FIPS 180-1). Used only for cache keys, not security.
inline std::array<std::uint8_t, 20> Sha1(const void* data, std::size_t len) {
  auto rol = [](std::uint32_t v, int s) { return (v << s) | (v >> (32 - s)); };
  std::uint32_t h0 = 0x67452301u, h1 = 0xEFCDAB89u, h2 = 0x98BADCFEu, h3 = 0x10325476u,
                h4 = 0xC3D2E1F0u;
  const auto* bytes = static_cast<const std::uint8_t*>(data);
  const std::uint64_t bitlen = static_cast<std::uint64_t>(len) * 8;
  std::uint8_t block[64];
  std::size_t off = 0;
  auto process = [&](const std::uint8_t* b) {
    std::uint32_t w[80];
    for (int i = 0; i < 16; ++i) {
      w[i] = (std::uint32_t(b[i * 4]) << 24) | (std::uint32_t(b[i * 4 + 1]) << 16) |
             (std::uint32_t(b[i * 4 + 2]) << 8) | std::uint32_t(b[i * 4 + 3]);
    }
    for (int i = 16; i < 80; ++i) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    std::uint32_t a = h0, c = h2, d = h3, e = h4, bb = h1;
    for (int i = 0; i < 80; ++i) {
      std::uint32_t f, k;
      if (i < 20) {
        f = (bb & c) | ((~bb) & d);
        k = 0x5A827999u;
      } else if (i < 40) {
        f = bb ^ c ^ d;
        k = 0x6ED9EBA1u;
      } else if (i < 60) {
        f = (bb & c) | (bb & d) | (c & d);
        k = 0x8F1BBCDCu;
      } else {
        f = bb ^ c ^ d;
        k = 0xCA62C1D6u;
      }
      const std::uint32_t temp = rol(a, 5) + f + e + k + w[i];
      e = d;
      d = c;
      c = rol(bb, 30);
      bb = a;
      a = temp;
    }
    h0 += a;
    h1 += bb;
    h2 += c;
    h3 += d;
    h4 += e;
  };
  while (off + 64 <= len) {
    process(bytes + off);
    off += 64;
  }
  const std::size_t rem = len - off;
  std::memcpy(block, bytes + off, rem);
  block[rem] = 0x80;
  if (rem >= 56) {
    std::memset(block + rem + 1, 0, 63 - rem);
    process(block);
    std::memset(block, 0, 56);
  } else {
    std::memset(block + rem + 1, 0, 55 - rem);
  }
  for (int i = 0; i < 8; ++i) block[63 - i] = static_cast<std::uint8_t>(bitlen >> (8 * i));
  process(block);
  std::array<std::uint8_t, 20> out{};
  const std::uint32_t hs[5] = {h0, h1, h2, h3, h4};
  for (int i = 0; i < 5; ++i) {
    out[i * 4] = static_cast<std::uint8_t>(hs[i] >> 24);
    out[i * 4 + 1] = static_cast<std::uint8_t>(hs[i] >> 16);
    out[i * 4 + 2] = static_cast<std::uint8_t>(hs[i] >> 8);
    out[i * 4 + 3] = static_cast<std::uint8_t>(hs[i]);
  }
  return out;
}

inline std::string Sha1Hex(const std::string& s) {
  const auto d = Sha1(s.data(), s.size());
  static const char* kHex = "0123456789abcdef";
  std::string hex(40, '0');
  for (int i = 0; i < 20; ++i) {
    hex[i * 2] = kHex[d[i] >> 4];
    hex[i * 2 + 1] = kHex[d[i] & 0xf];
  }
  return hex;
}

}  // namespace lenstrans
