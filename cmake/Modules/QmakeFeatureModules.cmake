# QmakeFeatureModules.cmake
#
# Defines INTERFACE IMPORTED targets that carry the QEMU compile environment for
# out-of-tree code that is *not* compiled by QEMU's own meson (i.e. the LD_PRELOAD
# / --enable-modules / Rust-bindgen / standalone-lint paths, and IDEs):
#
#   qmake::osdep         core include dirs + base defines + glib; lets a TU
#                        #include "qemu/osdep.h" and the QOM/hw headers.
#   qmake::qapi          osdep + the generated qapi header dir (<build>/qapi).
#   qmake::log           osdep (qemu/log.h lives in include/, covered by osdep).
#   qmake::qom           osdep (qom/object.h likewise).
#   qmake::target-<arch> osdep + per-target include dir + -DCOMPILING_PER_TARGET;
#                        attach this to mark a module target-specific (ARM-only).
#
# Requires QmakeIntrospect to have populated QMAKE_OSDEP_* etc. If introspection
# has not run yet (clean tree, QEMU unbuilt) the targets are skipped; re-run cmake
# after the first build.

include_guard(GLOBAL)

if(NOT QMAKE_INTROSPECTION_OK)
  message(STATUS "qmake: feature modules not defined yet (QEMU introspection unavailable).")
  return()
endif()

# Base: qmake::osdep
if(NOT TARGET qmake::osdep)
  add_library(qmake_osdep INTERFACE)
  add_library(qmake::osdep ALIAS qmake_osdep)
  target_include_directories(qmake_osdep SYSTEM INTERFACE ${QMAKE_OSDEP_INCLUDE_DIRS})
  target_compile_definitions(qmake_osdep INTERFACE ${QMAKE_OSDEP_DEFINES})
  foreach(fi IN LISTS QMAKE_OSDEP_FORCED_INCLUDES)
    target_compile_options(qmake_osdep INTERFACE "-include" "${fi}")
  endforeach()
  if(TARGET PkgConfig::GLIB)
    target_link_libraries(qmake_osdep INTERFACE PkgConfig::GLIB)
  endif()
endif()

# qapi: osdep + generated qapi headers
if(NOT TARGET qmake::qapi)
  add_library(qmake_qapi INTERFACE)
  add_library(qmake::qapi ALIAS qmake_qapi)
  target_link_libraries(qmake_qapi INTERFACE qmake::osdep)
  target_include_directories(qmake_qapi SYSTEM INTERFACE ${QMAKE_QAPI_INCLUDE_DIRS})
endif()

# log / qom: header groupings on top of osdep
foreach(feat log qom)
  if(NOT TARGET qmake::${feat})
    add_library(qmake_${feat} INTERFACE)
    add_library(qmake::${feat} ALIAS qmake_${feat})
    target_link_libraries(qmake_${feat} INTERFACE qmake::osdep)
  endif()
endforeach()

# Per-target feature modules (ARM-only etc.)
foreach(arch IN LISTS QMAKE_INTROSPECTED_ARCHS)
  if(NOT TARGET qmake::target-${arch})
    add_library(qmake_target_${arch} INTERFACE)
    add_library(qmake::target-${arch} ALIAS qmake_target_${arch})
    target_link_libraries(qmake_target_${arch} INTERFACE qmake::osdep)
    if(QMAKE_TARGET_${arch}_INCLUDE_DIRS)
      target_include_directories(qmake_target_${arch} SYSTEM INTERFACE
        ${QMAKE_TARGET_${arch}_INCLUDE_DIRS})
    endif()
    if(QMAKE_TARGET_${arch}_DEFINES)
      target_compile_definitions(qmake_target_${arch} INTERFACE
        ${QMAKE_TARGET_${arch}_DEFINES})
    endif()
  endif()
endforeach()

message(STATUS "qmake: feature modules ready (qmake::osdep qapi log qom; "
  "targets: ${QMAKE_INTROSPECTED_ARCHS})")
