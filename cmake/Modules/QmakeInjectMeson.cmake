# QmakeInjectMeson.cmake
#
# Statically links out-of-tree sources INTO QEMU by registering them in QEMU's
# own build system at configure time: each module gets a directory under
# hw/qmake-modules/<name>/ with a generated meson.build + Kconfig, and QEMU's
# hw/meson.build and hw/Kconfig are patched (idempotently, behind markers) to
# pull it in. QEMU's meson/Kconfig then handle per-target gating and linking.
#
# Public function:
#   qmake_inject_module(NAME <n> SRCDIR <dir> SOURCES <f...> [ARCHS <a...>])
#
# Reversibility: every edit to a tracked QEMU file sits between qmake markers, so
# `git -C $QMAKE_QEMU_DIR checkout hw/meson.build hw/Kconfig` plus
# `git -C $QMAKE_QEMU_DIR clean -fd hw/qmake-modules` fully reverts an injection.

include_guard(GLOBAL)

# These are module-level constants. They are stored as cache INTERNAL so they
# survive across directory scopes: include_guard(GLOBAL) means this file only
# runs once, so a plain set() would leave them undefined in sibling subdirs that
# include(QmakeAddModule) after the first.
set(QMAKE_INJECT_SUBDIR "qmake-modules" CACHE INTERNAL "")

# Map qmake short arch names -> QEMU Kconfig arch symbols (target/<arch>/Kconfig).
# Unknown names pass through upper-cased.
set(_QMAKE_ARCH_arm     "ARM"     CACHE INTERNAL "")
set(_QMAKE_ARCH_aarch64 "AARCH64" CACHE INTERNAL "")
set(_QMAKE_ARCH_x86     "X86_64"  CACHE INTERNAL "")
set(_QMAKE_ARCH_x86_64  "X86_64"  CACHE INTERNAL "")
set(_QMAKE_ARCH_riscv   "RISCV"   CACHE INTERNAL "")
set(_QMAKE_ARCH_mips    "MIPS"    CACHE INTERNAL "")
set(_QMAKE_ARCH_ppc     "PPC"     CACHE INTERNAL "")

function(_qmake_arch_symbol arch out_var)
  if(DEFINED _QMAKE_ARCH_${arch})
    set(${out_var} "${_QMAKE_ARCH_${arch}}" PARENT_SCOPE)
  else()
    string(TOUPPER "${arch}" _up)
    set(${out_var} "${_up}" PARENT_SCOPE)
  endif()
endfunction()

# Append `line` to a tracked QEMU file exactly once, behind a per-key marker.
# An optional 4th argument gives the marker's comment syntax, with @KEY@ standing
# for "qmake-inject: <key>" (default "# @KEY@"; C headers use "/* @KEY@ */").
function(_qmake_ensure_injected file key line)
  if(NOT EXISTS "${file}")
    message(FATAL_ERROR "qmake: cannot inject into '${file}' (not found). "
      "Is QMAKE_QEMU_DIR a real QEMU tree?")
  endif()
  set(_fmt "# @KEY@")
  if(ARGC GREATER 3)
    set(_fmt "${ARGV3}")
  endif()
  string(REPLACE "@KEY@" "qmake-inject: ${key}" _marker "${_fmt}")
  file(READ "${file}" _content)
  string(FIND "${_content}" "${_marker}" _pos)
  if(_pos EQUAL -1)
    file(APPEND "${file}" "\n${_marker}\n${line}\n")
    message(STATUS "qmake: injected into ${file}: ${line}")
  endif()
endfunction()

