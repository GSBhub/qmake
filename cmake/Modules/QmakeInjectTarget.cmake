# QmakeInjectTarget.cmake
#
# Registers an entirely new guest *target* (CPU architecture) into a QEMU tree,
# out of tree, the same way QmakeInjectMeson registers devices: generated files go
# into new paths, and every edit to a tracked QEMU file sits behind a
# `# qmake-inject:` marker so it is idempotent and reversible.
#
#   qmake_add_qemu_target(
#     NAME        <name>          # QEMU arch name, e.g. pcode -> qemu-system-pcode
#     SRCDIR      <dir>           # target sources (cpu.c, cpu.h, translate.c, meson.build...)
#     [SOURCES    <files...>]     # files in SRCDIR to link into target/<name>/ (default: all)
#     [MODES      softmmu linux-user]  # default: softmmu
#     [USER_DIR   <dir>]          # linux-user/<name>/ sources (cpu_loop.c, elfload.c,
#                                 #   signal.c, target_*.h, meson.build); MODES linux-user
#     [USER_LONG_BITS 32|64]      # TARGET_LONG_BITS for linux-user (default LONG_BITS)
#     [USER_MAK   <KEY=VALUE...>] # extra lines for <name>-linux-user.mak
#                                 #   (e.g. TARGET_SYSTBL=syscall.tbl TARGET_SYSTBL_ABI=common)
#     [LONG_BITS  32|64]          # TARGET_LONG_BITS (default 32)
#     [BIG_ENDIAN]                # TARGET_BIG_ENDIAN=y
#     [XML_FILES  <gdb-xml...>]   # TARGET_XML_FILES: files in SRCDIR (linked into
#                                 #   gdb-xml/) or existing QEMU paths
#     [DEVICES    <CONFIG_X=y...>]# lines for configs/devices/<name>-softmmu/default.mak
#     [ARCH_BIT   <n>]            # bit used for QEMU_ARCH_<NAME> (default 30)
#   )
#
# Touchpoints in a QEMU 10.2 tree:
#   new:     target/<name>/*                       (symlinks to SRCDIR)
#            linux-user/<name>/*                   (symlinks to USER_DIR)
#            configs/targets/<name>-linux-user.mak
#            gdb-xml/<file>                        (XML_FILES found in SRCDIR)
#            configs/targets/<name>-softmmu.mak
#            configs/devices/<name>-softmmu/default.mak
#   marked:  target/meson.build      subdir('<name>')
#            linux-user/meson.build  subdir('<name>')   (linux-user only)
#            target/Kconfig          source <name>/Kconfig
#            qapi/machine.json       '<name>' in the SysEmuTarget enum
#            include/system/arch_init.h   #define QEMU_ARCH_<NAME>
#
# Reverting: `git -C $QMAKE_QEMU_DIR checkout target qapi include` and
# `git -C $QMAKE_QEMU_DIR clean -fd target configs gdb-xml linux-user`.

include_guard(GLOBAL)
include(QmakeInjectMeson)   # _qmake_ensure_injected

# Insert `text` into `file` immediately after the first match of `anchor` that
# follows the first match of `after`, exactly once (keyed by a marker). Used for
# the few edits that cannot be appends (e.g. a qapi enum's member list).
function(_qmake_ensure_inserted file key after anchor text)
  set(_marker "# qmake-inject: ${key}")
  file(READ "${file}" _content)
  string(FIND "${_content}" "${_marker}" _pos)
  if(NOT _pos EQUAL -1)
    return()
  endif()
  string(FIND "${_content}" "${after}" _apos)
  if(_apos EQUAL -1)
    message(FATAL_ERROR "qmake: anchor '${after}' not found in ${file}")
  endif()
  string(SUBSTRING "${_content}" 0 ${_apos} _head)
  string(SUBSTRING "${_content}" ${_apos} -1 _tail)
  string(FIND "${_tail}" "${anchor}" _npos)
  if(_npos EQUAL -1)
    message(FATAL_ERROR "qmake: anchor '${anchor}' not found after '${after}' in ${file}")
  endif()
  string(LENGTH "${anchor}" _alen)
  math(EXPR _split "${_npos} + ${_alen}")
  string(SUBSTRING "${_tail}" 0 ${_split} _t0)
  string(SUBSTRING "${_tail}" ${_split} -1 _t1)
  string(REPLACE "@MARKER@" "${_marker}" _text "${text}")
  file(WRITE "${file}" "${_head}${_t0}${_text}${_t1}")
  message(STATUS "qmake: inserted into ${file}: ${key}")
