# Meson file for Vibe TLS

vibe_tls_src_dir = include_directories('.')

vibe_tls_src = [
    'vibe/stream/botan.d',
    'vibe/stream/openssl.d',
    'vibe/stream/tls.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

# TLS stream implementations
vibe_tls_lib = library('vibe-tls',
        [vibe_tls_src],
        dependencies: [vibe_stream_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-tls',
              libraries: [vibe_tls_lib],
              subdirs: 'd/vibe',
              requires: ['vibe-stream'],
              version: project_version,
              description: 'TLS stream implementations for Vibe.'
)

vibe_tls_dep = declare_dependency(
    link_with: [vibe_tls_lib],
    include_directories: [vibe_tls_src_dir],
    dependencies: [vibe_stream_dep]
)

#
# Tests
#
vibe_test_tls_exe = executable('vibe-test_tls',
    [vibe_tls_src],
    dependencies: [vibe_stream_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_tls', vibe_test_tls_exe)
