cmake_minimum_required(VERSION 3.20)
project(SownSyncCore VERSION 0.2.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(sowncore
    core/src/Time.cpp
    core/src/CueEngine.cpp
    core/src/SyncEngine.cpp
    core/src/InternalSyncSource.cpp
    core/src/ReaperSyncSource.cpp
)

target_include_directories(sowncore PUBLIC core/include)

if(WIN32)
    target_link_libraries(sowncore PRIVATE ws2_32)
endif()

add_executable(SownCoreConsole apps/console/main.cpp)
target_link_libraries(SownCoreConsole PRIVATE sowncore)

if(WIN32)
    add_library(reaper_sown_bridge SHARED reaper_extension/reaper_sown_bridge.cpp)
    target_compile_definitions(reaper_sown_bridge PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(reaper_sown_bridge PRIVATE ws2_32)
    set_target_properties(reaper_sown_bridge PROPERTIES PREFIX "")
endif()

enable_testing()
add_executable(SownCoreTests tests/core_tests.cpp)
target_link_libraries(SownCoreTests PRIVATE sowncore)
add_test(NAME SownCoreTests COMMAND SownCoreTests)
