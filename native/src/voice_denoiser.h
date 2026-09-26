#pragma once
#include <array>
#include <cstdint>

struct DenoiseState;
namespace dawnmesh {
// One instance per mono capture stream. PCM uses the signed-16 amplitude scale.
// processFloat consumes exactly 10 ms; processPcm consumes multiples of 10 ms.
class VoiceDenoiser {
 public:
  explicit VoiceDenoiser(int sample_rate);
  ~VoiceDenoiser();
  VoiceDenoiser(const VoiceDenoiser&) = delete;
  VoiceDenoiser& operator=(const VoiceDenoiser&) = delete;
  bool processFloat(float* samples, int count, int level);
  bool processPcm(int16_t* samples, int count, int level);
 private:
  struct Resampler {
    int input_count = 0, output_count = 0;
    std::array<float, 32> history{};
    std::array<std::array<float, 33>, 480> coefficients{};
    void init(int input, int output);
    void reset();
    void run(const float* input, float* output);
  };
  int rate_, last_level_ = 0, speech_hold_ = 0;
  DenoiseState* state_;
  Resampler up_, down_;
  std::array<float, 480> work_{}, output_{}, pcm_{};
  float previous_input_ = 0, highpass_ = 0, gain_ = 1;
};
}
