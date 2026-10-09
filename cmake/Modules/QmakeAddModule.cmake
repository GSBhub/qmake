# QmakeAddModule.cmake
#
# Public entry point for declaring an out-of-tree QEMU module.
#
#   qmake_add_qemu_module(
#     NAME      <name>            # module + QOM-ish identifier
#     LANG      C|RUST            # default C
#     SOURCES   <files...>        # relative to the calling CMakeLists dir
#     TARGETS   <arch...>         # arch gating, e.g. arm (omit = all targets)
#     LINKAGE   STATIC|PRELOAD|MODULE   # default STATIC
#     FEATURES  <feat...>         # extra qmake:: feature modules (qapi log ...)
#   )
#
# v1 implements LINKAGE STATIC: the sources are injected into QEMU's own build
# (see QmakeInjectMeson) and statically linked into the emulator, with per-target
# gating handled by QEMU's Kconfig. PRELOAD / MODULE / RUST are accepted by the
# API but not yet built (clear error) -- the wiring is staged for later.

include_guard(GLOBAL)
include(QmakeInjectMeson)

function(qmake_add_qemu_module)
  cmake_parse_arguments(ARG "" "NAME;LANG;LINKAGE;CRATE;SCOPE;MANIFEST;PROFILE"
                        "SOURCES;TARGETS;FEATURES;RUSTDEPS;HEADERS;SELECTS;LINK_ARGS" ${ARGN})

  if(NOT ARG_NAME)
    message(FATAL_ERROR "qmake_add_qemu_module: NAME is required")
  endif()
  if(NOT ARG_SOURCES AND NOT ARG_LANG STREQUAL "CARGO")
    message(FATAL_ERROR "qmake_add_qemu_module(${ARG_NAME}): SOURCES is required")
  endif()
  if(NOT ARG_LANG)
    set(ARG_LANG C)
  endif()
  if(NOT ARG_LINKAGE)
    set(ARG_LINKAGE STATIC)
  endif()
  # SCOPE SYSTEM (default) -> system_ss; SCOPE TARGET -> specific_ss (per-target,
  # for code that touches CPU internals). SCOPE TARGET requires TARGETS.
  if(NOT ARG_SCOPE)
    set(ARG_SCOPE SYSTEM)
  endif()

  if(NOT ARG_LANG MATCHES "^(C|RUST|CARGO)$")
    message(FATAL_ERROR "qmake_add_qemu_module(${ARG_NAME}): LANG must be C, RUST or CARGO")
  endif()

  # Cargo path: build a staticlib crate with real cargo (any dependencies) inside
  # QEMU's ninja graph and link it, plus optional C glue SOURCES, into QEMU.
  if(ARG_LANG STREQUAL "CARGO")
    if(NOT ARG_MANIFEST OR NOT ARG_CRATE)
      message(FATAL_ERROR
        "qmake_add_qemu_module(${ARG_NAME}): LANG CARGO requires MANIFEST and CRATE")
    endif()
    qmake_inject_cargo_module(
      NAME      "${ARG_NAME}"
      SRCDIR    "${CMAKE_CURRENT_SOURCE_DIR}"
      MANIFEST  "${ARG_MANIFEST}"
      CRATE     "${ARG_CRATE}"
      SOURCES   ${ARG_SOURCES}
      HEADERS   ${ARG_HEADERS}
      ARCHS     ${ARG_TARGETS}
      SCOPE     "${ARG_SCOPE}"
      PROFILE   "${ARG_PROFILE}"
      LINK_ARGS ${ARG_LINK_ARGS})
    if(NOT TARGET "${ARG_NAME}")
      add_custom_target("${ARG_NAME}" ALL
        COMMENT "qmake Cargo module '${ARG_NAME}' is statically linked into QEMU")
      qmake_register_module_target("${ARG_NAME}")
    endif()
    return()
  endif()

  # Rust path: reuse QEMU's in-tree rust crates, link the crate into QEMU via the
  # rust_devices_ss mechanism, and auto-enable --enable-rust on the QEMU build.
  if(ARG_LANG STREQUAL "RUST")
    if(ARG_LINKAGE AND NOT ARG_LINKAGE STREQUAL "STATIC")
      message(FATAL_ERROR
        "qmake_add_qemu_module(${ARG_NAME}): Rust modules currently support LINKAGE STATIC only")
    endif()
    qmake_require_rust()
    qmake_inject_rust_module(
      NAME     "${ARG_NAME}"
      SRCDIR   "${CMAKE_CURRENT_SOURCE_DIR}"
      SOURCES  ${ARG_SOURCES}
      CRATE    "${ARG_CRATE}"
      ARCHS    ${ARG_TARGETS}
      RUSTDEPS ${ARG_RUSTDEPS})
    if(NOT TARGET "${ARG_NAME}")
      add_custom_target("${ARG_NAME}" ALL
        COMMENT "qmake Rust module '${ARG_NAME}' is statically linked into QEMU")
      qmake_register_module_target("${ARG_NAME}")
    endif()
    return()
  endif()

  if(NOT ARG_LINKAGE STREQUAL "STATIC")
    message(FATAL_ERROR
      "qmake_add_qemu_module(${ARG_NAME}): LINKAGE=${ARG_LINKAGE} not yet built in v1 "
      "(STATIC only). PRELOAD/MODULE will build a .so against the qmake:: feature "
      "modules and are staged for a later milestone.")
  endif()

  # STATIC: register the sources into QEMU's build graph and tie a convenience
  # target to the QEMU build so `cmake --build . --target <name>` produces an
  # emulator with the module statically linked in.
  qmake_inject_module(
    NAME    "${ARG_NAME}"
    SRCDIR  "${CMAKE_CURRENT_SOURCE_DIR}"
    SOURCES ${ARG_SOURCES}
    HEADERS ${ARG_HEADERS}
    ARCHS   ${ARG_TARGETS}
    SELECTS ${ARG_SELECTS}
    SCOPE   "${ARG_SCOPE}")

  if(NOT TARGET "${ARG_NAME}")
    add_custom_target("${ARG_NAME}" ALL
      COMMENT "qmake module '${ARG_NAME}' is statically linked into QEMU")
    # The QEMU build is defined by a deferred finalizer (so it can auto-enable
    # rust once all modules are known); register for dependency wiring there.
    qmake_register_module_target("${ARG_NAME}")
  endif()

  if(ARG_FEATURES)
    message(STATUS "qmake: module '${ARG_NAME}' requested features '${ARG_FEATURES}' "
      "(used by non-static load paths; static link uses QEMU's own flags).")
  endif()
endfunction()
