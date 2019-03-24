project('Vibe.d', 'd',
    meson_version: '>=0.40',
    subproject_dir: 'lib/subprojects',
    license: 'MIT',
    version: '0.8.5'
)

project_soversion      = '0'
project_version_suffix = ''
project_version        = meson.project_version()
project_version_full   = project_version + project_version_suffix

source_root = meson.source_root()
build_root = meson.build_root()

pkgc = import('pkgconfig')

#
# Dependencies
#
zlib_dep = dependency('zlib')
crypto_dep = dependency('libcrypto')
ssl_dep = dependency('libssl')
libevent_dep = dependency('libevent')

#
# Compiler flags
#
flag_new_openssl_ldc = []
flag_new_openssl_dmd = []
if ssl_dep.version().version_compare('>=1.1')
    flag_new_openssl_ldc = '-d-version=VibeUseOpenSSL11'
    flag_new_openssl_dmd = '-version=VibeUseOpenSSL11'
endif

if meson.get_compiler('d').get_id() == 'llvm'
    add_global_arguments(['-d-version=VibeLibeventDriver',
                          '-d-version=Have_openssl',
                          '-d-version=Have_diet_ng',
                          '-d-version=Have_stdx_allocator',
                          flag_new_openssl_ldc], language : 'd')
endif
if meson.get_compiler('d').get_id() == 'dmd'
    add_global_arguments(['-version=VibeLibeventDriver',
                          '-version=Have_openssl',
                          '-version=Have_diet_ng',
                          '-version=Have_stdx_allocator',
                          flag_new_openssl_dmd], language : 'd')
endif
if meson.get_compiler('d').get_id() == 'gnu'
    error('Vibe.d can not be compiled with GDC at time (2016). Sorry.')
endif

#
# D dependencies
#

# we need to search for this dependency after setting global compiler flags, because
# it may pull in a subproject after which setting global flags is not allowed anymore
diet_dep = dependency('diet', fallback: ['diet', 'diet_dep'])
allocator_dep = dependency('stdx-allocator', fallback: ['stdx-allocator', 'allocator_dep'])

# directory where the external dependencies are included from.
# Meson will search for this dir in both build_root and source_root
subproject_dir = 'lib/subprojects'

# Try to find system OpenSSL bindings, if not found, download
# a Git copy.
openssl_src_dir = ''
if run_command('[', '-d', '/usr/include/d/common/deimos/openssl/', ']').returncode() == 0
    openssl_src_dir = '/usr/include/d/common'
else
    openssl_src_dir = subproject_dir + '/openssl'
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
    libevent_src_dir = subproject_dir + '/libevent'
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

#
# Modules
#

# Utils
subdir('utils/')

# Data
subdir('data/')

# Core
subdir('core/')

# Crypto
subdir('crypto/')

# Stream
subdir('stream/')

# TextFilter
subdir('textfilter/')

# INet
subdir('inet/')

# TLS
subdir('tls/')

# HTTP
subdir('http/')

# Mail
subdir('mail/')

# MongoDB
subdir('mongodb/')

# Redis
subdir('redis/')

# Web
subdir('web/')
