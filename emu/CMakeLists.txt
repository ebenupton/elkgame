# The emulator harness: elkh (headless: scripted runs and the demo's checks) and, when
# SDL2 is found, elkview (a window).  Both are built on Clock Signal's core from the fork
# in emu/clk (a git submodule, branch elk-headless), or from the checkout CLK_ROOT names.
# See emu/README.md.
#
#   cmake -S emu -B build-emu -DCMAKE_BUILD_TYPE=Release && cmake --build build-emu -j
#   cmake -S emu -B build-emu -DCLK_ROOT=/path/to/clk ...	(another checkout of the fork)
cmake_minimum_required(VERSION 3.19 FATAL_ERROR)
project(elkemu LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE Release)
endif()

set(CLK_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/clk CACHE PATH "the CLK fork (default: the submodule)")
if(NOT EXISTS ${CLK_ROOT}/cmake/CLK_SOURCES.cmake)
	message(FATAL_ERROR "emu/clk is empty: git submodule update --init emu/clk")
endif()
include(${CLK_ROOT}/cmake/CLK_SOURCES.cmake)

# CLK's sources (its own list, cmake/CLK_SOURCES.cmake) less its front ends
# (OSBindings), its OpenGL output and every machine but the Electron, the Acorn floppy
# code and the shared machine code (Machines/Utility, Machines/*.cpp); and less Electron.cpp itself, which machine.hpp
# compiles into each executable with CLK_HEADLESS so that the harness can reach the
# machine's state, and MachineForTarget.cpp, which would pull in the other machines.
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
target_compile_options(clkcore PRIVATE -w)		# CLK's own warnings are not ours
find_package(ZLIB REQUIRED)
target_link_libraries(clkcore PUBLIC ZLIB::ZLIB)
# On macOS CLK's audio filters (SignalProcessing/FIRFilter.hpp) use Accelerate's BLAS.
if(APPLE)
	set(BLA_VENDOR Apple)
	find_package(BLAS REQUIRED)
	target_link_libraries(clkcore PUBLIC BLAS::BLAS)
endif()

add_executable(elkh elkh.cpp)
target_link_libraries(elkh PRIVATE clkcore)
target_compile_options(elkh PRIVATE -Wno-everything)	# Electron.cpp is compiled in (machine.hpp)

# elkview is optional: built only when SDL2's CMake package is found.
find_package(SDL2 CONFIG)
if(SDL2_FOUND)
	add_executable(elkview elkview.cpp)
	target_link_libraries(elkview PRIVATE clkcore SDL2::SDL2)
	target_compile_options(elkview PRIVATE -Wno-everything)
else()
	message(STATUS "SDL2 not found: elkview will not be built")
endif()
