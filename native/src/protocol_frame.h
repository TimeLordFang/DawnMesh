#ifndef DAWN_PROTOCOL_FRAME_H
#define DAWN_PROTOCOL_FRAME_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define FFI_EXPORT __declspec(dllexport)
#else
/* 见 ring_buffer.h：Apple 平台静态链接 + dead_strip 需要 `used`。 */
#define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#define DAWN_FRAME_HEADER_SIZE 6
/* 必须与 Dart 侧 Frame.maxPayloadSize 及 Kotlin 版 Frame.MAX_PAYLOAD 一致。
   音频走 Opus，一帧几十字节，512 足够。 */
#define DAWN_MAX_PAYLOAD_SIZE 512

typedef enum {
    DAWN_FRAME_AUDIO = 0x01,
    DAWN_FRAME_JOIN_REQ = 0x02,
    DAWN_FRAME_ROSTER = 0x03,
    DAWN_FRAME_PTT_STATE = 0x04,
    DAWN_FRAME_HEARTBEAT = 0x05,
    DAWN_FRAME_LEAVE = 0x06,
    DAWN_FRAME_HOST_HANDOVER = 0x07,
} DawnFrameType;

typedef struct {
    uint8_t type;
    uint8_t sender_id;
    uint16_t seq;
    uint16_t payload_len;
    uint8_t payload[DAWN_MAX_PAYLOAD_SIZE];
} DawnNativeFrame;

FFI_EXPORT int dawn_frame_encode(
    uint8_t type,
    uint8_t sender_id,
    uint16_t seq,
    const uint8_t* payload,
    uint16_t payload_len,
    uint8_t* out_buffer,
    size_t out_capacity
);

FFI_EXPORT int dawn_frame_decode(
    const uint8_t* in_buffer,
    size_t in_len,
    DawnNativeFrame* out_frame
);

#ifdef __cplusplus
}
#endif

#endif // DAWN_PROTOCOL_FRAME_H

