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

redis_link_with = [vibe_utils_lib,
                     vibe_core_lib,
                     vibe_data_lib,
                     vibe_inet_lib,
                     vibe_stream_lib,
                     vibe_textfilter_lib,
                     vibe_tls_lib,
                     vibe_crypto_lib,
                     vibe_http_lib]

# Redis database client implementation
vibe_redis_lib = library('vibe-redis',
        [vibe_redis_src],
        include_directories: [vibe_utils_src_dir,
                              vibe_core_src_dir,
                              vibe_data_src_dir,
                              vibe_inet_src_dir,
                              vibe_stream_src_dir,
                              vibe_textfilter_src_dir,
                              vibe_tls_src_dir,
                              vibe_crypto_src_dir,
                              vibe_http_src_dir],
        install: true,
        link_with: [redis_link_with],
        dependencies: [crypto_dep,
                       ssl_dep],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-redis',
              libraries: [vibe_redis_lib] + redis_link_with,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Redis database client implementation for Vibe.'
)

#
# Tests
#
vibe_test_redis_exe = executable('vibe-test_redis',
    [vibe_redis_src],
    include_directories: [vibe_utils_src_dir,
                          vibe_core_src_dir,
                          vibe_data_src_dir,
                          vibe_inet_src_dir,
                          vibe_stream_src_dir,
                          vibe_textfilter_src_dir,
                          vibe_tls_src_dir,
                          vibe_crypto_src_dir,
                          vibe_http_src_dir],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    link_with: [redis_link_with],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe-test_redis', vibe_test_redis_exe)
