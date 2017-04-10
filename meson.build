project('Vibe.d', 'd')

source_root = meson.source_root()
build_root = meson.build_root()

project_version      = '0.7.31'
project_version_name = '0.7.31'
project_soversion    = '0'

pkgc = import('pkgconfig')

#
# Sources
#
src_dir = include_directories('source/')

vibe_main_src = [
    'source/vibe/d.d',
    'source/vibe/vibe.d'
]
install_headers(vibe_main_src, subdir: 'd/vibe')

vibe_core_src = [
    'core/source/vibe/appmain.d',
    'core/source/vibe/core/task.d',
    'core/source/vibe/core/sync.d',
    'core/source/vibe/core/concurrency.d',
    'core/source/vibe/core/file.d',
    'core/source/vibe/core/log.d',
    'core/source/vibe/core/connectionpool.d',
    'core/source/vibe/core/args.d',
    'core/source/vibe/core/stream.d',
    'core/source/vibe/core/drivers/libasync.d',
    'core/source/vibe/core/drivers/utils.d',
    'core/source/vibe/core/drivers/native.d',
    'core/source/vibe/core/drivers/threadedfile.d',
    'core/source/vibe/core/drivers/libevent2.d',
    'core/source/vibe/core/drivers/winrt.d',
    'core/source/vibe/core/drivers/timerqueue.d',
    'core/source/vibe/core/drivers/win32.d',
    'core/source/vibe/core/drivers/libevent2_tcp.d',
    'core/source/vibe/core/net.d',
    'core/source/vibe/core/core.d',
    'core/source/vibe/core/driver.d',
    'core/source/vibe/internal/allocator.d',
    'core/source/vibe/internal/freelistref.d'
]

vibe_crypto_src = [
    'crypto/source/vibe/crypto/passwordhash.d',
    'crypto/source/vibe/crypto/cryptorand.d'
]

vibe_inet_src = [
    'inet/source/vibe/inet/path.d',
    'inet/source/vibe/inet/url.d',
    'inet/source/vibe/inet/mimetypes.d',
    'inet/source/vibe/inet/webform.d',
    'inet/source/vibe/inet/urltransfer.d',
    'inet/source/vibe/inet/message.d'
]

vibe_stream_src = [
    'stream/source/vibe/stream/botan.d',
    'stream/source/vibe/stream/counting.d',
    'stream/source/vibe/stream/taskpipe.d',
    'stream/source/vibe/stream/base64.d',
    'stream/source/vibe/stream/zlib.d',
    'stream/source/vibe/stream/stdio.d',
    'stream/source/vibe/stream/multicast.d',
    'stream/source/vibe/stream/openssl.d',
    'stream/source/vibe/stream/tls.d',
    'stream/source/vibe/stream/operations.d',
    'stream/source/vibe/stream/memory.d',
    'stream/source/vibe/stream/wrapper.d'
]

vibe_textfilter_src = [
    'textfilter/source/vibe/textfilter/markdown.d',
    'textfilter/source/vibe/textfilter/urlencode.d',
    'textfilter/source/vibe/textfilter/html.d'
]

vibe_utils_src = [
    'utils/source/vibe/utils/validation.d',
    'utils/source/vibe/utils/hashmap.d',
    'utils/source/vibe/utils/array.d',
    'utils/source/vibe/utils/dictionarylist.d',
    'utils/source/vibe/utils/memory.d',
    'utils/source/vibe/utils/string.d'
]

vibe_internal_src = [
    'utils/source/vibe/internal/win32.d',
    'utils/source/vibe/internal/meta/funcattr.d',
    'utils/source/vibe/internal/meta/traits.d',
    'utils/source/vibe/internal/meta/typetuple.d',
    'utils/source/vibe/internal/meta/codegen.d',
    'utils/source/vibe/internal/meta/all.d',
    'utils/source/vibe/internal/meta/uda.d',
    'utils/source/vibe/internal/rangeutil.d'
]

vibe_data_src = [
    'data/source/vibe/data/bson.d',
    'data/source/vibe/data/serialization.d',
    'data/source/vibe/data/json.d'
]

