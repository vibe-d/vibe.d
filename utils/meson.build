# Meson file for Vibe Utils

vibe_utils_src_dir = include_directories('.')

vibe_utils_src = [
    'vibe/internal/memory_legacy.d',
    'vibe/internal/meta/all.d',
    'vibe/internal/meta/codegen.d',
    'vibe/internal/meta/funcattr.d',
    'vibe/internal/meta/traits.d',
    'vibe/internal/meta/typetuple.d',
    'vibe/internal/meta/uda.d',
    'vibe/internal/rangeutil.d',
    'vibe/internal/utilallocator.d',
    'vibe/internal/win32.d',
    'vibe/utils/array.d',
    'vibe/utils/dictionarylist.d',
    'vibe/utils/hashmap.d',
    'vibe/utils/memory.d',
    'vibe/utils/string.d',
    'vibe/utils/validation.d',
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

# Low level utility functionality
vibe_utils_lib = library('vibe-utils',
        [vibe_utils_src],
        include_directories: [openssl_inc, libevent_inc],
        install: true,
        dependencies: [crypto_dep,
                       ssl_dep,
                       libevent_dep,
                       zlib_dep,
                       allocator_dep],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-utils',
              libraries: vibe_utils_lib,
              subdirs: 'd/vibe',
              version: project_version,
              requires: ['stdx-allocator'],
              description: 'Low level utility functionality of Vibe.'
)

vibe_utils_dep = declare_dependency(
    link_with: [vibe_utils_lib],
    include_directories: [vibe_utils_src_dir, openssl_inc, libevent_inc],
    dependencies: [crypto_dep,
                    ssl_dep,
                    libevent_dep,
                    zlib_dep,
                    allocator_dep],
)

#
# Tests
#
vibe_test_utils_exe = executable('vibe-test_utils',
    [vibe_utils_src],
    dependencies: [vibe_utils_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_utils', vibe_test_utils_exe)