function(qmake_inject_module)
  cmake_parse_arguments(ARG "" "NAME;SRCDIR;SCOPE" "SOURCES;ARCHS;HEADERS;SELECTS" ${ARGN})
  if(NOT ARG_NAME OR NOT ARG_SRCDIR OR NOT ARG_SOURCES)
    message(FATAL_ERROR "qmake_inject_module: NAME, SRCDIR and SOURCES are required")
  endif()
  if(NOT DEFINED QMAKE_QEMU_DIR)
    message(FATAL_ERROR "qmake_inject_module: include(QmakeQemuBuild) first")
  endif()
  # SCOPE SYSTEM (default): build into system_ss, gated on a CONFIG_ Kconfig symbol
  #   (target-agnostic device code).
  # SCOPE TARGET: build into specific_ss, gated on TARGET_<arch> so the sources are
  #   compiled per-target (COMPILING_PER_TARGET) and may use target/<arch>/cpu.h.
  if(NOT ARG_SCOPE)
    set(ARG_SCOPE SYSTEM)
  endif()
  if(NOT ARG_SCOPE STREQUAL "SYSTEM" AND NOT ARG_SCOPE STREQUAL "TARGET")
    message(FATAL_ERROR "qmake_inject_module(${ARG_NAME}): SCOPE must be SYSTEM or TARGET")
  endif()
  if(ARG_SCOPE STREQUAL "TARGET" AND NOT ARG_ARCHS)
    message(FATAL_ERROR "qmake_inject_module(${ARG_NAME}): SCOPE TARGET requires ARCHS")
  endif()

  string(TOUPPER "${ARG_NAME}" _name_up)
  set(_config "QMAKE_${_name_up}")
  set(_hw "${QMAKE_QEMU_DIR}/hw")
  set(_moddir "${_hw}/${QMAKE_INJECT_SUBDIR}/${ARG_NAME}")

  file(MAKE_DIRECTORY "${_moddir}")

  # Symlink each source into the module dir (falls back to copy) and collect the
  # bare filenames meson's files() will reference.
  set(_files "")
  foreach(src IN LISTS ARG_SOURCES)
    if(IS_ABSOLUTE "${src}")
      set(_abs "${src}")
    else()
      set(_abs "${ARG_SRCDIR}/${src}")
    endif()
    if(NOT EXISTS "${_abs}")
      message(FATAL_ERROR "qmake_inject_module(${ARG_NAME}): source not found: ${_abs}")
    endif()
    get_filename_component(_fname "${_abs}" NAME)
    file(CREATE_LINK "${_abs}" "${_moddir}/${_fname}" SYMBOLIC COPY_ON_ERROR)
    list(APPEND _files "'${_fname}'")
  endforeach()
  list(JOIN _files ", " _files_csv)

  # Symlink HEADERS into the module dir so the sources' quote-includes
  # (#include "foo.h") resolve from the same directory (no -I plumbing needed).
  foreach(hdr IN LISTS ARG_HEADERS)
    if(IS_ABSOLUTE "${hdr}")
      set(_habs "${hdr}")
    else()
      set(_habs "${ARG_SRCDIR}/${hdr}")
    endif()
    if(NOT EXISTS "${_habs}")
      message(FATAL_ERROR "qmake_inject_module(${ARG_NAME}): header not found: ${_habs}")
    endif()
    get_filename_component(_hname "${_habs}" NAME)
    file(CREATE_LINK "${_habs}" "${_moddir}/${_hname}" SYMBOLIC COPY_ON_ERROR)
  endforeach()

  # Drop a version header beside the sources so a compat shim can guard QEMU API
  # differences across releases via #include "qmake_qemu_version.h".
  file(WRITE "${_moddir}/qmake_qemu_version.h"
    "/* Generated by qmake. QEMU version of QMAKE_QEMU_DIR. */\n"
    "#ifndef QMAKE_QEMU_VERSION_H\n#define QMAKE_QEMU_VERSION_H\n"
    "#define QMAKE_QEMU_VERSION_MAJOR ${QMAKE_QEMU_VER_MAJOR}\n"
    "#define QMAKE_QEMU_VERSION_MINOR ${QMAKE_QEMU_VER_MINOR}\n"
    "#define QMAKE_QEMU_VERSION_MICRO ${QMAKE_QEMU_VER_MICRO}\n"
    "#define QMAKE_QEMU_AT_LEAST(maj, min) \\\n"
    "    ((QMAKE_QEMU_VERSION_MAJOR > (maj)) || \\\n"
    "     (QMAKE_QEMU_VERSION_MAJOR == (maj) && QMAKE_QEMU_VERSION_MINOR >= (min)))\n"
    "#endif\n")

  if(ARG_SCOPE STREQUAL "SYSTEM")
    # Per-module meson.build: add to system_ss gated on our CONFIG_ symbol.
    # system_ss is in scope because hw/meson.build subdir()s us. meson's when:
    # references the CONFIG_-prefixed form that Kconfig emits.
    file(WRITE "${_moddir}/meson.build"
      "# Generated by qmake (qmake_inject_module). Do not edit by hand.\n"
      "system_ss.add(when: 'CONFIG_${_config}', if_true: files(${_files_csv}))\n")

    # Per-module Kconfig: default-on, optionally restricted to specific arch symbols.
    set(_kconfig
      "# Generated by qmake (qmake_inject_module). Do not edit by hand.\n"
      "config ${_config}\n"
      "    bool\n")
    if(ARG_ARCHS)
      foreach(arch IN LISTS ARG_ARCHS)
        _qmake_arch_symbol("${arch}" _sym)
        string(APPEND _kconfig "    default y if ${_sym}\n")
      endforeach()
    else()
      string(APPEND _kconfig "    default y\n")
    endif()
    # Pull in QEMU in-tree devices this module needs (Kconfig 'select'), so they
    # are compiled in whenever the module is, regardless of which boards build.
    foreach(sel IN LISTS ARG_SELECTS)
      string(APPEND _kconfig "    select ${sel}\n")
    endforeach()
    file(WRITE "${_moddir}/Kconfig" ${_kconfig})

    _qmake_ensure_injected("${_hw}/Kconfig" "${ARG_NAME}"
      "source ${QMAKE_INJECT_SUBDIR}/${ARG_NAME}/Kconfig")
  else()
    # SCOPE TARGET: add to specific_ss gated on TARGET_<arch> (one line per arch),
    # so sources compile per-target with access to target/<arch>/cpu.h. No Kconfig
    # symbol is needed — config_target already carries the TARGET_<arch> defines.
    set(_meson "# Generated by qmake (qmake_inject_module). Do not edit by hand.\n")
    foreach(arch IN LISTS ARG_ARCHS)
      _qmake_arch_symbol("${arch}" _sym)
      string(APPEND _meson
        "specific_ss.add(when: 'TARGET_${_sym}', if_true: files(${_files_csv}))\n")
    endforeach()
    file(WRITE "${_moddir}/meson.build" "${_meson}")
  endif()

  # Pull the module's sources into QEMU's build graph (idempotent).
  _qmake_ensure_injected("${_hw}/meson.build" "${ARG_NAME}"
    "subdir('${QMAKE_INJECT_SUBDIR}/${ARG_NAME}')")

  message(STATUS "qmake: registered out-of-tree module '${ARG_NAME}' "
    "(scope ${ARG_SCOPE}, ${_config})")