vibe_http_src = [
    'http/source/vibe/http/session.d',
    'http/source/vibe/http/proxy.d',
    'http/source/vibe/http/dist.d',
    'http/source/vibe/http/router.d',
    'http/source/vibe/http/common.d',
    'http/source/vibe/http/server.d',
    'http/source/vibe/http/log.d',
    'http/source/vibe/http/auth/basic_auth.d',
    'http/source/vibe/http/auth/digest_auth.d',
    'http/source/vibe/http/websockets.d',
    'http/source/vibe/http/client.d',
    'http/source/vibe/http/form.d',
    'http/source/vibe/http/fileserver.d',
    'http/source/vibe/http/status.d'
]

vibe_mail_src = [
    'mail/source/vibe/mail/smtp.d',
]

vibe_diet_src = [
    'templ/source/vibe/templ/parsertools.d',
    'templ/source/vibe/templ/utils.d',
    'templ/source/vibe/templ/diet.d'
]

vibe_db_mongo_src = [
    'mongo/source/vibe/db/mongo/connection.d',
    'mongo/source/vibe/db/mongo/database.d',
    'mongo/source/vibe/db/mongo/cursor.d',
    'mongo/source/vibe/db/mongo/collection.d',
    'mongo/source/vibe/db/mongo/client.d',
    'mongo/source/vibe/db/mongo/mongo.d',
    'mongo/source/vibe/db/mongo/settings.d',
    'mongo/source/vibe/db/mongo/flags.d'
]

vibe_db_redis_src = [
    'redis/source/vibe/db/redis/idioms.d',
    'redis/source/vibe/db/redis/types.d',
    'redis/source/vibe/db/redis/sessionstore.d',
    'redis/source/vibe/db/redis/redis.d'
]

vibe_web_src = [
    'web/source/vibe/web/validation.d',
    'web/source/vibe/web/common.d',
    'web/source/vibe/web/web.d',
    'web/source/vibe/web/internal/rest/common.d',
    'web/source/vibe/web/internal/rest/jsclient.d',
    'web/source/vibe/web/auth.d',
    'web/source/vibe/web/rest.d',
    'web/source/vibe/web/i18n.d'
]

#
# Includes
#
# It's easier to just install the whole source-tree then use
# install_headers and forget to include all subdirectories
# along the way.
install_subdir('source/vibe/', install_dir: 'include/d/')

#
# Dependencies
#
zlib_dep = dependency('zlib')
crypto_dep = dependency('libcrypto')
ssl_dep = dependency('libssl')
libevent_dep = dependency('libevent')

# directory where the external dependencies are included from.
# Meson will search for this dir in both build_root and source_root
external_subprojects_dir = 'subprojects'

# Try to find system OpenSSL bindings, if not found, download
# a Git copy.
openssl_src_dir = ''
if run_command('[', '-d', '/usr/include/d/common/deimos/openssl/', ']').returncode() == 0
    openssl_src_dir = '/usr/include/d/common'
else
    openssl_src_dir = external_subprojects_dir + '/openssl'
    if run_command('[', '-d', openssl_src_dir, ']').returncode() != 0
        message('Fetching OpenSSL D bindings from Github...')
        git_get_requests = run_command(['git', 'clone', 'https://github.com/s-ludwig/openssl.git', openssl_src_dir])
        if git_get_requests.returncode() != 0
            error('Unable to fetch OpenSSL bindings.\n' + git_get_requests.stderr())
        endif
    endif

    message('Using non-system OpenSSL D bindings.')
endif
openssl_inc = include_directories(openssl_src_dir)

# Try to find system LibEvent bindings, if not found, download
# a Git copy.
libevent_src_dir = ''
if run_command('[', '-d', '/usr/include/d/common/deimos/event2/', ']').returncode() == 0
    libevent_src_dir = '/usr/include/d/common'
else
    libevent_src_dir = external_subprojects_dir + '/libevent'
    if run_command('[', '-d', libevent_src_dir, ']').returncode() != 0
        message('Fetching LibEvent bindings from Github...')
        git_get_requests = run_command(['git', 'clone', 'https://github.com/s-ludwig/libevent.git', libevent_src_dir])
        if git_get_requests.returncode() != 0
            error('Unable to fetch LibEvent bindings.\n' + git_get_requests.stderr())
        endif
    endif

    message('Using non-system LibEvent D bindings.')
endif
libevent_inc = include_directories(libevent_src_dir)

if meson.get_compiler('d').get_id() == 'llvm'
    add_global_arguments(['-d-version=VibeLibeventDriver',
                          '-d-version=Have_openssl'], language : 'd')
