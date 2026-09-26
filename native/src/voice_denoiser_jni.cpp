#include "voice_denoiser.h"
#include <jni.h>
#include <new>
using dawnmesh::VoiceDenoiser;
extern "C" {
JNIEXPORT jlong JNICALL Java_dev_dawnmesh_intercom_audio_VoiceDenoiser_nativeCreate(JNIEnv*, jobject, jint rate) {
  if (rate != 16000 && rate != 32000 && rate != 48000) return 0;
  return reinterpret_cast<jlong>(new (std::nothrow) VoiceDenoiser(rate));
}
JNIEXPORT void JNICALL Java_dev_dawnmesh_intercom_audio_VoiceDenoiser_nativeDestroy(JNIEnv*, jobject, jlong handle) {
  delete reinterpret_cast<VoiceDenoiser*>(handle);
}
JNIEXPORT void JNICALL Java_dev_dawnmesh_intercom_audio_VoiceDenoiser_nativePcm(JNIEnv* env, jobject, jlong handle, jshortArray samples, jint level) {
  if (!handle || !samples) return;
  const auto count = env->GetArrayLength(samples);
  auto* data = env->GetShortArrayElements(samples, nullptr);
  if (!data) return;
  reinterpret_cast<VoiceDenoiser*>(handle)->processPcm(data, count, level);
  env->ReleaseShortArrayElements(samples, data, 0);
}
JNIEXPORT void JNICALL Java_dev_dawnmesh_intercom_audio_VoiceDenoiser_nativeFloat(JNIEnv* env, jobject, jlong handle, jobject buffer, jint count, jint level) {
  if (!handle || !buffer || count <= 0 || count > 480) return;
  if (env->GetDirectBufferCapacity(buffer) < jlong(count) * sizeof(float)) return;
  auto* data = static_cast<float*>(env->GetDirectBufferAddress(buffer));
  if (data) reinterpret_cast<VoiceDenoiser*>(handle)->processFloat(data, count, level);
}
}
