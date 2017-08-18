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

tls_link_with = [vibe_utils_lib,
                 vibe_core_lib,
                 vibe_data_lib,
                 vibe_stream_lib]

# TLS stream implementations
vibe_tls_lib = library('vibe-tls',
        [vibe_tls_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_stream_src_dir,
                              openssl_inc],
        install: true,
        link_with: [tls_link_with],
        dependencies: [crypto_dep,
                       ssl_dep],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-tls',
              libraries: [vibe_tls_lib] + tls_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'TLS stream implementations for Vibe.'
)

#
# Tests
#
vibe_test_tls_exe = executable('vibe-test_tls',
    [vibe_tls_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_stream_src_dir,
                          openssl_inc,
                          libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [tls_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_tls', vibe_test_tls_exe)
