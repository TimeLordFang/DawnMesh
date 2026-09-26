#include "voice_denoiser.h"
#include <algorithm>
#include <cmath>
#include <mutex>
extern "C" {
#include "rnnoise.h"
}
namespace dawnmesh {
namespace {
constexpr double pi = 3.14159265358979323846;
float bounded(float value) {
  return std::isfinite(value) ? std::clamp(value, -32768.f, 32767.f) : 0.f;
}
// RNNoise v0.1 lazily initializes shared FFT tables. Warm them exactly once,
// before any instance can process a frame on another capture thread.
std::once_flag initialize_model;
}
void VoiceDenoiser::Resampler::init(int input, int output) {
  input_count = input; output_count = output;
  const double cutoff = 0.90 * std::min(1.0, double(output) / input);
  for (int i = 0; i < output; ++i) {
    const double position = double(i) * input / output;
    const double fraction = position - std::floor(position);
    double sum = 0;
    for (int k = 0; k <= 32; ++k) {
      const double x = k + fraction - 16;
      const double sinc = std::abs(x) < 1e-9 ? cutoff : std::sin(pi * cutoff * x) / (pi * x);
      const double window = 0.5 + 0.5 * std::cos(pi * x / 17);
      coefficients[i][k] = float(sinc * window);
      sum += coefficients[i][k];
    }
    for (auto& coefficient : coefficients[i]) coefficient /= float(sum);
  }
}
void VoiceDenoiser::Resampler::reset() { history.fill(0); }
void VoiceDenoiser::Resampler::run(const float* input, float* output) {
  if (input_count == output_count) {
    std::copy_n(input, input_count, output);
    return;
  }
  for (int i = 0; i < output_count; ++i) {
    const int position = i * input_count / output_count;
    double sum = 0;
    for (int k = 0; k <= 32; ++k) {
      const int index = position - k;
      const float sample = index < 0 ? history[32 + index] : input[index];
      sum += sample * coefficients[i][k];
    }
    output[i] = float(sum);
  }
  std::copy_n(input + input_count - 32, 32, history.begin());
}
VoiceDenoiser::VoiceDenoiser(int rate) : rate_(rate), state_(nullptr) {
  std::call_once(initialize_model, [] {
    auto* warm = rnnoise_create();
    if (warm) {
      float silence[480]{};
      rnnoise_process_frame(warm, silence, silence);
      rnnoise_destroy(warm);
    }
  });
  if (rate != 16000 && rate != 32000 && rate != 48000) return;
  state_ = rnnoise_create();
  up_.init(rate / 100, 480);
  down_.init(480, rate / 100);
}
VoiceDenoiser::~VoiceDenoiser() { if (state_) rnnoise_destroy(state_); }
bool VoiceDenoiser::processFloat(float* samples, int count, int level) {
  if (!samples || !state_ || count != rate_ / 100 || level < 0 || level > 2) return false;
  if (level == 0) { last_level_ = 0; return true; }
  if (last_level_ == 0) {
    rnnoise_init(state_); up_.reset(); down_.reset();
    previous_input_ = highpass_ = 0; gain_ = 1; speech_hold_ = 0;
  }
  last_level_ = level;
  // RNNoise already has an 80 Hz high-pass. Strong adds a gentle 160 Hz
  // filter before inference to reduce wind/engine rumble without a hard gate.
  const float pole = float(std::exp(-2 * pi * 160 / rate_));
  for (int i = 0; i < count; ++i) {
    const float input = bounded(samples[i]);
    highpass_ = pole * (highpass_ + input - previous_input_);
    previous_input_ = input;
    pcm_[i] = level == 2 ? highpass_ : input;
  }
  up_.run(pcm_.data(), work_.data());
  const float probability = rnnoise_process_frame(state_, output_.data(), work_.data());
  if (probability >= 0.45f) speech_hold_ = 12;
  else if (speech_hold_ > 0) --speech_hold_;
  const float target = level == 1 || speech_hold_ > 0 ? 1.f :
      std::clamp(0.35f + probability * 1.45f, 0.35f, 1.f);
  const float next_gain = gain_ + (target - gain_) * (target > gain_ ? 0.8f : 0.08f);
  for (int i = 0; i < 480; ++i) {
    output_[i] *= gain_ + (next_gain - gain_) * (i + 1) / 480.f;
  }
  gain_ = next_gain;
  down_.run(output_.data(), work_.data());
  for (int i = 0; i < count; ++i) samples[i] = bounded(work_[i]);
  return true;
}
bool VoiceDenoiser::processPcm(int16_t* samples, int count, int level) {
  const int block = rate_ / 100;
  if (!samples || !state_ || count <= 0 || count % block != 0 || level < 0 || level > 2) return false;
  if (level == 0) { last_level_ = 0; return true; }
  // Separate buffer: processFloat uses pcm_ as resampler input.
  std::array<float, 480> block_samples{};
  for (int start = 0; start < count; start += block) {
    for (int i = 0; i < block; ++i) block_samples[i] = samples[start + i];
    if (!processFloat(block_samples.data(), block, level)) return false;
    for (int i = 0; i < block; ++i) samples[start + i] = int16_t(std::lrint(block_samples[i]));
  }
  return true;
}
}
