# A third-party integrator's view of Migo: find_package, link one target.
#
# Nothing here reaches into the Migo source tree. The prefix passed as
# CMAKE_PREFIX_PATH is an installed SDK -- either unpacked from a release by
# scripts/resolve-migo-artifact.sh, or staged locally by build-linux-sdk.sh.
cmake_minimum_required(VERSION 3.16)
project(migo-linux-example C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

find_package(migo REQUIRED)
find_package(X11 REQUIRED)

add_executable(migo-linux-example main.c)
target_link_libraries(migo-linux-example PRIVATE migo::migo ${X11_LIBRARIES})
target_include_directories(migo-linux-example PRIVATE ${X11_INCLUDE_DIR})
