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

# SMTP client support
vibe_mail_lib = library('vibe-mail',
        [vibe_mail_src],
        dependencies: [vibe_inet_dep,
                       vibe_tls_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-mail',
              libraries: [vibe_mail_lib],
              subdirs: 'd/vibe',
              version: project_version,
              requires: ['vibe-inet', 'vibe-tls'],
              description: 'SMTP client support for Vibe.'
)

vibe_mail_dep = declare_dependency(
    link_with: [vibe_mail_lib],
    include_directories: [vibe_mail_src_dir],
    dependencies: [vibe_inet_dep,
                   vibe_tls_dep],
)

#
# Tests
#
vibe_test_mail_exe = executable('vibe-test_mail',
    [vibe_mail_src],
    dependencies: [vibe_inet_dep,
                   vibe_tls_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_mail', vibe_test_mail_exe)
