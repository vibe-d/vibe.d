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

# MongoDB database client implementation
vibe_mongodb_lib = library('vibe-mongodb',
        [vibe_mongodb_src],
        dependencies: [vibe_inet_dep,
                       vibe_tls_dep,
                       vibe_crypto_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-mongodb',
              libraries: [vibe_mongodb_lib],
              subdirs: 'd/vibe',
              version: project_version,
              requires: ['vibe-inet', 'vibe-tls', 'vibe-crypto'],
              description: 'MongoDB database client implementation for Vibe.'
)

vibe_mongodb_dep = declare_dependency(
    link_with: [vibe_mongodb_lib],
    include_directories: [vibe_mongodb_src_dir],
    dependencies: [vibe_inet_dep,
                   vibe_tls_dep,
                   vibe_crypto_dep],
)

#
# Tests
#
vibe_test_mongodb_exe = executable('vibe-test_mongodb',
    [vibe_mongodb_src],
    dependencies: [vibe_inet_dep,
                   vibe_tls_dep,
                   vibe_crypto_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_mongodb', vibe_test_mongodb_exe)
