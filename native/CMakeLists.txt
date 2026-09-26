cmake_minimum_required(VERSION 3.10)
project(dawn_mesh_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(dawn_mesh_native SHARED
    src/audio_dsp.cpp
    src/ring_buffer.cpp
    src/protocol_frame.cpp
    src/voice_denoiser.cpp
)

add_library(rnnoise STATIC
    vendor/rnnoise/src/denoise.c vendor/rnnoise/src/rnn.c
    vendor/rnnoise/src/rnn_data.c vendor/rnnoise/src/pitch.c
    vendor/rnnoise/src/kiss_fft.c vendor/rnnoise/src/celt_lpc.c)
set_target_properties(rnnoise PROPERTIES POSITION_INDEPENDENT_CODE ON C_VISIBILITY_PRESET hidden)
target_include_directories(rnnoise PUBLIC vendor/rnnoise/include PRIVATE vendor/rnnoise/src)
target_compile_options(rnnoise PRIVATE -O3)
target_link_libraries(dawn_mesh_native PRIVATE rnnoise)
if(ANDROID)
    target_sources(dawn_mesh_native PRIVATE src/voice_denoiser_jni.cpp)
else()
    enable_testing()
    add_executable(voice_denoiser_test test/voice_denoiser_test.cpp)
    target_link_libraries(voice_denoiser_test PRIVATE dawn_mesh_native)
    add_test(NAME voice_denoiser COMMAND voice_denoiser_test)
endif()

target_include_directories(dawn_mesh_native PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if (MSVC)
    target_compile_options(dawn_mesh_native PRIVATE /W4 /O2)
else()
    target_compile_options(dawn_mesh_native PRIVATE -Wall -Wextra -O3 -fPIC)
endif()
