# The emulator harness: elkh (headless; scripted runs and the demo's checks) and, when
# SDL2 is found, elkview (a window).  Both build Clock Signal's core from the fork in
# emu/clk (git submodule, branch elk-headless).  See emu/README.md.
#
#   cmake -S emu -B build-emu -DCMAKE_BUILD_TYPE=Release && cmake --build build-emu -j
cmake_minimum_required(VERSION 3.19 FATAL_ERROR)
project(elkemu LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE Release)
endif()

set(CLK_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/clk)
if(NOT EXISTS ${CLK_ROOT}/cmake/CLK_SOURCES.cmake)
	message(FATAL_ERROR "emu/clk is empty: git submodule update --init emu/clk")
endif()
include(${CLK_ROOT}/cmake/CLK_SOURCES.cmake)

# CLK's core without its front ends, its OpenGL output, the other machines, and the
# Electron itself (machine.hpp compiles that into each executable, to reach its state).
set(CORE_SOURCES)
foreach(src ${CLK_SOURCES})
	if(src MATCHES "^OSBindings/" OR src MATCHES "^Outputs/OpenGL/")
		continue()
	endif()
	if(src MATCHES "^Machines/" AND NOT (src MATCHES "^Machines/Acorn/Electron/" OR src MATCHES "^Machines/Acorn/Floppy/"
			OR src MATCHES "^Machines/Utility/" OR src MATCHES "^Machines/[A-Za-z]*\\.cpp$"))
		continue()
	endif()
	if(src STREQUAL "Machines/Acorn/Electron/Electron.cpp" OR src STREQUAL "Machines/Utility/MachineForTarget.cpp")
		continue()
	endif()
	list(APPEND CORE_SOURCES ${CLK_ROOT}/${src})
endforeach()

add_library(clkcore STATIC ${CORE_SOURCES})
target_include_directories(clkcore PUBLIC ${CLK_ROOT})
target_compile_definitions(clkcore PUBLIC CLK_HEADLESS)
target_compile_options(clkcore PRIVATE -w)		# (CLK's own warnings are not ours)
find_package(ZLIB REQUIRED)
target_link_libraries(clkcore PUBLIC ZLIB::ZLIB)
if(APPLE)
	set(BLA_VENDOR Apple)
	find_package(BLAS REQUIRED)
	target_link_libraries(clkcore PUBLIC BLAS::BLAS)
endif()

add_executable(elkh elkh.cpp)
target_link_libraries(elkh PRIVATE clkcore)
target_compile_options(elkh PRIVATE -Wno-everything)	# (Electron.cpp is compiled in)

find_package(SDL2 CONFIG)
if(SDL2_FOUND)
	add_executable(elkview elkview.cpp)
	target_link_libraries(elkview PRIVATE clkcore SDL2::SDL2)
	target_compile_options(elkview PRIVATE -Wno-everything)
else()
	message(STATUS "SDL2 not found: elkview will not be built")
endif()
