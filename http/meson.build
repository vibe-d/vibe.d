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

# HTTP server and client implementation and higher level HTTP functionality
vibe_http_lib = library('vibe-http',
        [vibe_http_src],
        dependencies: [
                       vibe_inet_dep,
                       vibe_tls_dep,
                       vibe_crypto_dep,
                       diet_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-http',
              libraries: [vibe_http_lib],
              subdirs: 'd/vibe',
              version: project_version,
              requires: ['diet',
                         'vibe-inet',
                         'vibe-tls',
                         'vibe-crypto'],
              description: 'Vibe HTTP server and client implementation and higher level HTTP functionality'
)

vibe_http_dep = declare_dependency(
    link_with: [vibe_http_lib],
    include_directories: [vibe_http_src_dir],
    dependencies: [vibe_inet_dep,
                   vibe_tls_dep,
                   vibe_crypto_dep,
                   diet_dep],
)

#
# Tests
#
vibe_test_http_exe = executable('vibe-test_http',
    [vibe_http_src],
    dependencies: [vibe_inet_dep,
                   vibe_tls_dep,
                   vibe_crypto_dep,
                   diet_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_http', vibe_test_http_exe)
