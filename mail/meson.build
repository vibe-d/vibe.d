# Meson file for Vibe Mail

vibe_mail_src_dir = include_directories('.')

vibe_mail_src = [
    'vibe/mail/smtp.d',
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

mail_link_with = [vibe_utils_lib,
                  vibe_core_lib,
                  vibe_data_lib,
                  vibe_inet_lib,
                  vibe_stream_lib,
                  vibe_tls_lib]

# SMTP client support
vibe_mail_lib = library('vibe-mail',
        [vibe_mail_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_inet_src_dir,
                              vibe_stream_src_dir,
                              vibe_tls_src_dir],
        install: true,
        link_with: [mail_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-mail',
              libraries: [vibe_mail_lib] + mail_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'SMTP client support for Vibe.'
)

#
# Tests
#
vibe_test_mail_exe = executable('vibe-test_mail',
    [vibe_mail_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_inet_src_dir,
                          vibe_stream_src_dir,
                          vibe_tls_src_dir],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [mail_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_mail', vibe_test_mail_exe)
