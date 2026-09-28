#include "voice_denoiser.h"
#include "tonal_suppressor.h"
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

void verify_tonal_protection() {
  for (float hz : {1100.f, 2350.f, 4800.f}) {
    dawnmesh::TonalSuppressor filter;
    std::array<float,480> frame{};
    double input=0,output=0;
    for (int block=0;block<180;++block) {
      for(int i=0;i<480;++i) frame[i]=2000*std::sin(2*3.141592653589793*hz*(block*480+i)/48000);
      if(block>80) for(float x:frame) input+=x*x;
      const auto before=frame;
      filter.process(frame.data(),1.f); // A tonal whistle may fool speech VAD.
      if(block<19) assert(frame==before); // Never notch a short consonant/transient.
      for(float x:frame) {assert(std::isfinite(x));if(block>80) output+=x*x;}
    }
    std::printf("persistent whistle %.0f Hz power ratio=%.6f\n",hz,output/input);
    assert(output/input<0.04); // At least 14 dB after settling.
    filter.reset();
    for(int block=0;block<100;++block) {
      for(int i=0;i<480;++i) {
        const double t=double(block*480+i)/48000;
        frame[i]=0;
        for(int harmonic=1;harmonic<=30;++harmonic)
          frame[i]+=float(1200.0/harmonic*std::sin(2*3.141592653589793*180*harmonic*t));
      }
      const auto speech=frame;
      filter.process(frame.data(),1.f);
      assert(frame==speech); // Harmonic voice must not be mistaken for a whistle.
    }
  }
}
void verify_strong_whistle(int rate, bool wind = false) {
  VoiceDenoiser standard(rate), strong(rate);
  std::array<float,480> a{}, b{};
  const int count=rate/100;
  double standard_power=0,strong_power=0;
  uint32_t random=73;
  for(int block=0;block<200;++block) {
    for(int i=0;i<count;++i) {
      random=random*1664525u+1013904223u;
      const double t=double(block*count+i)/rate;
      const float gust=wind ? float(5000*std::sin(2*3.141592653589793*70*t))+(float(random>>8)/16777216.f-0.5f)*1000 : 0;
      a[i]=b[i]=float(3000*std::sin(2*3.141592653589793*2350*t))+gust;
    }
    assert(standard.processFloat(a.data(),count,1));assert(strong.processFloat(b.data(),count,2));
    if(block>100) for(int i=0;i<count;++i) {standard_power+=a[i]*a[i];strong_power+=b[i]*b[i];}
  }
  std::printf("rate=%d wind=%d strong/standard whistle ratio=%.6f\n",rate,int(wind),strong_power/(standard_power+1));
  assert(strong_power/(standard_power+1)<0.2);
}
int main() {
  verify_tonal_protection();
  for (int rate : {16000,32000,48000}) {verify_strong_whistle(rate);verify_strong_whistle(rate,true);}
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
