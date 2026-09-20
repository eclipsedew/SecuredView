cmake_minimum_required(VERSION 3.14)
project(warp_vpn LANGUAGES CXX)

set(BINARY_NAME "securedview")
set(APPLICATION_ID "com.securedview.app")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)

function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_definitions(${TARGET} PRIVATE "NOMINMAX" "UNICODE" "_UNICODE"
    $<$<NOT:$<CONFIG:Debug>>:NDEBUG>)
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

add_executable(${BINARY_NAME} WIN32
  "runner/main.cpp"
  "runner/flutter_window.cpp"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX" "UNICODE" "_UNICODE")

add_dependencies(${BINARY_NAME} flutter_assemble)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE kernel32 user32 gdi32 winspool comctl32)
target_link_libraries(${BINARY_NAME} PRIVATE oleaut32 ole32 uuid shell32 shlwapi)
target_link_libraries(${BINARY_NAME} PRIVATE advapi32 delayimp)
target_link_libraries(${BINARY_NAME} PRIVATE ${CMAKE_DL_LIBS})

set_target_properties(${BINARY_NAME} PROPERTIES VS_DPI_AWARE "ON")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)

foreach(bundled_library ${RUNTIME_LIBRARY_DIRS})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)
