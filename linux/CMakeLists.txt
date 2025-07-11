cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "stream_webrtc_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")
set (CMAKE_EXPORT_COMPILE_COMMANDS ON )
set(CMAKE_CXX_STANDARD 17)

add_definitions(-DRTC_DESKTOP_DEVICE)

add_library(${PLUGIN_NAME} SHARED
  "../common/cpp/src/flutter_data_channel.cc"
  "../common/cpp/src/flutter_frame_cryptor.cc"
  "../common/cpp/src/flutter_media_stream.cc"
  "../common/cpp/src/flutter_peerconnection.cc"
  "../common/cpp/src/flutter_frame_capturer.cc"
  "../common/cpp/src/flutter_video_renderer.cc"
  "../common/cpp/src/flutter_screen_capture.cc"
  "../common/cpp/src/flutter_webrtc.cc"
  "../common/cpp/src/flutter_webrtc_base.cc"
  "../common/cpp/src/flutter_common.cc"
  "stream_webrtc_flutter_plugin.cc"
  "flutter/core_implementations.cc"
  "flutter/standard_codec.cc"
  "flutter/plugin_registrar.cc"
  "task_runner_linux.cc"
)

include_directories(
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/flutter/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/svpng"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)


target_link_libraries(${PLUGIN_NAME} PRIVATE 
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/${FLUTTER_TARGET_PLATFORM}/libwebrtc.so"
)

# List of absolute paths to libraries that should be bundled with the plugin
set(flutter_webrtc_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/${FLUTTER_TARGET_PLATFORM}/libwebrtc.so"
  PARENT_SCOPE
)

# Add $ORIGIN to RPATH so that lib/libstream_webrtc_flutter_plugin.so can find lib/libwebrtc.so at runtime
set_property(
    TARGET ${PLUGIN_NAME}
    PROPERTY BUILD_RPATH
    "\$ORIGIN"
)