endif
if meson.get_compiler('d').get_id() == 'dmd'
    add_global_arguments(['-version=VibeLibeventDriver',
                          '-version=Have_openssl'], language : 'd')
endif
if meson.get_compiler('d').get_id() == 'gnu'
    error('Vibe.d can not be compiled with GDC at time (2016). Sorry.')
endif

#
# Build Targets
#

# Basic I/O and concurrency primitives, as well as low level utility functions
vibe_core_lib = library('vibe-core',
        [vibe_core_src,
         vibe_crypto_src,
         vibe_inet_src,
         vibe_stream_src,
         vibe_textfilter_src],
        include_directories: [src_dir, openssl_inc, libevent_inc],
        install: true,
        dependencies: [crypto_dep,
                       ssl_dep,
                       libevent_dep,
                       zlib_dep],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-core',
              libraries: vibe_core_lib,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Basic I/O and concurrency primitives, as well as low level utility functions of Vibe.'
)

# Low level utility functionality
vibe_utils_lib = library('vibe-utils',
        [vibe_utils_src,
         vibe_internal_src],
        include_directories: [src_dir],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-utils',
              libraries: vibe_utils_lib,
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Low level utility functionality of Vibe.'
)

# Data format and serialization support
vibe_data_lib = library('vibe-data',
        [vibe_data_src],
        include_directories: [src_dir],
        install: true,
        link_with: [vibe_utils_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-data',
              libraries: [vibe_data_lib, vibe_utils_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Data format and serialization support for Vibe.'
)

# HTTP server and client implementation and higher level HTTP functionality
vibe_http_lib = library('vibe-http',
        [vibe_http_src],
        include_directories: [src_dir,openssl_inc, libevent_inc],
        install: true,
        dependencies: [zlib_dep],
        link_with: [vibe_core_lib, vibe_data_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-http',
              libraries: [vibe_http_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe HTTP server and client implementation and higher level HTTP functionality'
)

# SMTP client support
vibe_mail_lib = library('vibe-mail',
        [vibe_mail_src],
        include_directories: [src_dir],
        install: true,
        link_with: [vibe_core_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-mail',
              libraries: [vibe_mail_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe SMTP client support.'
)

# Diet HTML template system
vibe_diet_lib = library('vibe-diet',
        [vibe_diet_src],
        include_directories: [src_dir],
        install: true,
        link_with: [vibe_http_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-diet',
              libraries: [vibe_diet_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe Diet HTML template system.'
)

# MongoDB database client implementation
vibe_mongodb_lib = library('vibe-mongodb',
        [vibe_db_mongo_src],
        include_directories: [src_dir],
        install: true,
        link_with: [vibe_http_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-mongodb',
              libraries: [vibe_mongodb_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe MongoDB database client implementation.'
)

# Redis database client implementation
vibe_redis_lib = library('vibe-redis',
        [vibe_db_redis_src],
        include_directories: [src_dir],
        install: true,
        link_with: [vibe_http_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-redis',
              libraries: [vibe_redis_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe Redis database client implementation.'
)

# High level web and REST service framework
vibe_web_lib = library('vibe-web',
        [vibe_web_src],
        include_directories: [src_dir],
        install: true,
        link_with: [vibe_http_lib, vibe_diet_lib],
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-web',
              libraries: [vibe_web_lib],
              subdirs: 'd/vibe',
              version: project_version,
              description: 'Vibe high level web and REST service framework.'
)

#
# Tests
#
vibe_test_exe = executable('vibe_test',
    [vibe_main_src,
     vibe_core_src,
     vibe_crypto_src,
     vibe_inet_src,
     vibe_stream_src,
     vibe_textfilter_src,
     vibe_utils_src,
     vibe_internal_src,
     vibe_data_src,
     vibe_http_src,
     vibe_mail_src,
     vibe_diet_src,
     vibe_db_mongo_src,
     vibe_db_redis_src,
     vibe_web_src],
    include_directories: [src_dir, openssl_inc, libevent_inc],
    dependencies: [zlib_dep,
                   crypto_dep,
                   ssl_dep,
                   libevent_dep],
    d_args: meson.get_compiler('d').unittest_args(),
    link_args: '-main'
)
test('vibe_testsuite', vibe_test_exe)
