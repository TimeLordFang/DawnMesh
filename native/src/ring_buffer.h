#ifndef DAWN_RING_BUFFER_H
#define DAWN_RING_BUFFER_H

#include <stdint.h>
#include <stddef.h>
#include <atomic>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define FFI_EXPORT __declspec(dllexport)
#else
/* `used` 是 Apple 平台必需的：iOS/macOS 把这些 .cpp 静态链进 app 二进制，
 * 只有 Dart 侧通过 DynamicLibrary.process() 在运行时查符号，
 * 链接期没有任何引用，release 的 -dead_strip 会把它们剥掉。 */
#define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

/// High-Performance Lock-Free Single-Producer Single-Consumer (SPSC) Audio Ring Buffer.
typedef struct DawnRingBuffer {
    uint8_t* buffer;
    size_t capacity;
    std::atomic<size_t> head;
    std::atomic<size_t> tail;
} DawnRingBuffer;

FFI_EXPORT DawnRingBuffer* dawn_ring_buffer_create(size_t capacity);
FFI_EXPORT void dawn_ring_buffer_free(DawnRingBuffer* rb);
FFI_EXPORT size_t dawn_ring_buffer_write(DawnRingBuffer* rb, const uint8_t* data, size_t length);
FFI_EXPORT size_t dawn_ring_buffer_read(DawnRingBuffer* rb, uint8_t* out_data, size_t length);
FFI_EXPORT size_t dawn_ring_buffer_available_read(const DawnRingBuffer* rb);
FFI_EXPORT size_t dawn_ring_buffer_available_write(const DawnRingBuffer* rb);
FFI_EXPORT void dawn_ring_buffer_clear(DawnRingBuffer* rb);

#ifdef __cplusplus
}
#endif

#endif // DAWN_RING_BUFFER_H

