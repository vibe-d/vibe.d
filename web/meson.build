# Meson file for Vibe Web

vibe_web_src_dir = include_directories('.')

vibe_web_src = [
    'vibe/web/auth.d',
    'vibe/web/common.d',
    'vibe/web/i18n.d',
    'vibe/web/internal/rest/common.d',
    'vibe/web/internal/rest/jsclient.d',
    'vibe/web/rest.d',
    'vibe/web/validation.d',
    'vibe/web/web.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

web_link_with = [vibe_utils_lib,
                 vibe_core_lib,
                 vibe_data_lib,
                 vibe_inet_lib,
                 vibe_stream_lib,
                 vibe_textfilter_lib,
                 vibe_tls_lib,
                 vibe_crypto_lib,
                 vibe_http_lib]

# High level web and REST service framework
vibe_web_lib = library('vibe-web',
        [vibe_web_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_inet_src_dir,
                              vibe_stream_src_dir,
                              vibe_textfilter_src_dir,
                              vibe_tls_src_dir,
                              vibe_crypto_src_dir,
                              vibe_http_src_dir,
                              openssl_inc],
        install: true,
        link_with: [web_link_with],
        dependencies: [crypto_dep,
                       ssl_dep],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-web',
              libraries: [vibe_web_lib] + web_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'High level web and REST service framework'
)

#
# Tests
#
vibe_test_web_exe = executable('vibe-test_web',
    [vibe_web_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_inet_src_dir,
                          vibe_stream_src_dir,
                          vibe_textfilter_src_dir,
                          vibe_tls_src_dir,
                          vibe_crypto_src_dir,
                          vibe_http_src_dir,
                          openssl_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [web_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_web', vibe_test_web_exe)
