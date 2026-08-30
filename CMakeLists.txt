cmake_minimum_required(VERSION 3.24)
project(LensTrans LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(LLAMA_PREBUILT "${CMAKE_SOURCE_DIR}/third_party/llama.cpp/build")
set(LLAMA_SRC "${CMAKE_SOURCE_DIR}/third_party/llama.cpp")
set(HAVE_PREBUILT_LLAMA OFF)
if(EXISTS "${LLAMA_PREBUILT}/src/Release/llama.lib" AND EXISTS "${LLAMA_SRC}/include/llama.h")
  set(HAVE_PREBUILT_LLAMA ON)
endif()

option(LENSTRANS_WITH_LLAMA "Link prebuilt llama.cpp b10688" ${HAVE_PREBUILT_LLAMA})

add_library(lenstrans_core STATIC
  core/src/engine_local.cpp
  core/src/engine_cloud.cpp
  core/src/engine_fake.cpp
)
target_include_directories(lenstrans_core PUBLIC "${CMAKE_SOURCE_DIR}/core/include")
if(WIN32)
  target_link_libraries(lenstrans_core PUBLIC winhttp crypt32)
endif()

if(LENSTRANS_WITH_LLAMA AND HAVE_PREBUILT_LLAMA)
  target_compile_definitions(lenstrans_core PUBLIC LENSTRANS_WITH_LLAMA)
  target_include_directories(lenstrans_core PUBLIC
    "${LLAMA_SRC}/include"
    "${LLAMA_SRC}/ggml/include")
  target_link_libraries(lenstrans_core PUBLIC
    "${LLAMA_PREBUILT}/src/Release/llama.lib"
    "${LLAMA_PREBUILT}/ggml/src/Release/ggml.lib"
    "${LLAMA_PREBUILT}/ggml/src/Release/ggml-base.lib"
    "${LLAMA_PREBUILT}/ggml/src/Release/ggml-cpu.lib")
  message(STATUS "LensTrans: linking prebuilt llama.cpp at ${LLAMA_PREBUILT}")
elseif(LENSTRANS_WITH_LLAMA)
  message(FATAL_ERROR "LENSTRANS_WITH_LLAMA=ON but prebuilt llama.lib missing")
endif()

function(lenstrans_copy_llama tgt)
  if(LENSTRANS_WITH_LLAMA AND HAVE_PREBUILT_LLAMA)
    foreach(dll llama.dll ggml.dll ggml-base.dll ggml-cpu.dll)
      add_custom_command(TARGET ${tgt} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${LLAMA_PREBUILT}/bin/Release/${dll}"
          "$<TARGET_FILE_DIR:${tgt}>/${dll}")
    endforeach()
  endif()
endfunction()

add_executable(lenstrans_test tests/test_core.cpp)
target_link_libraries(lenstrans_test PRIVATE lenstrans_core)
if(MSVC)
  target_compile_options(lenstrans_test PRIVATE /utf-8 /W4 /permissive-)
endif()

if(WIN32)
  add_executable(lenstrans_test_hotkey tests/test_hotkey.cpp)
  target_link_libraries(lenstrans_test_hotkey PRIVATE lenstrans_core user32)
  target_compile_definitions(lenstrans_test_hotkey PRIVATE NOMINMAX WINVER=0x0A00
                             _WIN32_WINNT=0x0A00)
  if(MSVC)
    target_compile_options(lenstrans_test_hotkey PRIVATE /utf-8 /W4 /permissive-)
  endif()
endif()

add_executable(lenstrans_test_llama tests/test_llama.cpp)
target_link_libraries(lenstrans_test_llama PRIVATE lenstrans_core)
if(WIN32)
  target_link_libraries(lenstrans_test_llama PRIVATE psapi)
endif()
if(MSVC)
  target_compile_options(lenstrans_test_llama PRIVATE /utf-8 /W4 /permissive-)
endif()
lenstrans_copy_llama(lenstrans_test_llama)

if(WIN32)
  add_executable(lenstrans_overlay WIN32
    win/overlay/main.cpp
    win/capture/capture.cpp
    win/ocr/winrt_ocr.cpp
    win/app/secrets.cpp
    win/app/ui.cpp
    win/app/model_download.cpp
  )
  target_include_directories(lenstrans_overlay PRIVATE "${CMAKE_SOURCE_DIR}")
  target_link_libraries(lenstrans_overlay PRIVATE
    lenstrans_core user32 gdi32 comctl32 shell32 ole32 dwmapi d3d11 dxgi windowsapp bcrypt)
  target_compile_definitions(lenstrans_overlay PRIVATE UNICODE _UNICODE NOMINMAX WINVER=0x0A00
                                                       _WIN32_WINNT=0x0A00 NTDDI_VERSION=0x0A000010)
  if(MSVC)
    target_compile_options(lenstrans_overlay PRIVATE /utf-8 /W4 /permissive-)
  endif()
  lenstrans_copy_llama(lenstrans_overlay)

  add_executable(lenstrans_e2e_target tests/e2e_target.cpp)
  target_compile_definitions(lenstrans_e2e_target PRIVATE UNICODE _UNICODE NOMINMAX WINVER=0x0A00
                                                         _WIN32_WINNT=0x0A00)
  if(MSVC)
    target_compile_options(lenstrans_e2e_target PRIVATE /utf-8 /W4 /permissive-)
  endif()

  add_executable(lenstrans_wgc_probe
    tests/wgc_probe.cpp
    win/capture/capture.cpp
    win/ocr/winrt_ocr.cpp
  )
  target_include_directories(lenstrans_wgc_probe PRIVATE "${CMAKE_SOURCE_DIR}")
  target_link_libraries(lenstrans_wgc_probe PRIVATE
    lenstrans_core user32 gdi32 ole32 d3d11 dxgi windowsapp)
  target_compile_definitions(lenstrans_wgc_probe PRIVATE UNICODE _UNICODE NOMINMAX WINVER=0x0A00
                                                         _WIN32_WINNT=0x0A00)
  if(MSVC)
    target_compile_options(lenstrans_wgc_probe PRIVATE /utf-8 /W4 /permissive-)
  endif()
endif()
