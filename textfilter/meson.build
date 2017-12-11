# Meson file for Vibe Textfilter

vibe_textfilter_src_dir = include_directories('.')

vibe_textfilter_src = [
    'vibe/textfilter/html.d',
    'vibe/textfilter/markdown.d',
    'vibe/textfilter/urlencode.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

# Text filtering routines
vibe_textfilter_lib = library('vibe-textfilter',
        [vibe_textfilter_src],
        dependencies: [vibe_core_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-textfilter',
              libraries: [vibe_textfilter_lib],
              requires: ['vibe-core'],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Text filtering routines for Vibe.'
)

vibe_textfilter_dep = declare_dependency(
    link_with: [vibe_textfilter_lib],
    include_directories: [vibe_textfilter_src_dir],
    dependencies: [vibe_core_dep],
)

#
# Tests
#
vibe_test_textfilter_exe = executable('vibe-test_textfilter',
    [vibe_textfilter_src],
    dependencies: [vibe_core_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_textfilter', vibe_test_textfilter_exe)
