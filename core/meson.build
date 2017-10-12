# Meson file for Vibe Core

vibe_core_src_dir = include_directories('.')

vibe_core_src = [
    'vibe/appmain.d',
    'vibe/core/args.d',
    'vibe/core/concurrency.d',
    'vibe/core/connectionpool.d',
    'vibe/core/core.d',
    'vibe/core/driver.d',
    'vibe/core/drivers/libasync.d',
    'vibe/core/drivers/libevent2.d',
    'vibe/core/drivers/libevent2_tcp.d',
    'vibe/core/drivers/native.d',
    'vibe/core/drivers/threadedfile.d',
    'vibe/core/drivers/timerqueue.d',
    'vibe/core/drivers/utils.d',
    'vibe/core/drivers/win32.d',
    'vibe/core/drivers/winrt.d',
    'vibe/core/file.d',
    'vibe/core/log.d',
    'vibe/core/net.d',
    'vibe/core/path.d',
    'vibe/core/stream.d',
    'vibe/core/sync.d',
    'vibe/core/task.d',
    'vibe/internal/allocator.d',
    'vibe/internal/freelistref.d',
    'vibe/internal/interfaceproxy.d',
    'vibe/internal/memory.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

core_link_with = [vibe_utils_lib,
                  vibe_data_lib]

# Basic I/O and concurrency primitives, as well as low level utility functions
vibe_core_lib = library('vibe-core',
        [vibe_core_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_data_src_dir,
                              openssl_inc,
                              libevent_inc],
        install: true,
        dependencies: [crypto_dep,
                       ssl_dep,
                       libevent_dep,
                       zlib_dep],
        link_with: [core_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-core',
              libraries: [vibe_core_lib] + core_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Basic I/O and concurrency primitives, as well as low level utility functions of Vibe.'
)

#
# Tests
#
vibe_test_core_exe = executable('vibe-test_core',
    [vibe_core_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_data_src_dir,
                          openssl_inc,
                          libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [core_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_core', vibe_test_core_exe)
