# Meson file for Vibe Redis

vibe_redis_src_dir = include_directories('.')

vibe_redis_src = [
    'vibe/db/redis/idioms.d',
    'vibe/db/redis/redis.d',
    'vibe/db/redis/sessionstore.d',
    'vibe/db/redis/types.d'
]

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

# Redis database client implementation
vibe_redis_lib = library('vibe-redis',
        [vibe_redis_src],
        dependencies: [vibe_http_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-redis',
              libraries: [vibe_redis_lib],
              subdirs: 'd/vibe',
              version: project_version,
              requires: ['vibe-http'],
              description: 'Redis database client implementation for Vibe.'
)

vibe_redis_dep = declare_dependency(
    link_with: [vibe_redis_lib],
    include_directories: [vibe_redis_src_dir],
    dependencies: [vibe_http_dep],
)

#
# Tests
#
vibe_test_redis_exe = executable('vibe-test_redis',
    [vibe_redis_src],
    dependencies: [vibe_http_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_redis', vibe_test_redis_exe)
