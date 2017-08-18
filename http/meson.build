# Meson file for Vibe HTTP

vibe_http_src_dir = include_directories('.')

vibe_http_src = [
    'vibe/http/auth/basic_auth.d',
    'vibe/http/auth/digest_auth.d',
    'vibe/http/client.d',
    'vibe/http/common.d',
    'vibe/http/dist.d',
    'vibe/http/fileserver.d',
    'vibe/http/form.d',
    'vibe/http/log.d',
    'vibe/http/proxy.d',
    'vibe/http/router.d',
    'vibe/http/server.d',
    'vibe/http/session.d',
    'vibe/http/status.d',
    'vibe/http/websockets.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

http_link_with = [vibe_core_lib,
                  vibe_utils_lib,
                  vibe_data_lib,
                  vibe_stream_lib,
                  vibe_textfilter_lib,
                  vibe_inet_lib,
                  vibe_tls_lib,
                  vibe_crypto_lib]

# HTTP server and client implementation and higher level HTTP functionality
vibe_http_lib = library('vibe-http',
        [vibe_http_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_stream_src_dir,
                              vibe_textfilter_src_dir,
                              vibe_inet_src_dir,
                              vibe_tls_src_dir,
                              vibe_crypto_src_dir,
                              openssl_inc],
        install: true,
        dependencies: [zlib_dep],
        link_with: [http_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-http',
              libraries: [vibe_http_lib] + http_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe HTTP server and client implementation and higher level HTTP functionality'
)

#
# Tests
#
vibe_test_http_exe = executable('vibe-test_http',
    [vibe_http_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_stream_src_dir,
                          vibe_textfilter_src_dir,
                          vibe_inet_src_dir,
                          vibe_tls_src_dir,
                          vibe_crypto_src_dir,
                          openssl_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [http_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_http', vibe_test_http_exe)
