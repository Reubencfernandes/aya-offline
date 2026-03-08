cmake_minimum_required(VERSION 3.18)
project(aya_engine C)

set(CMAKE_C_STANDARD 11)

# Source files (library only, no HTTP server)
set(AYA_SOURCES
    src/gguf.c
    src/model.c
    src/aya_api.c
)

# Build as shared library
add_library(aya_engine SHARED ${AYA_SOURCES})
target_include_directories(aya_engine PRIVATE src)
target_link_libraries(aya_engine m)

# Platform-specific optimizations
if(ANDROID)
    # ARM NEON is enabled by default on arm64-v8a
    target_compile_options(aya_engine PRIVATE -O2)
    # Strip for smaller APK
    set_target_properties(aya_engine PROPERTIES
        LINK_FLAGS "-s"
    )
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    # x86_64: use AVX2 + FMA
    target_compile_options(aya_engine PRIVATE -O2 -mavx2 -mfma)
else()
    target_compile_options(aya_engine PRIVATE -O2)
endif()