endfunction()

function(qmake_add_qemu_target)
  cmake_parse_arguments(ARG "BIG_ENDIAN" "NAME;SRCDIR;LONG_BITS;ARCH_BIT;USER_DIR;USER_LONG_BITS"
                        "SOURCES;MODES;XML_FILES;DEVICES;USER_MAK" ${ARGN})
  if(NOT ARG_NAME OR NOT ARG_SRCDIR)
    message(FATAL_ERROR "qmake_add_qemu_target: NAME and SRCDIR are required")
  endif()
  if(NOT DEFINED QMAKE_QEMU_DIR)
    message(FATAL_ERROR "qmake_add_qemu_target: include(QmakeQemuBuild) first")
  endif()
  if(NOT IS_ABSOLUTE "${ARG_SRCDIR}")
    set(ARG_SRCDIR "${CMAKE_CURRENT_SOURCE_DIR}/${ARG_SRCDIR}")
  endif()
  if(NOT ARG_MODES)
    set(ARG_MODES softmmu)
  endif()
  if(NOT ARG_LONG_BITS)
    set(ARG_LONG_BITS 32)
  endif()
  if(NOT ARG_ARCH_BIT)
    set(ARG_ARCH_BIT 30)
  endif()
  if(NOT ARG_USER_LONG_BITS)
    set(ARG_USER_LONG_BITS ${ARG_LONG_BITS})
  endif()
  foreach(mode IN LISTS ARG_MODES)
    if(NOT mode MATCHES "^(softmmu|linux-user)$")
      message(FATAL_ERROR "qmake_add_qemu_target(${ARG_NAME}): unknown MODE '${mode}'")
    endif()
  endforeach()
  if("linux-user" IN_LIST ARG_MODES AND NOT ARG_USER_DIR)
    message(FATAL_ERROR "qmake_add_qemu_target(${ARG_NAME}): MODES linux-user needs USER_DIR")
  endif()
  if(ARG_USER_DIR AND NOT IS_ABSOLUTE "${ARG_USER_DIR}")
    set(ARG_USER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/${ARG_USER_DIR}")
  endif()

  set(_q "${QMAKE_QEMU_DIR}")
  string(TOUPPER "${ARG_NAME}" _up)

  # --- target/<name>/: per-file symlinks into a real directory ----------------
  if(NOT ARG_SOURCES)
    file(GLOB ARG_SOURCES RELATIVE "${ARG_SRCDIR}" "${ARG_SRCDIR}/*")
  endif()
  set(_tdir "${_q}/target/${ARG_NAME}")
  file(MAKE_DIRECTORY "${_tdir}")
  set(_have_kconfig FALSE)
  foreach(src IN LISTS ARG_SOURCES)
    if(IS_ABSOLUTE "${src}")
      set(_abs "${src}")
    else()
      set(_abs "${ARG_SRCDIR}/${src}")
    endif()
    if(NOT EXISTS "${_abs}")
      message(FATAL_ERROR "qmake_add_qemu_target(${ARG_NAME}): source not found: ${_abs}")
    endif()
    get_filename_component(_fname "${_abs}" NAME)
    if(_fname STREQUAL "Kconfig")
      set(_have_kconfig TRUE)
    endif()
    file(CREATE_LINK "${_abs}" "${_tdir}/${_fname}" SYMBOLIC COPY_ON_ERROR)
  endforeach()
  if(NOT EXISTS "${_tdir}/meson.build")
    message(FATAL_ERROR "qmake_add_qemu_target(${ARG_NAME}): ${ARG_SRCDIR} must provide a "
      "meson.build that defines target_arch/target_system_arch['${ARG_NAME}']")
  endif()
  if(NOT _have_kconfig)
    file(WRITE "${_tdir}/Kconfig"
      "# Generated by qmake (qmake_add_qemu_target). Do not edit by hand.\n"
      "config ${_up}\n    bool\n")
  endif()

  # --- configs ---------------------------------------------------------------
  string(CONCAT _mak "# Generated by qmake (qmake_add_qemu_target). Do not edit by hand.\n"
           "TARGET_ARCH=${ARG_NAME}\n"
           "TARGET_LONG_BITS=${ARG_LONG_BITS}\n")
  if(ARG_BIG_ENDIAN)
    string(APPEND _mak "TARGET_BIG_ENDIAN=y\n")
  endif()
  if(ARG_XML_FILES)
    # Files in SRCDIR are linked into QEMU's gdb-xml/; other entries are taken
    # as existing QEMU paths (e.g. gdb-xml/arm-core.xml).
    set(_xml "")
    foreach(x IN LISTS ARG_XML_FILES)
      if(EXISTS "${ARG_SRCDIR}/${x}")
        get_filename_component(_xname "${x}" NAME)
        file(CREATE_LINK "${ARG_SRCDIR}/${x}" "${_q}/gdb-xml/${_xname}" SYMBOLIC COPY_ON_ERROR)
        list(APPEND _xml "gdb-xml/${_xname}")
      else()
        list(APPEND _xml "${x}")
      endif()
    endforeach()
    list(JOIN _xml " " _xml)
    string(APPEND _mak "TARGET_XML_FILES=${_xml}\n")
  endif()
  if("softmmu" IN_LIST ARG_MODES)
    file(WRITE "${_q}/configs/targets/${ARG_NAME}-softmmu.mak" "${_mak}")
  endif()

  # --- linux-user ---------------------------------------------------------
  if("linux-user" IN_LIST ARG_MODES)
    string(REPLACE "TARGET_LONG_BITS=${ARG_LONG_BITS}" "TARGET_LONG_BITS=${ARG_USER_LONG_BITS}"
           _umak "${_mak}")
    foreach(line IN LISTS ARG_USER_MAK)
      string(APPEND _umak "${line}\n")
    endforeach()
    file(WRITE "${_q}/configs/targets/${ARG_NAME}-linux-user.mak" "${_umak}")

    set(_udir "${_q}/linux-user/${ARG_NAME}")
    file(MAKE_DIRECTORY "${_udir}")
    file(GLOB _ufiles RELATIVE "${ARG_USER_DIR}" "${ARG_USER_DIR}/*")
    foreach(f IN LISTS _ufiles)
      file(CREATE_LINK "${ARG_USER_DIR}/${f}" "${_udir}/${f}" SYMBOLIC COPY_ON_ERROR)
    endforeach()
    if(NOT EXISTS "${_udir}/meson.build")
      file(WRITE "${_udir}/meson.build" "# Generated by qmake (qmake_add_qemu_target).\n")
    endif()
    _qmake_ensure_injected("${_q}/linux-user/meson.build" "target-${ARG_NAME}"
      "subdir('${ARG_NAME}')")
  endif()

  set(_dev "# Generated by qmake (qmake_add_qemu_target). Do not edit by hand.\n")
  foreach(line IN LISTS ARG_DEVICES)
    string(APPEND _dev "${line}\n")
  endforeach()
  file(MAKE_DIRECTORY "${_q}/configs/devices/${ARG_NAME}-softmmu")
  file(WRITE "${_q}/configs/devices/${ARG_NAME}-softmmu/default.mak" ${_dev})

  # --- marked edits to tracked files -----------------------------------------
  _qmake_ensure_injected("${_q}/target/meson.build" "target-${ARG_NAME}"
    "subdir('${ARG_NAME}')")
  _qmake_ensure_injected("${_q}/target/Kconfig" "target-${ARG_NAME}"
    "source ${ARG_NAME}/Kconfig")
  # QEMU_ARCH is an enum; a macro after the include guard is equivalent for the
  # `QEMU_ARCH QEMU_ARCH_<NAME>` define meson writes into config-target.h.
  _qmake_ensure_injected("${_q}/include/system/arch_init.h" "target-${ARG_NAME}"
    "#define QEMU_ARCH_${_up} (1 << ${ARG_ARCH_BIT})" "/* @KEY@ */")
  # SysEmuTarget is a list, not an append point: insert the member right after
  # the opening bracket, with the marker as a qapi comment on the same line.
  _qmake_ensure_inserted("${_q}/qapi/machine.json" "target-${ARG_NAME}"
    "'enum' : 'SysEmuTarget'" "'data' : ["
    " '${ARG_NAME}', @MARKER@\n            ")

  # Make sure the target is in the configure --target-list.
  get_property(_extra GLOBAL PROPERTY QMAKE_QEMU_EXTRA_TARGETS)
  foreach(mode IN LISTS ARG_MODES)
    list(APPEND _extra "${ARG_NAME}-${mode}")
  endforeach()
  set_property(GLOBAL PROPERTY QMAKE_QEMU_EXTRA_TARGETS "${_extra}")

  set(_QMAKE_ARCH_${ARG_NAME} "${_up}" CACHE INTERNAL "")
  message(STATUS "qmake: registered out-of-tree target '${ARG_NAME}' (${ARG_MODES})")
endfunction()