endfunction()

# Default QEMU Rust crates a SysBus device crate links against (the `*_rs` meson
# dependency objects defined in extern/qemu/rust). Override per-module with RUSTDEPS.
set(QMAKE_RUST_DEFAULT_DEPS
    "common_rs;util_rs;bql_rs;qom_rs;system_rs;hwcore_rs;glib_sys_rs" CACHE INTERNAL "")

# Statically link an out-of-tree Rust device crate INTO QEMU, mirroring how QEMU's
# in-tree Rust devices (rust/hw/char/pl011) are wired: build the crate as a Rust
# static_library and add it to rust_devices_ss with link_whole, gated on a Kconfig
# symbol. The crate uses QEMU's own rust crates (qom/system/...) so it needs no
# bindgen of its own. Registered under extern/qemu/rust/hw/qmake-<name>/.
#
#   qmake_inject_rust_module(NAME <n> SRCDIR <d> SOURCES <f...>
#                            [CRATE <crate>] [ARCHS <a...>] [RUSTDEPS <dep...>])
function(qmake_inject_rust_module)
  cmake_parse_arguments(ARG "" "NAME;SRCDIR;CRATE" "SOURCES;ARCHS;RUSTDEPS" ${ARGN})
  if(NOT ARG_NAME OR NOT ARG_SRCDIR OR NOT ARG_SOURCES)
    message(FATAL_ERROR "qmake_inject_rust_module: NAME, SRCDIR and SOURCES are required")
  endif()
  if(NOT ARG_CRATE)
    string(REPLACE "-" "_" ARG_CRATE "${ARG_NAME}")
  endif()
  if(NOT ARG_RUSTDEPS)
    set(ARG_RUSTDEPS ${QMAKE_RUST_DEFAULT_DEPS})
  endif()

  string(TOUPPER "${ARG_NAME}" _name_up)
  set(_config "QMAKE_${_name_up}")
  set(_rusthw "${QMAKE_QEMU_DIR}/rust/hw")
  set(_moddir "${_rusthw}/qmake-${ARG_NAME}")
  file(MAKE_DIRECTORY "${_moddir}/src")

  # Symlink crate sources into the module's src/ (lib.rs must sit beside its mods).
  set(_srcs "")
  foreach(src IN LISTS ARG_SOURCES)
    if(IS_ABSOLUTE "${src}")
      set(_abs "${src}")
    else()
      set(_abs "${ARG_SRCDIR}/${src}")
    endif()
    if(NOT EXISTS "${_abs}")
      message(FATAL_ERROR "qmake_inject_rust_module(${ARG_NAME}): source not found: ${_abs}")
    endif()
    get_filename_component(_fname "${_abs}" NAME)
    file(CREATE_LINK "${_abs}" "${_moddir}/src/${_fname}" SYMBOLIC COPY_ON_ERROR)
    list(APPEND _srcs "'src/${_fname}'")
  endforeach()
  list(JOIN _srcs ", " _srcs_csv)
  list(JOIN ARG_RUSTDEPS ", " _deps_csv)

  # meson.build: build the rust crate + add to rust_devices_ss (link_whole) so its
  # QOM type constructors are linked into the emulator. CONFIG_-prefixed gate.
  file(WRITE "${_moddir}/meson.build"
    "# Generated by qmake (qmake_inject_rust_module). Do not edit by hand.\n"
    "_lib_${ARG_CRATE} = static_library(\n"
    "  '${ARG_CRATE}',\n"
    "  structured_sources([${_srcs_csv}]),\n"
    "  override_options: ['rust_std=2021', 'build.rust_std=2021'],\n"
    "  rust_abi: 'rust',\n"
    "  dependencies: [${_deps_csv}],\n"
    ")\n"
    "rust_devices_ss.add(when: 'CONFIG_${_config}', if_true: [declare_dependency(\n"
    "  link_whole: [_lib_${ARG_CRATE}],\n"
    "  variables: {'crate': '${ARG_CRATE}'},\n"
    ")])\n")

  # Kconfig: only meaningful when Rust is available (HAVE_RUST), optionally arch-gated.
  set(_kconfig
    "# Generated by qmake (qmake_inject_rust_module). Do not edit by hand.\n"
    "config ${_config}\n"
    "    bool\n")
  if(ARG_ARCHS)
    foreach(arch IN LISTS ARG_ARCHS)
      _qmake_arch_symbol("${arch}" _sym)
      string(APPEND _kconfig "    default y if HAVE_RUST && ${_sym}\n")
    endforeach()
  else()
    string(APPEND _kconfig "    default y if HAVE_RUST\n")
  endif()
  file(WRITE "${_moddir}/Kconfig" ${_kconfig})

  # Pull into QEMU's rust build + config graph (idempotent). rust/Kconfig sources
  # rust/hw/Kconfig; rust/meson.build subdir()s rust/hw which subdir()s devices.
  _qmake_ensure_injected("${_rusthw}/meson.build" "rust-${ARG_NAME}"
    "subdir('qmake-${ARG_NAME}')")
  _qmake_ensure_injected("${_rusthw}/Kconfig" "rust-${ARG_NAME}"
    "source qmake-${ARG_NAME}/Kconfig")

  message(STATUS "qmake: registered out-of-tree Rust module '${ARG_NAME}' "
    "(crate ${ARG_CRATE}, ${_config})")
