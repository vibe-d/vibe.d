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

# Cryptographic helper routines
vibe_stream_lib = library('vibe-stream',
        [vibe_stream_src],
        dependencies: [vibe_core_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-stream',
              libraries: [vibe_stream_lib],
              subdirs: 'd/vibe',
              version: project_version,
              requires: ['vibe-core', 'vibe-data'],
              description: 'Library of various pluggable stream implementations for Vibe.'
)

vibe_stream_dep = declare_dependency(
    link_with: [vibe_stream_lib],
    include_directories: [vibe_stream_src_dir],
    dependencies: [vibe_core_dep]
)
#
# Tests
#
vibe_test_stream_exe = executable('vibe-test_stream',
    [vibe_stream_src],
    dependencies: [vibe_core_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_stream', vibe_test_stream_exe)
