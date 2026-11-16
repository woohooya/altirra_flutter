# bridge.cmake - injected into the upstream AltirraSDL CMake project via
#   -DCMAKE_PROJECT_INCLUDE=<this file>
#
# Upstream's CMake uses CMAKE_SOURCE_DIR extensively, so it must be the
# top-level project and cannot be add_subdirectory()'d. Instead we hook in
# right after its project() call and defer our target definitions until the
# whole upstream tree (and thus the AltirraLibretro target) has been processed.
# This keeps the upstream checkout completely unmodified.

set(ALTIRRA_BRIDGE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# Libretro core only; no SDL3/ImGui frontend.
set(ALTIRRA_LIBRETRO ON CACHE BOOL "" FORCE)
set(ALTIRRA_SDL3 OFF CACHE BOOL "" FORCE)
set(ALTIRRA_LIBRETRO_NO_SDL3 ON CACHE BOOL "" FORCE)
set(ALTIRRA_LIBRETRO_BUILD_TESTS OFF CACHE BOOL "" FORCE)

function(altirra_bridge_define_targets)
    if(NOT TARGET AltirraLibretro)
        message(FATAL_ERROR "AltirraLibretro target missing; is the upstream tree too old?")
    endif()

    # Android's package manager only extracts/loads lib*.so; give the core a
    # conventional name everywhere so DT_NEEDED lookups just work.
    set_target_properties(AltirraLibretro PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "altirra_libretro")

    add_library(altirra_bridge SHARED
        "${ALTIRRA_BRIDGE_DIR}/altirra_bridge.cpp"
        "${ALTIRRA_BRIDGE_DIR}/miniaudio_impl.c"
    )
    target_include_directories(altirra_bridge PRIVATE
        "${ALTIRRA_BRIDGE_DIR}"
        "${ALTIRRA_BRIDGE_DIR}/third_party"
        "${CMAKE_SOURCE_DIR}/src/AltirraLibretro/libretro"
    )
    target_compile_features(altirra_bridge PRIVATE cxx_std_17)
    set_target_properties(altirra_bridge PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden)
    target_link_libraries(altirra_bridge PRIVATE AltirraLibretro)

    find_package(Threads REQUIRED)
    target_link_libraries(altirra_bridge PRIVATE Threads::Threads)

    if(ANDROID)
        target_link_libraries(altirra_bridge PRIVATE log dl)
        # 16 KB page size support (required for new Play Store uploads).
        target_link_options(altirra_bridge PRIVATE "LINKER:-z,max-page-size=16384")
        target_link_options(AltirraLibretro PRIVATE "LINKER:-z,max-page-size=16384")
    elseif(APPLE)
        target_link_libraries(altirra_bridge PRIVATE
            "-framework CoreFoundation" "-framework CoreAudio" "-framework AudioToolbox")
    elseif(UNIX)
        target_link_libraries(altirra_bridge PRIVATE dl m)
        set_target_properties(altirra_bridge PROPERTIES
            BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN")
    endif()
endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL altirra_bridge_define_targets)
