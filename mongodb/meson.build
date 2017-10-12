# Meson file for Vibe MongoDB

vibe_mongodb_src_dir = include_directories('.')

vibe_mongodb_src = [
    'vibe/db/mongo/client.d',
    'vibe/db/mongo/collection.d',
    'vibe/db/mongo/connection.d',
    'vibe/db/mongo/cursor.d',
    'vibe/db/mongo/database.d',
    'vibe/db/mongo/flags.d',
    'vibe/db/mongo/mongo.d',
    'vibe/db/mongo/sasl.d',
    'vibe/db/mongo/settings.d',
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

mongodb_link_with = [vibe_utils_lib,
                     vibe_core_lib,
                     vibe_data_lib,
                     vibe_inet_lib,
                     vibe_stream_lib,
                     vibe_textfilter_lib,
                     vibe_tls_lib,
                     vibe_crypto_lib]

# MongoDB database client implementation
vibe_mongodb_lib = library('vibe-mongodb',
        [vibe_mongodb_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_inet_src_dir,
                              vibe_stream_src_dir,
                              vibe_textfilter_src_dir,
                              vibe_tls_src_dir,
                              vibe_crypto_src_dir],
        install: true,
        link_with: [mongodb_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-mongodb',
              libraries: [vibe_mongodb_lib] + mongodb_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'MongoDB database client implementation for Vibe.'
)

#
# Tests
#
vibe_test_mongodb_exe = executable('vibe-test_mongodb',
    [vibe_mongodb_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_inet_src_dir,
                          vibe_stream_src_dir,
                          vibe_textfilter_src_dir,
                          vibe_tls_src_dir,
                          vibe_crypto_src_dir],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [mongodb_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_mongodb', vibe_test_mongodb_exe)
