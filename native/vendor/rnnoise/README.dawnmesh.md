# Vendored RNNoise 0.2

Source: https://github.com/xiph/rnnoise/releases/tag/v0.2
BSD 3-clause license: COPYING. Includes the upstream default model; no runtime downloads.

Generic portable C sources from RNNOISE_SOURCES in Makefile.am are compiled.
The pitch, FFT and LPC translation units use rnnoise_ filenames, and their CELT/FFT
helpers use dawn_rnnoise_ symbol prefixes to coexist with iOS libopus.
DawnMesh wraps the 48 kHz / 480-sample API with streaming resampling.

Includes upstream ARM/scalar compilation fix
https://github.com/xiph/rnnoise/commit/372f7b4b76cde4ca1ec4605353dd17898a99de38
(which replaces absent Opus headers with RNNoise's own memory helpers).
