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

textfilter_link_with = [vibe_utils_lib,
                        vibe_core_lib,
                        vibe_data_lib]

# Text filtering routines
vibe_textfilter_lib = library('vibe-textfilter',
        [vibe_textfilter_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir],
        install: true,
        link_with: [textfilter_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-textfilter',
              libraries: [vibe_textfilter_lib] + textfilter_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Text filtering routines for Vibe.'
)

#
# Tests
#
vibe_test_textfilter_exe = executable('vibe-test_textfilter',
    [vibe_textfilter_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          openssl_inc,
                          libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [textfilter_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_textfilter', vibe_test_textfilter_exe)
