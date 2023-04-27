# Meson file for Vibe INet

vibe_inet_src_dir = include_directories('.')

vibe_inet_src = files(
    'vibe/inet/message.d',
    'vibe/inet/mimetypes.d',
    'vibe/inet/url.d',
    'vibe/inet/urltransfer.d',
    'vibe/inet/webform.d',
)

#
# Install Includes
#
install_subdir('vibe/', install_dir: 'include/d/vibe/')

#
# Build Targets
#

vibe_inet_deps = [
    vibe_data_dep,
    vibe_core_dep,
    vibe_stream_dep,
    vibe_textfilter_dep,
]

# Internet standard functionality
vibe_inet_lib = library('vibe-inet',
        [vibe_inet_src],
        dependencies: vibe_inet_deps,
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'vibe-inet',
              libraries: [vibe_inet_lib],
              subdirs: 'd/vibe',
              requires: ['vibe-stream', 'vibe-textfilter'],
              version: project_version,
              description: 'Internet standard functionality for Vibe.'
)

vibe_inet_dep = declare_dependency(
    link_with: [vibe_inet_lib],
    include_directories: [vibe_inet_src_dir],
    dependencies: vibe_inet_deps,
)

#
# Tests
#
vibe_test_inet_exe = executable('vibe-test_inet',
    [vibe_inet_src],
    dependencies: vibe_inet_deps,
    d_unittest: true,
    link_args: '-main'
)
test('vibe-test_inet', vibe_test_inet_exe)
