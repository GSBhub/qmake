# QmakeIntrospect.cmake
#
# Runs cmake/scripts/qmake_introspect.py against the configured QEMU build to
# derive the exact include dirs / defines / per-target flags used by QEMU, and
# loads them as CMake variables (QMAKE_OSDEP_*, QMAKE_QAPI_*, QMAKE_TARGET_*).
#
# QEMU is built by ExternalProject at *build* time, so on a clean tree the build
# dir is not yet configured when we run. In that case we skip gracefully and set
# QMAKE_INTROSPECTION_OK to FALSE; re-running CMake after the first build picks
# up the data. The static-injection path does not need these (QEMU's own meson
# compiles injected sources) -- they serve the preload/module/Rust/tooling paths.

include_guard(GLOBAL)

find_package(Python3 COMPONENTS Interpreter REQUIRED)

set(QMAKE_INTROSPECTION_OK FALSE)

function(qmake_run_introspection)
  set(_cc "${QMAKE_QEMU_BUILD_DIR}/compile_commands.json")
  if(NOT EXISTS "${_cc}")
    message(STATUS "qmake: QEMU not configured yet (${_cc} missing); "
      "feature modules will be available after the first build + re-run of cmake.")
    return()
  endif()

  set(_out "${CMAKE_BINARY_DIR}/qmake-introspection.cmake")
  execute_process(
    COMMAND "${Python3_EXECUTABLE}"
            "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../scripts/qmake_introspect.py"
            "${QMAKE_QEMU_BUILD_DIR}" "${_out}"
    RESULT_VARIABLE _rc
    OUTPUT_VARIABLE _msg
    ERROR_VARIABLE  _err)
  if(NOT _rc EQUAL 0)
    message(WARNING "qmake: introspection failed: ${_err}")
    return()
  endif()
  message(STATUS "qmake: ${_msg}")
  include("${_out}")

  # Re-export the loaded vars to the caller's scope.
  foreach(v OSDEP_INCLUDE_DIRS OSDEP_DEFINES OSDEP_FORCED_INCLUDES
            QAPI_INCLUDE_DIRS INTROSPECTED_ARCHS INTROSPECTION_OK)
    set(QMAKE_${v} "${QMAKE_${v}}" PARENT_SCOPE)
  endforeach()
  foreach(arch IN LISTS QMAKE_INTROSPECTED_ARCHS)
    set(QMAKE_TARGET_${arch}_INCLUDE_DIRS "${QMAKE_TARGET_${arch}_INCLUDE_DIRS}" PARENT_SCOPE)
    set(QMAKE_TARGET_${arch}_DEFINES "${QMAKE_TARGET_${arch}_DEFINES}" PARENT_SCOPE)
  endforeach()
endfunction()

qmake_run_introspection()
