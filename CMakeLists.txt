cmake_minimum_required(VERSION 3.30)

project("qmake" C CXX)

find_package(Git QUIET)
find_package(PkgConfig REQUIRED)

# glib-2.0 is QEMU's core dependency; the feature modules (qmake::osdep ...) re-export it.
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules")

option(QMAKE_BUILD_EXAMPLES "Build the bundled example out-of-tree modules" OFF)

# Stage 1: select + build a QEMU (configurable via QMAKE_QEMU_DIR).
include(QmakeQemuBuild)

# Stage 2: derive QEMU's compile environment + define feature modules.
include(QmakeIntrospect)
include(QmakeFeatureModules)

# examples/ is wired in once the public API module lands (Stage 4).
if(QMAKE_BUILD_EXAMPLES)
  add_subdirectory(examples/arm-hello-dev)
  add_subdirectory(examples/new-edu)
  add_subdirectory(examples/rust-devices)

  # Functional qtest: boot QEMU under -accel qtest and drive real MMIO against
  # the example devices (realize + read/write handlers), not just registration.
  enable_testing()
  find_program(QMAKE_PYTHON3 NAMES python3 python REQUIRED)
  add_test(
    NAME qtest-mmio
    COMMAND ${QMAKE_PYTHON3}
            ${CMAKE_CURRENT_SOURCE_DIR}/tests/qtest/qmake_qtest.py
            ${CMAKE_BINARY_DIR}/qemu-build/qemu-system-aarch64)
endif()

