#include "voice_denoiser.h"
#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>
#include <thread>
#include <vector>
using dawnmesh::VoiceDenoiser;
void verify_rate(int rate) {
  VoiceDenoiser denoiser(rate);
  const int frames = rate / 100;
  std::array<float, 480> pcm{};
  for (int i = 0; i < frames; ++i) pcm[i] = i - 240.5f;
  const auto original = pcm;
  assert(denoiser.processFloat(pcm.data(), frames, 0));
  assert(pcm == original);
  assert(!denoiser.processFloat(pcm.data(), frames - 1, 1));
  assert(!denoiser.processFloat(pcm.data(), frames, 3));
  for (int level : {1, 2, 0, 2}) {
    double input_power = 0, output_power = 0;
    uint32_t random = 42;
    for (int block = 0; block < 240; ++block) {
      for (int i = 0; i < frames; ++i) {
        const double time = double(block * frames + i) / rate;
        random = random * 1664525u + 1013904223u;
        const float noise = (float(random >> 8) / 16777216.f - 0.5f) * 10000;
        pcm[i] = noise + float(1200 * std::sin(time * 2 * 3.141592653589793 * 70));
        if (block > 100) input_power += pcm[i] * pcm[i];
      }
      assert(denoiser.processFloat(pcm.data(), frames, level));
      for (int i = 0; i < frames; ++i) {
        assert(std::isfinite(pcm[i]) && pcm[i] >= -32768 && pcm[i] <= 32767);
        if (block > 100) output_power += pcm[i] * pcm[i];
      }
    }
    const double ratio = output_power / input_power;
    std::printf("rate=%d level=%d stationary noise power ratio=%.5f\n", rate, level, ratio);
    if (level != 0) assert(ratio < 0.9);
    else assert(std::abs(ratio - 1) < 1e-6);
  }
  pcm.fill(std::numeric_limits<float>::infinity());
  assert(denoiser.processFloat(pcm.data(), frames, 1));
  for (int i = 0; i < frames; ++i) assert(std::isfinite(pcm[i]));
}
int main() {
  // Also exercise shared lazy model initialization from concurrent streams.
  std::thread a([] { verify_rate(16000); });
  std::thread b([] { verify_rate(48000); });
  verify_rate(32000);
  a.join(); b.join();
  VoiceDenoiser denoiser(16000);
  std::array<int16_t, 320> pcm{};
  pcm.fill(-1200);
  assert(denoiser.processPcm(pcm.data(), 320, 0));
  assert(pcm[319] == -1200);
  assert(!denoiser.processPcm(pcm.data(), 319, 1));
  assert(denoiser.processPcm(pcm.data(), 320, 2));
  VoiceDenoiser unsupported(44100);
  assert(!unsupported.processPcm(pcm.data(), 320, 1));
}
