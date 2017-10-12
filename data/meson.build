# Meson file for Vibe Data

vibe_data_src_dir = include_directories('.')

vibe_data_src = [
    'vibe/data/bson.d',
    'vibe/data/json.d',
    'vibe/data/serialization.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

data_link_with = [vibe_utils_lib]

# Data format and serialization support
vibe_data_lib = library('vibe-data',
        [vibe_data_src],
        include_directories: [vibe_utils_src_dir],
        install: true,
        link_with: [data_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-data',
              libraries: [vibe_data_lib] + data_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Data format and serialization support for Vibe.'
)

#
# Tests
#
vibe_test_data_exe = executable('vibe-test_data',
    [vibe_data_src],
    include_directories: [vibe_utils_src_dir,
                          openssl_inc,
                          libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [data_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_data', vibe_test_data_exe)
