# Meson file for Vibe Stream

vibe_stream_src_dir = include_directories('.')

vibe_stream_src = [
    'vibe/stream/base64.d',
    'vibe/stream/counting.d',
    'vibe/stream/memory.d',
    'vibe/stream/multicast.d',
    'vibe/stream/operations.d',
    'vibe/stream/stdio.d',
    'vibe/stream/taskpipe.d',
    'vibe/stream/wrapper.d',
    'vibe/stream/zlib.d',
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

stream_link_with = [vibe_utils_lib,
                    vibe_core_lib,
                    vibe_data_lib]

# Cryptographic helper routines
vibe_stream_lib = library('vibe-stream',
        [vibe_stream_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir],
        install: true,
        link_with: [stream_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-stream',
              libraries: [vibe_stream_lib] + stream_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Library of various pluggable stream implementations for Vibe.'
)

#
# Tests
#
vibe_test_stream_exe = executable('vibe-test_stream',
    [vibe_stream_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [stream_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_stream', vibe_test_stream_exe)
