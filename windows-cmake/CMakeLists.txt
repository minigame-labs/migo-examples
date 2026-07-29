# A third-party integrator's view of Migo: find_package, link one target.
#
# Nothing here reaches into the Migo source tree. The prefix passed as
# CMAKE_PREFIX_PATH is an installed SDK -- either unpacked from a release by
# scripts/resolve-migo-artifact.sh, or staged locally by build-windows-sdk.sh.
cmake_minimum_required(VERSION 3.16)
project(migo-windows-example C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

find_package(migo REQUIRED)

add_executable(migo-windows-example main.c)
target_link_libraries(migo-windows-example PRIVATE migo::migo)

# migo.dll and the runtimes it loads by name must sit beside the executable: the
# loader resolves them from the executable's directory, and a build that links
# cleanly still fails at startup without them -- with no output at all, because
# the failure happens before main runs.
#
# The whole directory is copied, and its path comes from the imported target
# rather than from a hand-written list or a walk up from ${migo_DIR}. A list has
# to be edited every time the SDK's runtime set changes; this example was
# already broken once that way, when migo.dll gained a dependency on V8's DLL.
add_custom_command(TARGET migo-windows-example POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "$<TARGET_FILE_DIR:migo::migo>"
            "$<TARGET_FILE_DIR:migo-windows-example>"
    COMMENT "staging the Migo runtime DLLs beside the executable")
