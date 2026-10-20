cmake_minimum_required(VERSION 3.10)
project(spotube LANGUAGES CXX)

# The app's memory-backing policy: see cpp/memory_backing.cpp.
#
# Only the Linux/Android native helper lives here. The Flutter engine and
# the plugins are built by the Flutter Gradle plugin, not by this file.
add_library(spotube SHARED
        "memory_backing.cpp"
)

target_compile_features(spotube PUBLIC cxx_std_14)
target_compile_options(spotube PRIVATE -Wall -Werror)
target_compile_options(spotube PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
target_compile_definitions(spotube PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
target_compile_options(spotube PRIVATE -Wno-error=deprecated-declarations)

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(spotube ${log-lib} ${android-lib})
