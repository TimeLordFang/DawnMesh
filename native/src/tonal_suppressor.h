#pragma once
#include <array>
#include <complex>

namespace dawnmesh {
// Conservative, persistent narrow-band whistle removal at RNNoise's 48 kHz.
// Analysis looks back 20 ms; filtering adds no buffering to the audio path.
class TonalSuppressor {
 public:
  void reset();
  void process(float* frame, float speech_probability);
 private:
  std::array<float, 960> history_{};
  std::array<std::complex<float>, 1024> spectrum_{};
  int filled_ = 0, stable_ = 0;
  float candidate_ = 0, frequency_ = 0, wet_ = 0;
  float x1_ = 0, x2_ = 0, y1_ = 0, y2_ = 0;
};
}
