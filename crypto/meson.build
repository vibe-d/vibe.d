# Meson file for Vibe Crypto

vibe_crypto_src_dir = include_directories('.')

vibe_crypto_src = [
    'vibe/crypto/cryptorand.d',
    'vibe/crypto/passwordhash.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

crypto_link_with = [vibe_utils_lib,
                    vibe_core_lib]

# Cryptographic helper routines
vibe_crypto_lib = library('vibe-crypto',
        [vibe_crypto_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir],
        install: true,
        link_with: [crypto_link_with],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-crypto',
              libraries: [vibe_crypto_lib] + crypto_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Cryptographic helper routines for Vibe.'
)

#
# Tests
#
vibe_test_crypto_exe = executable('vibe-test_crypto',
    [vibe_crypto_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          openssl_inc,
                          libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [crypto_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_crypto', vibe_test_crypto_exe)
