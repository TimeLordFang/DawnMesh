#include "tonal_suppressor.h"
#include <algorithm>
#include <cmath>
namespace dawnmesh {
namespace { constexpr float pi = 3.14159265358979323846f; }
void TonalSuppressor::reset() {
  history_.fill(0); filled_ = stable_ = 0;
  candidate_ = frequency_ = wet_ = x1_ = x2_ = y1_ = y2_ = 0;
}
void TonalSuppressor::process(float* frame, float speech_probability) {
  std::copy(history_.begin() + 480, history_.end(), history_.begin());
  std::copy_n(frame, 480, history_.begin() + 480);
  filled_ = std::min(2, filled_ + 1);
  for (int i = 0; i < 1024; ++i) {
    spectrum_[i] = i < 960 ? history_[i] * (0.5f - 0.5f * std::cos(2*pi*i/959)) : 0.f;
  }
  for (int i=1, j=0; i<1024; ++i) {
    int bit=512; for (; j & bit; bit>>=1) j^=bit; j^=bit;
    if (i<j) std::swap(spectrum_[i], spectrum_[j]);
  }
  for (int length=2; length<=1024; length<<=1) {
    const auto step=std::polar(1.f, -2*pi/length);
    for (int start=0; start<1024; start+=length) {
      std::complex<float> phase(1,0);
      for (int k=0; k<length/2; ++k) {
        const auto a=spectrum_[start+k], b=phase*spectrum_[start+k+length/2];
        spectrum_[start+k]=a+b; spectrum_[start+k+length/2]=a-b; phase*=step;
      }
    }
  }
  double total=0; int peak=20;
  for (int k=1; k<512; ++k) total+=std::norm(spectrum_[k]);
  for (int k=20; k<=128; ++k) if (std::norm(spectrum_[k])>std::norm(spectrum_[peak])) peak=k;
  const float left=std::norm(spectrum_[peak-1]), center=std::norm(spectrum_[peak]), right=std::norm(spectrum_[peak+1]);
  const double concentration=(left+center+right)/(total+1);
  // Require overwhelming single-line energy during speech. Voiced harmonics,
  // consonants, broad rubbing noise and short transients must not trigger it.
  const float threshold=speech_probability >= 0.6f ? 0.85f : 0.65f;
  bool evidence=filled_==2 && total>1e7 && concentration>threshold;
  if (evidence) {
    const float a=std::log(left+1), b=std::log(center+1), c=std::log(right+1);
    const float denominator=a-2*b+c;
    const float delta=std::abs(denominator)>1e-6f ? std::clamp(0.5f*(a-c)/denominator, -0.5f, 0.5f) : 0.f;
    const float hz=(peak+delta)*48000/1024;
    if (std::abs(hz-candidate_)<70) { ++stable_; candidate_+=0.2f*(hz-candidate_); }
    else { candidate_=hz; stable_=1; }
  } else stable_=0;
  const bool active=evidence && stable_>=20;
  if (active) {
    if (frequency_==0 || std::abs(frequency_-candidate_)>150) {
      frequency_=candidate_; x1_=x2_=y1_=y2_=0; wet_=0;
    } else frequency_+=0.1f*(candidate_-frequency_);
  }
  const float next=wet_+((active?1.f:0.f)-wet_)*(active?0.2f:0.25f);
  if (frequency_>0) {
    const float c=std::cos(2*pi*frequency_/48000), r=std::exp(-pi*90/48000);
    const float g=(1-2*r*c+r*r)/(2-2*c);
    for (int i=0; i<480; ++i) {
      const float x=frame[i];
      const float y=g*(x-2*c*x1_+x2_)+2*r*c*y1_-r*r*y2_;
      x2_=x1_;x1_=x;y2_=y1_;y1_=y;
      const float mix=wet_+(next-wet_)*(i+1)/480;
      frame[i]=x+mix*(y-x);
    }
  }
  wet_=next;
}
}