endfunction()

# Statically link an out-of-tree *Cargo* crate (crate-type = ["staticlib"]) into
# QEMU, alongside optional C glue sources compiled by QEMU's meson with full
# per-target flags. Unlike qmake_inject_rust_module (which builds through QEMU's
# meson Rust support and only sees QEMU's in-tree crates), this runs real cargo,
# so the crate may use any crates.io/git dependencies.
#
# cargo runs as a meson custom_target inside QEMU's own ninja graph, with cargo's
# dep-info as its depfile: it is ordered before the emulator link and re-run (and
# QEMU relinked) exactly when one of the crate's sources changes. build.rs sees
# QEMU_SRC_ROOT / QEMU_BUILD_ROOT in its environment.
#
#   qmake_inject_cargo_module(NAME <n> SRCDIR <d> MANIFEST <Cargo.toml> CRATE <lib_name>
#                             [SOURCES <c glue...>] [HEADERS <h...>] [ARCHS <a...>]
#                             [SCOPE SYSTEM|TARGET] [PROFILE release|dev]
#                             [LINK_ARGS <args...>])
set(QMAKE_CARGO_DEFAULT_LINK_ARGS "-lgcc_s;-lutil;-lrt;-lpthread;-lm;-ldl" CACHE INTERNAL "")

