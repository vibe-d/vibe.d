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

# Cryptographic helper routines
vibe_crypto_lib = library('vibe-crypto',
        [vibe_crypto_src],
        dependencies: [vibe_core_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-crypto',
              libraries: [vibe_crypto_lib],
              subdirs: 'd/vibe',
              version: project_version,
    		  requires: ['vibe-core'],
              description: 'Cryptographic helper routines for Vibe.'
)

vibe_crypto_dep = declare_dependency(
    link_with: [vibe_crypto_lib],
    include_directories: [vibe_crypto_src_dir],
    dependencies: [vibe_core_dep, vibe_utils_dep]
)

#
# Tests
#
vibe_test_crypto_exe = executable('vibe-test_crypto',
    [vibe_crypto_src],
    dependencies: [vibe_core_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_crypto', vibe_test_crypto_exe)
