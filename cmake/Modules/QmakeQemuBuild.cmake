# QmakeQemuBuild.cmake
#
# Drives a chosen QEMU source tree through its own configure -> meson -> ninja
# build via ExternalProject. The tree is selected with QMAKE_QEMU_DIR and defaults
# to the extern/qemu git submodule, but may point at any other local QEMU clone
# (avatar-qemu, libqemu-afl-bridge, a fork) without changing anything else.
#
# Exports (cache):
#   QMAKE_QEMU_DIR        - source tree being built
#   QMAKE_QEMU_BUILD_DIR  - out-of-source build dir (always under our binary dir)
#   QMAKE_QEMU_TARGETS    - --target-list passed to configure
# and the ExternalProject target `qemu` plus `qmake_qemu_binary(<var> <target>)`.

include_guard(GLOBAL)
include(ExternalProject)

# Default to qmake's own bundled submodule, resolved relative to THIS module file
# (cmake/Modules/) so it works whether qmake is the top project or add_subdirectory'd
# by an external consumer. Override QMAKE_QEMU_DIR to target another QEMU clone.
get_filename_component(_qmake_default_qemu_dir
    "${CMAKE_CURRENT_LIST_DIR}/../../extern/qemu" ABSOLUTE)
set(QMAKE_QEMU_DIR "${_qmake_default_qemu_dir}"
    CACHE PATH "QEMU source tree to build against (defaults to the extern/qemu submodule)")
set(QMAKE_QEMU_REMOTE "https://gitlab.com/qemu-project/qemu.git"
    CACHE STRING "Remote used only to initialise/update the default submodule")
set(QMAKE_QEMU_TAG "v10.2.3"
    CACHE STRING "Tag the default submodule is pinned to (informational)")
set(QMAKE_QEMU_TARGETS "aarch64-softmmu"
    CACHE STRING "Value for QEMU configure --target-list (space/comma separated)")
set(QMAKE_QEMU_CONFIGURE_ARGS ""
    CACHE STRING "Extra arguments appended to QEMU's configure invocation")
option(QMAKE_ENABLE_MODULES
    "Pass --enable-modules to QEMU configure (only needed for MODULE-linkage out-of-tree modules)" OFF)
option(QMAKE_ENABLE_RUST
    "Force --enable-rust on QEMU configure (otherwise auto-enabled when a LANG RUST module is added)" OFF)

# --- Validate the target tree actually looks like QEMU -----------------------
if(NOT EXISTS "${QMAKE_QEMU_DIR}/configure" OR NOT EXISTS "${QMAKE_QEMU_DIR}/meson.build")
  message(FATAL_ERROR
    "QMAKE_QEMU_DIR='${QMAKE_QEMU_DIR}' does not look like a QEMU source tree "
    "(missing configure and/or meson.build). Initialise the submodule "
    "(git submodule update --init extern/qemu) or point QMAKE_QEMU_DIR at a QEMU clone.")
endif()

# Parse the QEMU version (from the tree's VERSION file) so out-of-tree modules can
# guard API differences across QEMU releases. Exposed to C via a generated header
# (see qmake_inject_module) and here as cache vars.
if(EXISTS "${QMAKE_QEMU_DIR}/VERSION")
  file(READ "${QMAKE_QEMU_DIR}/VERSION" _qmake_ver_raw)
  string(STRIP "${_qmake_ver_raw}" _qmake_ver_raw)
  if(_qmake_ver_raw MATCHES "^([0-9]+)\\.([0-9]+)\\.?([0-9]*)")
    set(QMAKE_QEMU_VER_MAJOR "${CMAKE_MATCH_1}" CACHE INTERNAL "")
    set(QMAKE_QEMU_VER_MINOR "${CMAKE_MATCH_2}" CACHE INTERNAL "")
    set(QMAKE_QEMU_VER_MICRO "0" CACHE INTERNAL "")
    if(CMAKE_MATCH_3)
      set(QMAKE_QEMU_VER_MICRO "${CMAKE_MATCH_3}" CACHE INTERNAL "")
    endif()
  endif()
endif()
if(NOT DEFINED QMAKE_QEMU_VER_MAJOR)
  message(WARNING "qmake: could not parse QEMU version from ${QMAKE_QEMU_DIR}/VERSION; "
    "version guards will default to 0.0.0")
  set(QMAKE_QEMU_VER_MAJOR "0" CACHE INTERNAL "")
  set(QMAKE_QEMU_VER_MINOR "0" CACHE INTERNAL "")
  set(QMAKE_QEMU_VER_MICRO "0" CACHE INTERNAL "")
endif()

