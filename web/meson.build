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

# High level web and REST service framework
vibe_web_lib = library('vibe-web',
        [vibe_web_src],
        dependencies: [vibe_http_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-web',
              libraries: [vibe_web_lib],
              subdirs: 'd/vibe',
              requires: ['vibe-http'],
              version: project_version,
              description: 'High level web and REST service framework'
)

vibe_web_dep = declare_dependency(
    link_with: [vibe_web_lib],
    include_directories: [vibe_web_src_dir],
    dependencies: [vibe_http_dep]
)

#
# Tests
#
vibe_test_web_exe = executable('vibe-test_web',
    [vibe_web_src],
    dependencies: [vibe_http_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_web', vibe_test_web_exe)
