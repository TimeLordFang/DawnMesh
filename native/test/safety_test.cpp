#include "protocol_frame.h"
#include "ring_buffer.h"
#include <cassert>
#include <cstring>
int main() {
    uint8_t out[1024];
    memset(out, 0xa5, sizeof(out));
    assert(sunset_frame_encode(1, 1, 0, nullptr, 1, out, sizeof(out)) < 0);
    assert(out[6] == 0xa5);
    uint8_t payload[513] = {};
    assert(sunset_frame_encode(1, 1, 0, payload, 513, out, sizeof(out)) < 0);
    assert(sunset_frame_encode(1, 1, 0, payload, 512, out, sizeof(out)) == 518);
    SunsetNativeFrame decoded{};
    assert(sunset_frame_decode(out, 517, &decoded) < 0);
    assert(sunset_frame_decode(out, 518, &decoded) == 0);
    auto* ring = sunset_ring_buffer_create(8);
    assert(ring);
    uint8_t input[] = {1,2,3,4,5,6,7,8};
    assert(sunset_ring_buffer_write(ring, input, 8) == 7);
    assert(sunset_ring_buffer_read(ring, out, 5) == 5);
    assert(memcmp(input, out, 5) == 0);
    assert(sunset_ring_buffer_write(ring, input, 5) == 5);
    assert(sunset_ring_buffer_read(ring, out, 7) == 7);
    assert(out[0] == 6 && out[1] == 7 && out[2] == 1 && out[6] == 5);
    sunset_ring_buffer_free(ring);
}
