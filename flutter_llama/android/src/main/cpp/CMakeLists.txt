# Flutter Llama - CMake configuration for Android with llama.cpp
# Based on llama.cpp/examples/llama.android approach

cmake_minimum_required(VERSION 3.10.2)

project(flutter_llama)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# Find required packages
find_library(log-lib log)
find_library(android-lib android)

# llama.cpp configuration
set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../llama.cpp")

# Configure llama.cpp build
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)

# Disable features not needed for mobile
set(GGML_USE_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_AMX OFF CACHE BOOL "" FORCE)

# GPU Acceleration for Android devices
# Vulkan for modern devices (Android 7.0+)
# OpenCL as fallback for older devices
# CPU backend with NEON as last resort

find_library(vulkan-lib vulkan)
find_library(opencl-lib OpenCL)

# Respect explicit backend flags from Gradle/tooling and only auto-detect when
# neither backend has been configured yet.
set(FLUTTER_LLAMA_GPU_BACKEND_CONFIGURED OFF)
if(DEFINED GGML_VULKAN OR DEFINED GGML_OPENCL)
    set(FLUTTER_LLAMA_GPU_BACKEND_CONFIGURED ON)
endif()

if(FLUTTER_LLAMA_GPU_BACKEND_CONFIGURED)
    if(GGML_VULKAN)
        if(vulkan-lib)
            message(STATUS "🚀 Vulkan GPU acceleration ENABLED")
            message(STATUS "   Supported: Adreno 5xx+, Mali-G71+, Samsung Exynos 9+")
            message(STATUS "   Expected: 4-8x faster than CPU")
        else()
            message(WARNING "GGML_VULKAN was requested, but Vulkan libraries were not found. Falling back to CPU.")
            set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
        endif()
    endif()

    if(GGML_OPENCL)
        if(opencl-lib)
            message(STATUS "⚡ OpenCL GPU acceleration ENABLED (fallback)")
            message(STATUS "   Supported: Most Android devices with GPU")
            message(STATUS "   Expected: 2-5x faster than CPU")
        else()
            message(WARNING "GGML_OPENCL was requested, but OpenCL libraries were not found. Falling back to CPU.")
            set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
        endif()
    endif()

    if(NOT GGML_VULKAN AND NOT GGML_OPENCL)
        message(STATUS "⚡ Using optimized CPU backend with ARM NEON")
        message(STATUS "   GPU acceleration disabled by build configuration")
    endif()
else()
    # Try to enable Vulkan (best performance on modern devices)
    if(vulkan-lib)
        set(GGML_VULKAN ON CACHE BOOL "" FORCE)
        message(STATUS "🚀 Vulkan GPU acceleration ENABLED")
        message(STATUS "   Supported: Adreno 5xx+, Mali-G71+, Samsung Exynos 9+")
        message(STATUS "   Expected: 4-8x faster than CPU")
    else()
        # Try OpenCL as fallback
        if(opencl-lib)
            set(GGML_OPENCL ON CACHE BOOL "" FORCE)
            message(STATUS "⚡ OpenCL GPU acceleration ENABLED (fallback)")
            message(STATUS "   Supported: Most Android devices with GPU")
            message(STATUS "   Expected: 2-5x faster than CPU")
        else()
            message(STATUS "⚡ Using optimized CPU backend with ARM NEON")
            message(STATUS "   GPU libraries not found, falling back to CPU")
        endif()
    endif()
endif()

message(STATUS "   Works on: All ARM64 Android devices")

# Add llama.cpp as subdirectory (it will build its own CMakeLists.txt)
add_subdirectory(${LLAMA_CPP_DIR} build-llama)

# Create our JNI bridge library
add_library(flutter_llama_bridge SHARED
    flutter_llama_bridge.cpp
)

# Include directories
target_include_directories(flutter_llama_bridge PRIVATE
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/src
    ${LLAMA_CPP_DIR}/ggml/include
    ${LLAMA_CPP_DIR}/common
)

# Link with llama.cpp libraries
target_link_libraries(flutter_llama_bridge
    llama
    ${log-lib}
    ${android-lib}
)

# Link GPU libraries if found
if(GGML_VULKAN AND vulkan-lib)
    target_link_libraries(flutter_llama_bridge ${vulkan-lib})
    message(STATUS "  Linked: Vulkan library")
endif()

if(GGML_OPENCL AND opencl-lib)
    target_link_libraries(flutter_llama_bridge ${opencl-lib})
    message(STATUS "  Linked: OpenCL library")
endif()

message(STATUS "Flutter Llama Bridge configuration:")
message(STATUS "  Android ABI: ${ANDROID_ABI}")
message(STATUS "  llama.cpp Dir: ${LLAMA_CPP_DIR}")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