# Build artefacts always live under our own binary dir so an externally supplied
# QMAKE_QEMU_DIR is never polluted with build output.
set(QMAKE_QEMU_BUILD_DIR "${CMAKE_BINARY_DIR}/qemu-build"
    CACHE PATH "QEMU out-of-source build directory" FORCE)

# configure wants a comma-separated list; accept either separator from the user.
string(REPLACE " " "," _qmake_target_list "${QMAKE_QEMU_TARGETS}")
set(QMAKE_QEMU_TARGET_LIST "${_qmake_target_list}" CACHE INTERNAL "")

# State accumulated by qmake_add_qemu_module before the QEMU project is defined.
set_property(GLOBAL PROPERTY QMAKE_QEMU_NEEDS_RUST FALSE)
set_property(GLOBAL PROPERTY QMAKE_MODULE_TARGETS "")
set_property(GLOBAL PROPERTY QMAKE_QEMU_EXTRA_TARGETS "")

# Called by the Rust module path to request --enable-rust on the QEMU build.
function(qmake_require_rust)
  set_property(GLOBAL PROPERTY QMAKE_QEMU_NEEDS_RUST TRUE)
endfunction()

# Module convenience targets register here so the finalizer can make them depend
# on the QEMU build (the build is defined later, after all modules are known).
function(qmake_register_module_target tgt)
  set_property(GLOBAL APPEND PROPERTY QMAKE_MODULE_TARGETS "${tgt}")
endfunction()

# Resolve the path to a built system emulator binary for a given short arch name
# (e.g. qmake_qemu_binary(BIN aarch64) -> .../qemu-system-aarch64).
function(qmake_qemu_binary out_var arch)
  set(${out_var} "${QMAKE_QEMU_BUILD_DIR}/qemu-system-${arch}" PARENT_SCOPE)
endfunction()

# The QEMU ExternalProject is defined here, deferred to the END of the top-level
# project so it can observe whether any LANG RUST module was registered and turn
# on --enable-rust automatically. Deferring on CMAKE_SOURCE_DIR makes this work
# for external consumers that add_subdirectory(qmake) and then declare modules.
function(_qmake_finalize_qemu)
  get_property(_needs_rust GLOBAL PROPERTY QMAKE_QEMU_NEEDS_RUST)

  set(_extra "")
  if(QMAKE_ENABLE_MODULES)
    list(APPEND _extra "--enable-modules")
  endif()
  if(_needs_rust OR QMAKE_ENABLE_RUST)
    list(APPEND _extra "--enable-rust")
  endif()
  separate_arguments(_user UNIX_COMMAND "${QMAKE_QEMU_CONFIGURE_ARGS}")

  # Out-of-tree targets (qmake_add_qemu_target) join the configured target list.
  get_property(_extra_targets GLOBAL PROPERTY QMAKE_QEMU_EXTRA_TARGETS)
  set(_target_list "${QMAKE_QEMU_TARGET_LIST}")
  foreach(t IN LISTS _extra_targets)
    string(FIND ",${_target_list}," ",${t}," _found)
    if(_found EQUAL -1 AND _target_list)
      set(_target_list "${_target_list},${t}")
    elseif(_found EQUAL -1)
      set(_target_list "${t}")
    endif()
  endforeach()

  ExternalProject_Add(qemu
    SOURCE_DIR        "${QMAKE_QEMU_DIR}"
    BINARY_DIR        "${QMAKE_QEMU_BUILD_DIR}"
    CONFIGURE_COMMAND "${QMAKE_QEMU_DIR}/configure"
                      "--target-list=${_target_list}"
                      ${_extra}
                      ${_user}
    # Re-run ninja every build: modules injected after first configure change
    # hw/meson.build, and meson/ninja auto-reconfigure on those changes.
    BUILD_COMMAND     ninja -C "${QMAKE_QEMU_BUILD_DIR}"
    BUILD_ALWAYS      TRUE
    INSTALL_COMMAND   ""
    USES_TERMINAL_CONFIGURE TRUE
    USES_TERMINAL_BUILD     TRUE
  )

  # Wire each registered module convenience target to the QEMU build.
  get_property(_targets GLOBAL PROPERTY QMAKE_MODULE_TARGETS)
  foreach(t IN LISTS _targets)
    if(TARGET "${t}")
      add_dependencies("${t}" qemu)
    endif()
  endforeach()

  list(JOIN _extra " " _extra_str)
  message(STATUS "qmake: QEMU source   = ${QMAKE_QEMU_DIR}")
  message(STATUS "qmake: QEMU build    = ${QMAKE_QEMU_BUILD_DIR}")
  message(STATUS "qmake: QEMU targets  = ${_target_list}")
  message(STATUS "qmake: QEMU configure extra = [${_extra_str}] (rust=${_needs_rust})")
endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL _qmake_finalize_qemu)