function(qmake_inject_cargo_module)
  cmake_parse_arguments(ARG "" "NAME;SRCDIR;MANIFEST;CRATE;SCOPE;PROFILE"
                        "SOURCES;HEADERS;ARCHS;LINK_ARGS" ${ARGN})
  if(NOT ARG_NAME OR NOT ARG_SRCDIR OR NOT ARG_MANIFEST OR NOT ARG_CRATE)
    message(FATAL_ERROR "qmake_inject_cargo_module: NAME, SRCDIR, MANIFEST and CRATE are required")
  endif()
  if(NOT ARG_SCOPE)
    set(ARG_SCOPE SYSTEM)
  endif()
  if(ARG_SCOPE STREQUAL "TARGET" AND NOT ARG_ARCHS)
    message(FATAL_ERROR "qmake_inject_cargo_module(${ARG_NAME}): SCOPE TARGET requires ARCHS")
  endif()
  if(NOT ARG_PROFILE)
    set(ARG_PROFILE release)
  endif()
  if(NOT ARG_LINK_ARGS)
    set(ARG_LINK_ARGS ${QMAKE_CARGO_DEFAULT_LINK_ARGS})
  endif()
  if(NOT IS_ABSOLUTE "${ARG_MANIFEST}")
    set(ARG_MANIFEST "${ARG_SRCDIR}/${ARG_MANIFEST}")
  endif()
  find_program(QMAKE_CARGO cargo HINTS "$ENV{HOME}/.cargo/bin" REQUIRED)

  string(TOUPPER "${ARG_NAME}" _name_up)
  set(_config "QMAKE_${_name_up}")
  set(_hw "${QMAKE_QEMU_DIR}/hw")
  set(_moddir "${_hw}/${QMAKE_INJECT_SUBDIR}/${ARG_NAME}")
  file(MAKE_DIRECTORY "${_moddir}")

  set(_files "")
  foreach(src IN LISTS ARG_SOURCES ARG_HEADERS)
    if(IS_ABSOLUTE "${src}")
      set(_abs "${src}")
    else()
      set(_abs "${ARG_SRCDIR}/${src}")
    endif()
    if(NOT EXISTS "${_abs}")
      message(FATAL_ERROR "qmake_inject_cargo_module(${ARG_NAME}): file not found: ${_abs}")
    endif()
    get_filename_component(_fname "${_abs}" NAME)
    file(CREATE_LINK "${_abs}" "${_moddir}/${_fname}" SYMBOLIC COPY_ON_ERROR)
    if(src IN_LIST ARG_SOURCES)
      list(APPEND _files "'${_fname}'")
    endif()
  endforeach()
  list(JOIN _files ", " _files_csv)

  set(_link "")
  foreach(a IN LISTS ARG_LINK_ARGS)
    list(APPEND _link "'${a}'")
  endforeach()
  list(JOIN _link ", " _link_csv)

  set(_v "_qmake_${ARG_NAME}")
  set(_script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../scripts/qmake_cargo_build.py")
  get_filename_component(_script "${_script}" ABSOLUTE)
  string(CONCAT _meson
    "# Generated by qmake (qmake_inject_cargo_module). Do not edit by hand.\n"
    "${_v}_cargo = custom_target('qmake-${ARG_NAME}-cargo',\n"
    "  output: 'lib${ARG_CRATE}.a',\n"
    "  depfile: 'lib${ARG_CRATE}.a.d',\n"
    "  command: [python, '${_script}',\n"
    "            '--cargo', '${QMAKE_CARGO}',\n"
    "            '--manifest', '${ARG_MANIFEST}',\n"
    "            '--crate', '${ARG_CRATE}',\n"
    "            '--profile', '${ARG_PROFILE}',\n"
    "            '--target-dir', meson.current_build_dir() / 'cargo-target',\n"
    "            '--out', '@OUTPUT@', '--depfile', '@DEPFILE@',\n"
    "            '--env', 'QEMU_SRC_ROOT=' + meson.project_source_root(),\n"
    "            '--env', 'QEMU_BUILD_ROOT=' + meson.project_build_root()],\n"
    "  console: true)\n"
    "${_v}_dep = declare_dependency(link_with: ${_v}_cargo,\n"
    "  link_args: [${_link_csv}])\n")
  if(_files_csv)
    set(_srcs "files(${_files_csv}), ")
  else()
    set(_srcs "")
  endif()

  if(ARG_SCOPE STREQUAL "SYSTEM")
    string(APPEND _meson
      "system_ss.add(when: 'CONFIG_${_config}', if_true: [${_srcs}${_v}_dep])\n")
    set(_kconfig "# Generated by qmake (qmake_inject_cargo_module). Do not edit by hand.\nconfig ${_config}\n    bool\n")
    if(ARG_ARCHS)
      foreach(arch IN LISTS ARG_ARCHS)
        _qmake_arch_symbol("${arch}" _sym)
        string(APPEND _kconfig "    default y if ${_sym}\n")
      endforeach()
    else()
      string(APPEND _kconfig "    default y\n")
    endif()
    file(WRITE "${_moddir}/Kconfig" "${_kconfig}")
    _qmake_ensure_injected("${_hw}/Kconfig" "${ARG_NAME}"
      "source ${QMAKE_INJECT_SUBDIR}/${ARG_NAME}/Kconfig")
  else()
    foreach(arch IN LISTS ARG_ARCHS)
      _qmake_arch_symbol("${arch}" _sym)
      string(APPEND _meson
        "specific_ss.add(when: 'TARGET_${_sym}', if_true: [${_srcs}${_v}_dep])\n")
    endforeach()
  endif()
  file(WRITE "${_moddir}/meson.build" "${_meson}")

  _qmake_ensure_injected("${_hw}/meson.build" "${ARG_NAME}"
    "subdir('${QMAKE_INJECT_SUBDIR}/${ARG_NAME}')")

  message(STATUS "qmake: registered out-of-tree Cargo module '${ARG_NAME}' "
    "(crate ${ARG_CRATE}, scope ${ARG_SCOPE})")
endfunction()
