# Meson file for Vibe INet

vibe_inet_src_dir = include_directories('.')

vibe_inet_src = [
    'vibe/inet/message.d',
    'vibe/inet/mimetypes.d',
    'vibe/inet/path.d',
    'vibe/inet/url.d',
    'vibe/inet/urltransfer.d',
    'vibe/inet/webform.d',
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

inet_link_with = [vibe_utils_lib,
                  vibe_core_lib,
                  vibe_data_lib,
                  vibe_stream_lib,
                  vibe_textfilter_lib]

# Internet standard functionality
vibe_inet_lib = library('vibe-inet',
        [vibe_inet_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_stream_src_dir,
                              vibe_textfilter_src_dir],
        install: true,
        link_with: [inet_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-textfilter',
              libraries: [vibe_inet_lib] + inet_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Internet standard functionality for Vibe.'
)

#
# Tests
#
vibe_test_inet_exe = executable('vibe-test_inet',
    [vibe_inet_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_stream_src_dir,
                          vibe_textfilter_src_dir,
                          openssl_inc,
                          libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [inet_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_inet', vibe_test_inet_exe)
