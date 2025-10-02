# This file is part of Sanmill.
# Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
#
# Sanmill is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Sanmill is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

### ==========================================================================
### Section 1. General Configuration
### ==========================================================================

### Executable name
ifeq ($(COMP),mingw)
EXE = sanmill.exe
else
EXE = sanmill
endif

### Installation dir definitions
PREFIX = /usr/local
BINDIR = $(PREFIX)/bin

### Built-in benchmark for pgo-builds
PGOBENCH = ./$(EXE) bench

### Source and object files
PERFECT_SRCS = $(wildcard perfect/*.cpp)
SRCS = $(PERFECT_SRCS) $(wildcard *.cpp)

OBJS = $(SRCS:.cpp=.o)

# Define library objects excluding main.o
LIB_OBJS = $(filter-out main.o, $(OBJS))

# Define test library objects with .test.o suffix
LIB_OBJS_TEST = $(patsubst %.o, %.test.o, $(LIB_OBJS))

# Define VPATH for source file locations
VPATH = syzygy:nnue:nnue/features

### Establish the operating system name
KERNEL = $(shell uname -s)
ifeq ($(KERNEL),Linux)
	OS = $(shell uname -o)
endif

ifeq ($(KERNEL),Darwin)
	OS = macOS
endif

### ==========================================================================
### Section 2. High-level Configuration
### ==========================================================================

#
# flag                --- Comp switch      --- Description
# ----------------------------------------------------------------------------
#
# debug = yes/no      --- -DNDEBUG         --- Enable/Disable debug mode
# sanitize = undefined/thread/no (-fsanitize )
#                     --- ( undefined )    --- enable undefined behavior checks
#                     --- ( thread    )    --- enable threading error  checks
# optimize = yes/no   --- (-O3/-fast etc.) --- Enable/Disable optimizations
# arch = (name)       --- (-arch)          --- Target architecture
# bits = 64/32        --- -DIS_64BIT       --- 64-/32-bit operating system
# prefetch = yes/no   --- -DUSE_PREFETCH   --- Use prefetch asm-instruction
# popcnt = yes/no     --- -DUSE_POPCNT     --- Use popcnt asm-instruction
# pext = yes/no       --- -DUSE_PEXT       --- Use pext x86_64 asm-instruction
# sse = yes/no        --- -msse            --- Use Intel Streaming SIMD Extensions
# mmx = yes/no        --- -mmmx            --- Use Intel MMX instructions
# sse2 = yes/no       --- -msse2           --- Use Intel Streaming SIMD Extensions 2
# ssse3 = yes/no      --- -mssse3          --- Use Intel Supplemental Streaming SIMD Extensions 3
# sse41 = yes/no      --- -msse4.1         --- Use Intel Streaming SIMD Extensions 4.1
# avx2 = yes/no       --- -mavx2           --- Use Intel Advanced Vector Extensions 2
# avx512 = yes/no     --- -mavx512bw       --- Use Intel Advanced Vector Extensions 512
# vnni256 = yes/no    --- -mavx512vnni     --- Use Intel Vector Neural Network Instructions 256
# vnni512 = yes/no    --- -mavx512vnni     --- Use Intel Vector Neural Network Instructions 512
# neon = yes/no       --- -DUSE_NEON       --- Use ARM SIMD architecture
#
# Note that Makefile is space sensitive, so when adding new architectures
# or modifying existing flags, you have to make sure there are no extra spaces
# at the end of the line for flag values.

### 2.1. General and architecture defaults

# Auto-detect ARCH on macOS based on machine architecture if not set by user
ifeq ($(OS), macOS)
	UNAME_M := $(shell uname -m)
	ifeq ($(UNAME_M),arm64)
		ARCH ?= apple-silicon
	endif
	ifeq ($(UNAME_M),x86_64)
		ARCH ?= x86-64-modern
	endif
endif

ifeq ($(ARCH),)
   ARCH = x86-64-modern
   help_skip_sanity = yes
endif

# explicitly check for the list of supported architectures (as listed with make help),
# the user can override with `make ARCH=x86-32-vnni256 SUPPORTED_ARCH=true`
ifeq ($(ARCH), $(filter $(ARCH), \
                 x86-64-vnni512 x86-64-vnni256 x86-64-avx512 x86-64-bmi2 x86-64-avx2 \
                 x86-64-sse41-popcnt x86-64-modern x86-64-ssse3 x86-64-sse3-popcnt \
                 x86-64 x86-32-sse41-popcnt x86-32-sse2 x86-32 ppc-64 ppc-32 \
                 armv7 armv7-neon armv8 apple-silicon general-64 general-32))
   SUPPORTED_ARCH=true
else
   SUPPORTED_ARCH=false
endif

optimize = no
debug = yes
sanitize = no
coverage = no
bits = 64
prefetch = no
popcnt = no
pext = no
sse = no
mmx = no
sse2 = no
ssse3 = no
sse41 = no
avx2 = no
avx512 = no
vnni256 = no
vnni512 = no
neon = no
STRIP = strip

### 2.2 Architecture specific

ifeq ($(findstring x86,$(ARCH)),x86)

# x86-32/64

ifeq ($(findstring x86-32,$(ARCH)),x86-32)
	arch = i386
	bits = 32
	sse = yes
	mmx = yes
else
	arch = x86_64
	sse = yes
	sse2 = yes
endif

ifeq ($(findstring -sse,$(ARCH)),-sse)
	sse = yes
endif

ifeq ($(findstring -popcnt,$(ARCH)),-popcnt)
	popcnt = yes
endif

ifeq ($(findstring -mmx,$(ARCH)),-mmx)
	mmx = yes
endif

ifeq ($(findstring -sse2,$(ARCH)),-sse2)
	sse = yes
	sse2 = yes
endif

ifeq ($(findstring -ssse3,$(ARCH)),-ssse3)
	sse = yes
	sse2 = yes
	ssse3 = yes
endif

ifeq ($(findstring -sse41,$(ARCH)),-sse41)
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
endif

ifeq ($(findstring -modern,$(ARCH)),-modern)
	popcnt = yes
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
endif

ifeq ($(findstring -avx2,$(ARCH)),-avx2)
	popcnt = yes
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
	avx2 = yes
endif

ifeq ($(findstring -bmi2,$(ARCH)),-bmi2)
	popcnt = yes
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
	avx2 = yes
	pext = yes
endif

ifeq ($(findstring -avx512,$(ARCH)),-avx512)
	popcnt = yes
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
	avx2 = yes
	pext = yes
	avx512 = yes
endif

ifeq ($(findstring -vnni256,$(ARCH)),-vnni256)
	popcnt = yes
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
	avx2 = yes
	pext = yes
	vnni256 = yes
endif

ifeq ($(findstring -vnni512,$(ARCH)),-vnni512)
	popcnt = yes
	sse = yes
	sse2 = yes
	ssse3 = yes
	sse41 = yes
	avx2 = yes
	pext = yes
	avx512 = yes
	vnni512 = yes
endif

ifeq ($(sse),yes)
	prefetch = yes
endif

# 64-bit pext is not available on x86-32
ifeq ($(bits),32)
	pext = no
endif

else

# all other architectures

ifeq ($(ARCH),general-32)
	arch = any
	bits = 32
endif

ifeq ($(ARCH),general-64)
	arch = any
endif

ifeq ($(ARCH),armv7)
	arch = armv7
	prefetch = yes
	bits = 32
endif

ifeq ($(ARCH),armv7-neon)
	arch = armv7
	prefetch = yes
	popcnt = yes
	neon = yes
	bits = 32
endif

ifeq ($(ARCH),armv8)
	arch = armv8
	prefetch = yes
	popcnt = yes
	neon = yes
endif

ifeq ($(ARCH),apple-silicon)
	arch = arm64
	prefetch = yes
	popcnt = yes
	neon = yes
endif

ifeq ($(ARCH),ppc-32)
	arch = ppc
	bits = 32
endif

ifeq ($(ARCH),ppc-64)
	arch = ppc64
	popcnt = yes
	prefetch = yes
endif

endif

### ==========================================================================
### Section 3. Low-level Configuration
### ==========================================================================

### 3.1 Selecting compiler (default = gcc)
CXXFLAGS += -Wall -Wcast-qual -fno-exceptions -std=c++17 $(EXTRACXXFLAGS)
DEPENDFLAGS += -std=c++17
LDFLAGS += $(EXTRALDFLAGS)

# For Sanmill
CXXFLAGS += -I../include -Iperfect -I.

ifeq ($(COMP),)
	COMP=gcc
endif

ifeq ($(COMP),gcc)
	comp=gcc
	CXX=g++
	CXXFLAGS += -pedantic -Wextra -Wshadow
	# CXXFLAGS += -Wno-class-memaccess

	ifeq ($(arch),$(filter $(arch),armv7 armv8))
		ifeq ($(OS),Android)
			CXXFLAGS += -m$(bits)
			LDFLAGS += -m$(bits)
		endif
	else
		CXXFLAGS += -m$(bits)
		LDFLAGS += -m$(bits)
	endif

	ifeq ($(arch),$(filter $(arch),armv7))
		LDFLAGS += -latomic
	endif

	ifneq ($(KERNEL),Darwin)
	   LDFLAGS += -Wl,--no-as-needed
	endif
endif

ifeq ($(COMP),mingw)
	comp=mingw

	ifeq ($(KERNEL),Linux)
		ifeq ($(bits),64)
			ifeq ($(shell which x86_64-w64-mingw32-c++-posix),)
				CXX=x86_64-w64-mingw32-c++
			else
				CXX=x86_64-w64-mingw32-c++-posix
			endif
		else
			ifeq ($(shell which i686-w64-mingw32-c++-posix),)
				CXX=i686-w64-mingw32-c++
			else
				CXX=i686-w64-mingw32-c++-posix
			endif
		endif
	else
		CXX=g++
	endif

	CXXFLAGS += -Wextra -Wshadow
	LDFLAGS += -static
endif

ifeq ($(COMP),icc)
	comp=icc
	CXX=icpc
	CXXFLAGS += -diag-disable 1476,10120 -Wcheck -Wabi -Wdeprecated -strict-ansi
endif

ifeq ($(COMP),clang)
	comp=clang
	CXX=clang++
	CXXFLAGS += -pedantic -Wextra -Wshadow -fexceptions

	ifneq ($(KERNEL),Darwin)
	ifneq ($(KERNEL),OpenBSD)
		LDFLAGS += -latomic
	endif
	endif

	ifeq ($(arch),$(filter $(arch),armv7 armv8))
		ifeq ($(OS),Android)
			CXXFLAGS += -m$(bits)
			LDFLAGS += -m$(bits)
		endif
	else
		CXXFLAGS += -m$(bits)
		LDFLAGS += -m$(bits)
	endif
endif

ifeq ($(KERNEL),Darwin)
	CXXFLAGS += -arch $(arch) -mmacosx-version-min=10.14
	LDFLAGS += -arch $(arch) -mmacosx-version-min=10.14
	XCRUN = xcrun
endif

# To cross-compile for Android, NDK version r21 or later is recommended.
# In earlier NDK versions, you'll need to pass -fno-addrsig if using GNU binutils.
# Currently we don't know how to make PGO builds with the NDK yet.
ifeq ($(COMP),ndk)
	CXXFLAGS += -stdlib=libc++ -fPIE
	comp=clang
	ifeq ($(arch),armv7)
		CXX=armv7a-linux-androideabi16-clang++
		CXXFLAGS += -mthumb -march=armv7-a -mfloat-abi=softfp -mfpu=neon
		STRIP=arm-linux-androideabi-strip
	endif
	ifeq ($(arch),armv8)
		CXX=aarch64-linux-android21-clang++
		STRIP=aarch64-linux-android-strip
	endif
	LDFLAGS += -static-libstdc++ -pie -lm -latomic
endif

ifeq ($(comp),icc)
	profile_make = icc-profile-make
	profile_use = icc-profile-use
else ifeq ($(comp),clang)
	profile_make = clang-profile-make
	profile_use = clang-profile-use
else
	profile_make = gcc-profile-make
	profile_use = gcc-profile-use
endif

### Travis CI script uses COMPILER to overwrite CXX
ifdef COMPILER
	COMPCXX=$(COMPILER)
endif

### Allow overwriting CXX from command line
ifdef COMPCXX
	CXX=$(COMPCXX)
endif

### Sometimes gcc is really clang
ifeq ($(COMP),gcc)
	gccversion = $(shell $(CXX) --version)
	gccisclang = $(findstring clang,$(gccversion))
	ifneq ($(gccisclang),)
		profile_make = clang-profile-make
		profile_use = clang-profile-use
	endif
endif

### On mingw use Windows threads, otherwise POSIX
ifneq ($(comp),mingw)
	CXXFLAGS += -DUSE_PTHREADS
	# On Android Bionic's C library comes with its own pthread implementation bundled in
	ifneq ($(OS),Android)
		# Haiku has pthreads in its libroot, so only link it in on other platforms
		ifneq ($(KERNEL),Haiku)
			ifneq ($(COMP),ndk)
				LDFLAGS += -lpthread
			endif
		endif
	endif
endif

### 3.2.1 Debugging
ifeq ($(debug),no)
	CXXFLAGS += -DNDEBUG
else
	CXXFLAGS += -g
endif

### 3.2.2 Debugging with undefined behavior sanitizers
ifneq ($(sanitize),no)
	CXXFLAGS += -g3 -fsanitize=$(sanitize)
	LDFLAGS += -fsanitize=$(sanitize)
endif

### 3.3 Optimization
ifeq ($(optimize),yes)

	CXXFLAGS += -O3

	ifeq ($(comp),gcc)
		ifeq ($(OS), Android)
			CXXFLAGS += -fno-gcse -mthumb -march=armv7-a -mfloat-abi=softfp
		endif
	endif

	ifeq ($(comp),$(filter $(comp),gcc clang icc))
		ifeq ($(KERNEL),Darwin)
			CXXFLAGS += -mdynamic-no-pic
		endif
	endif
endif

### 3.4 Bits
ifeq ($(bits),64)
	CXXFLAGS += -DIS_64BIT
endif

### 3.5 prefetch
ifeq ($(prefetch),yes)
	ifeq ($(sse),yes)
		CXXFLAGS += -msse
	endif
else
	CXXFLAGS += -DNO_PREFETCH
endif

### 3.6 popcnt
ifeq ($(popcnt),yes)
	ifeq ($(arch),$(filter $(arch),ppc64 armv7 armv8 arm64))
		CXXFLAGS += -DUSE_POPCNT
	else ifeq ($(comp),icc)
		CXXFLAGS += -msse3 -DUSE_POPCNT
	else
		CXXFLAGS += -msse3 -mpopcnt -DUSE_POPCNT
	endif
endif

ifeq ($(avx2),yes)
	CXXFLAGS += -DUSE_AVX2
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mavx2
	endif
endif

ifeq ($(avx512),yes)
	CXXFLAGS += -DUSE_AVX512
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mavx512f -mavx512bw
	endif
endif

ifeq ($(vnni256),yes)
	CXXFLAGS += -DUSE_VNNI
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mavx512f -mavx512bw -mavx512vnni -mavx512dq -mavx512vl -mprefer-vector-width=256
	endif
endif

ifeq ($(vnni512),yes)
	CXXFLAGS += -DUSE_VNNI
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mavx512vnni -mavx512dq -mavx512vl
	endif
endif

ifeq ($(sse41),yes)
	CXXFLAGS += -DUSE_SSE41
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -msse4.1
	endif
endif

ifeq ($(ssse3),yes)
	CXXFLAGS += -DUSE_SSSE3
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mssse3
	endif
endif

ifeq ($(sse2),yes)
	CXXFLAGS += -DUSE_SSE2
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -msse2
	endif
endif

ifeq ($(mmx),yes)
	CXXFLAGS += -DUSE_MMX
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mmmx
	endif
endif

ifeq ($(neon),yes)
	CXXFLAGS += -DUSE_NEON
	ifeq ($(KERNEL),Linux)
		ifneq ($(COMP),ndk)
			ifneq ($(arch),armv8)
				CXXFLAGS += -mfpu=neon
			endif
		endif
	endif
endif

### 3.7 pext
ifeq ($(pext),yes)
	CXXFLAGS += -DUSE_PEXT
	ifeq ($(comp),$(filter $(comp),gcc clang mingw))
		CXXFLAGS += -mbmi2
	endif
endif

### 3.8 Link Time Optimization
### This is a mix of compile and link time options because the lto link phase
### needs access to the optimization flags.
ifeq ($(optimize),yes)
ifeq ($(debug), no)
	ifeq ($(comp),clang)
		CXXFLAGS += -flto=thin
		ifneq ($(findstring MINGW,$(KERNEL)),)
			CXXFLAGS += -fuse-ld=lld
		else ifneq ($(findstring MSYS,$(KERNEL)),)
			CXXFLAGS += -fuse-ld=lld
		endif
		LDFLAGS += $(CXXFLAGS)

	# GCC and CLANG use different methods for parallelizing LTO and CLANG pretends to be
	# GCC on some systems.
	else ifeq ($(comp),gcc)
		ifeq ($(gccisclang),)
			CXXFLAGS += -flto
			LDFLAGS += $(CXXFLAGS) -flto=jobserver
			ifneq ($(findstring MINGW,$(KERNEL)),)
				LDFLAGS += -save-temps
			else ifneq ($(findstring MSYS,$(KERNEL)),)
				LDFLAGS += -save-temps
			endif
		else
			CXXFLAGS += -flto=thin
			LDFLAGS += $(CXXFLAGS)
		endif

	# To use LTO and static linking on windows, the tool chain requires a recent gcc:
	# gcc version 10.1 in msys2 or TDM-GCC version 9.2 are known to work, older might not.
	# So, only enable it for a cross from Linux by default.
	else ifeq ($(comp),mingw)
		ifeq ($(KERNEL),Linux)
			ifneq ($(arch),i386)
				CXXFLAGS += -flto
				LDFLAGS += $(CXXFLAGS) -flto=jobserver
			endif
		endif
	endif
endif
endif

### 3.9 Android 5 can only run position independent executables. Note that this
### breaks Android 4.0 and earlier.
ifeq ($(OS), Android)
	CXXFLAGS += -fPIE
	LDFLAGS += -fPIE -pie
endif

### 3.10 coverage
ifeq ($(coverage),yes)
	CXXFLAGS       += -fprofile-arcs -ftest-coverage --coverage -O0 -g
	CXXFLAGS       := $(filter-out -flto% -O3,$(CXXFLAGS))
	CXXFLAGS_TEST  += -fprofile-arcs -ftest-coverage --coverage
	LDFLAGS        += --coverage
endif

### ==========================================================================
### Section 4. Public Targets
### ==========================================================================

help:
	@echo ""
	@echo "To compile sanmill, type: "
	@echo ""
	@echo "make target ARCH=arch [COMP=compiler] [COMPCXX=cxx]"
	@echo ""
	@echo "Supported targets:"
	@echo ""
	@echo "help                    > Display architecture details"
	@echo "build                   > Standard build"
	@echo "net                     > Download the default nnue net"
	@echo "profile-build           > Faster build (with profile-guided optimization)"
	@echo "strip                   > Strip executable"
	@echo "install                 > Install executable"
	@echo "clean                   > Clean up"
	@echo "test                    > Run unit tests with GoogleTest"
	@echo "coverage                > Run tests and generate coverage report"
	@echo ""
	@echo "Supported archs:"
	@echo ""
	@echo "x86-64-vnni512          > x86 64-bit with vnni support 512bit wide"
	@echo "x86-64-vnni256          > x86 64-bit with vnni support 256bit wide"
	@echo "x86-64-avx512           > x86 64-bit with avx512 support"
	@echo "x86-64-bmi2             > x86 64-bit with bmi2 support"
	@echo "x86-64-avx2             > x86 64-bit with avx2 support"
	@echo "x86-64-sse41-popcnt     > x86 64-bit with sse41 and popcnt support"
	@echo "x86-64-modern           > common modern CPU, currently x86-64-sse41-popcnt"
	@echo "x86-64-ssse3            > x86 64-bit with ssse3 support"
	@echo "x86-64-sse3-popcnt      > x86 64-bit with sse3 and popcnt support"
	@echo "x86-64                  > x86 64-bit generic (with sse2 support)"
	@echo "x86-32-sse41-popcnt     > x86 32-bit with sse41 and popcnt support"
	@echo "x86-32-sse2             > x86 32-bit with sse2 support"
	@echo "x86-32                  > x86 32-bit generic (with mmx and sse support)"
	@echo "ppc-64                  > PPC 64-bit"
	@echo "ppc-32                  > PPC 32-bit"
	@echo "armv7                   > ARMv7 32-bit"
	@echo "armv7-neon              > ARMv7 32-bit with popcnt and neon"
	@echo "armv8                   > ARMv8 64-bit with popcnt and neon"
	@echo "apple-silicon           > Apple silicon ARM64"
	@echo "general-64              > unspecified 64-bit"
	@echo "general-32              > unspecified 32-bit"
	@echo ""
	@echo "Supported compilers:"
	@echo ""
	@echo "gcc                     > GNU compiler (default)"
	@echo "mingw                   > GNU compiler with MinGW under Windows"
	@echo "clang                   > LLVM Clang compiler"
	@echo "icc                     > Intel compiler"
	@echo "ndk                     > Google NDK to cross-compile for Android"
	@echo ""
	@echo "Simple examples. If you don't know what to do, you likely want to run: "
	@echo ""
	@echo "make -j build ARCH=x86-64  (A portable, slow compile for 64-bit systems)"
	@echo "make -j build ARCH=x86-32  (A portable, slow compile for 32-bit systems)"
	@echo ""
	@echo "Advanced examples, for experienced users looking for performance: "
	@echo ""
	@echo "make    help  ARCH=x86-64-bmi2"
	@echo "make -j profile-build ARCH=x86-64-bmi2 COMP=gcc COMPCXX=g++-9.0"
	@echo "make -j build ARCH=x86-64-ssse3 COMP=clang"
	@echo ""
	@echo "-------------------------------"
ifeq ($(SUPPORTED_ARCH)$(help_skip_sanity), true)
	@echo "The selected architecture $(ARCH) will enable the following configuration: "
	@$(MAKE) ARCH=$(ARCH) COMP=$(COMP) config-sanity
else
	@echo "Specify a supported architecture with the ARCH option for more details"
	@echo ""
endif


.PHONY: help build profile-build strip install clean coverage objclean profileclean \
	config-sanity icc-profile-use icc-profile-make gcc-profile-use gcc-profile-make \
	clang-profile-use clang-profile-make test check-gtest coverage-report net

build: net config-sanity
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) all
	@echo "CXXFLAGS: $(CXXFLAGS)"
	@echo "CXXFLAGS_TEST: $(CXXFLAGS_TEST)"
	@echo "LDFLAGS: $(LDFLAGS)"

profile-build: net config-sanity objclean profileclean
	@echo ""
	@echo "Step 1/4. Building instrumented executable ..."
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) $(profile_make)
	@echo ""
	@echo "Step 2/4. Running benchmark for pgo-build ..."
	$(PGOBENCH) > /dev/null
	@echo ""
	@echo "Step 3/4. Building optimized executable ..."
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) objclean
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) $(profile_use)
	@echo ""
	@echo "Step 4/4. Deleting profile data ..."
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) profileclean

strip:
	$(STRIP) $(EXE)

install:
	-mkdir -p -m 755 $(BINDIR)
	-cp $(EXE) $(BINDIR)
	-strip $(BINDIR)/$(EXE)

# clean all
clean: objclean profileclean coverage-clean
	@rm -f .depend *~ core

# clean binaries and objects
objclean:
	@rm -f $(EXE) $(TEST_EXE) *.o *.test.o ./syzygy/*.o ./nnue/*.o ./nnue/features/*.o ./perfect/*.o ../tests/*.o

# clean auxiliary profiling files and coverage data
profileclean: coverage-clean
	@rm -rf profdir
	@rm -f bench.txt *.gcda *.gcno ./syzygy/*.gcda ./nnue/*.gcda ./nnue/features/*.gcda *.s
	@rm -f sanmill.profdata *.profraw

default:
	help

### ==========================================================================
### Section 5. Private Targets
### ==========================================================================

all: $(EXE) $(TEST_EXE) .depend

config-sanity: net
	@echo ""
	@echo "Config:"
	@echo "debug: '$(debug)'"
	@echo "sanitize: '$(sanitize)'"
	@echo "optimize: '$(optimize)'"
	@echo "coverage: '$(coverage)'"
	@echo "arch: '$(arch)'"
	@echo "bits: '$(bits)'"
	@echo "kernel: '$(KERNEL)'"
	@echo "os: '$(OS)'"
	@echo "prefetch: '$(prefetch)'"
	@echo "popcnt: '$(popcnt)'"
	@echo "pext: '$(pext)'"
	@echo "sse: '$(sse)'"
	@echo "mmx: '$(mmx)'"
	@echo "sse2: '$(sse2)'"
	@echo "ssse3: '$(ssse3)'"
	@echo "sse41: '$(sse41)'"
	@echo "avx2: '$(avx2)'"
	@echo "avx512: '$(avx512)'"
	@echo "vnni256: '$(vnni256)'"
	@echo "vnni512: '$(vnni512)'"
	@echo "neon: '$(neon)'"
	@echo ""
	@echo "Flags:"
	@echo "CXX: $(CXX)"
	@echo "CXXFLAGS: $(CXXFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"
	@echo ""
	@echo "Testing config sanity. If this fails, try 'make help' ..."
	@echo ""
	@test "$(debug)" = "yes" || test "$(debug)" = "no"
	@test "$(sanitize)" = "undefined" || test "$(sanitize)" = "thread" || test "$(sanitize)" = "address" || test "$(sanitize)" = "no"
	@test "$(optimize)" = "yes" || test "$(optimize)" = "no"
	@test "$(SUPPORTED_ARCH)" = "true"
	@test "$(arch)" = "any" || test "$(arch)" = "x86_64" || test "$(arch)" = "i386" || \
	 test "$(arch)" = "ppc64" || test "$(arch)" = "ppc" || \
	 test "$(arch)" = "armv7" || test "$(arch)" = "armv8" || test "$(arch)" = "arm64"
	@test "$(bits)" = "32" || test "$(bits)" = "64"
	@test "$(prefetch)" = "yes" || test "$(prefetch)" = "no"
	@test "$(popcnt)" = "yes" || test "$(popcnt)" = "no"
	@test "$(pext)" = "yes" || test "$(pext)" = "no"
	@test "$(sse)" = "yes" || test "$(sse)" = "no"
	@test "$(mmx)" = "yes" || test "$(mmx)" = "no"
	@test "$(sse2)" = "yes" || test "$(sse2)" = "no"
	@test "$(ssse3)" = "yes" || test "$(ssse3)" = "no"
	@test "$(sse41)" = "yes" || test "$(sse41)" = "no"
	@test "$(avx2)" = "yes" || test "$(avx2)" = "no"
	@test "$(avx512)" = "yes" || test "$(avx512)" = "no"
	@test "$(vnni256)" = "yes" || test "$(vnni256)" = "no"
	@test "$(vnni512)" = "yes" || test "$(vnni512)" = "no"
	@test "$(neon)" = "yes" || test "$(neon)" = "no"
	@test "$(comp)" = "gcc" || test "$(comp)" = "icc" || test "$(comp)" = "mingw" || test "$(comp)" = "clang" \
	|| test "$(comp)" = "armv7a-linux-androideabi16-clang"  || test "$(comp)" = "aarch64-linux-android21-clang"

# Link main executable
$(EXE): $(OBJS)
	+$(CXX) -o $@ $(OBJS) $(LDFLAGS)

# Profile-guided optimization targets
clang-profile-make:
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) \
	EXTRACXXFLAGS='-fprofile-instr-generate ' \
	EXTRALDFLAGS=' -fprofile-instr-generate' \
	all

clang-profile-use:
	$(XCRUN) llvm-profdata merge -output=sanmill.profdata *.profraw
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) \
	EXTRACXXFLAGS='-fprofile-instr-use=sanmill.profdata' \
	EXTRALDFLAGS='-fprofile-use ' \
	all

gcc-profile-make:
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) \
	EXTRACXXFLAGS='-fprofile-generate' \
	EXTRALDFLAGS='-lgcov' \
	all

gcc-profile-use:
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) \
	EXTRACXXFLAGS='-fprofile-use -fno-peel-loops -fno-tracer' \
	EXTRALDFLAGS='-lgcov' \
	all

icc-profile-make:
	@mkdir -p profdir
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) \
	EXTRACXXFLAGS='-prof-gen=srcpos -prof_dir ./profdir' \
	all

icc-profile-use:
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) \
	EXTRACXXFLAGS='-prof_use -prof_dir ./profdir' \
	all

.depend: Makefile $(SRCS)
	-@$(CXX) $(CXXFLAGS) $(DEPENDFLAGS) -MM $(SRCS) > $@ 2> /dev/null

-include .depend

### ==========================================================================
### Section 6. GoogleTest Testing Support
### ==========================================================================
# The following section adds support for unit testing using GoogleTest.

### Define test sources and objects
# Assume that test source files are located in the 'tests' directory
TEST_SRCS = $(wildcard ../tests/*.cpp)
TEST_OBJS = $(TEST_SRCS:.cpp=.o)

### Define test executable name
ifeq ($(COMP),mingw)
	TEST_EXE = test_sanmill.exe
else
	TEST_EXE = test_sanmill
endif

### Define GoogleTest compiler and linker flags based on OS
# Use pkg-config where available (common in Unix-like systems)
ifeq ($(OS), Linux)
	GTEST_CFLAGS = $(shell pkg-config --cflags gtest)
	GTEST_LIBS = $(shell pkg-config --libs gtest) -lgtest_main
endif

ifeq ($(OS), macOS)
	GTEST_CFLAGS = $(shell pkg-config --cflags gtest)
	GTEST_LIBS = $(shell pkg-config --libs gtest)
endif

# For Windows (MinGW), assume Google Test is installed in a known location
ifeq ($(comp),mingw)
	# Adjust these paths according to your GoogleTest installation
	GTEST_CFLAGS = -IC:/path/to/gtest/include
	GTEST_LIBS = -LC:/path/to/gtest/lib -lgtest -lgtest_main -lpthread
endif

# Add other OS-specific configurations if necessary

### Define separate compiler flags for tests
CXXFLAGS_TEST = $(CXXFLAGS) $(GTEST_CFLAGS)

### Pattern rule: compile library source files to .test.o with test flags
%.test.o: %.cpp
	@echo "Compiling $< for tests..."
	$(CXX) $(CXXFLAGS_TEST) $(GTEST_CFLAGS) -c $< -o $@

### Ensure GoogleTest is installed
# This target checks if the GoogleTest package is available via pkg-config or predefined paths
check-gtest:
ifeq ($(OS), Linux)
	@pkg-config --exists gtest || { echo >&2 "GoogleTest is required but it's not installed. Aborting."; exit 1; }
endif
ifeq ($(OS), macOS)
	@pkg-config --exists gtest || { echo >&2 "GoogleTest is required but it's not installed. Aborting."; exit 1; }
endif
ifeq ($(comp),mingw)
	# Simple check: verify that GoogleTest include and lib directories exist
	@if [ ! -d "C:/path/to/gtest/include" ] || [ ! -d "C:/path/to/gtest/lib" ]; then \
		echo >&2 "GoogleTest is required but it's not installed in C:/path/to/gtest/. Aborting."; \
		exit 1; \
	fi
endif

### Add a 'test' target to build and run tests
test: check-gtest $(TEST_EXE)
	@echo "Running unit tests..."
	./$(TEST_EXE)

### Rule to build the test executable
$(TEST_EXE): $(TEST_OBJS) $(LIB_OBJS_TEST)
	@echo "Linking test executable..."
	$(CXX) -o $@ $(TEST_OBJS) $(LIB_OBJS_TEST) $(LDFLAGS) $(GTEST_LIBS)

### Compile test source files with GoogleTest flags
../tests/%.o: ../tests/%.cpp
	@echo "Compiling $< for tests..."
	$(CXX) $(CXXFLAGS_TEST) $(GTEST_CFLAGS) -c $< -o $@

### ==========================================================================
### Section 7. Coverage Support
### ==========================================================================
# The following section adds support for generating coverage reports using gcov and gcovr.

### Define coverage-related variables
PROJECT_ROOT := $(shell pwd)
COVERAGE_DIR = $(PROJECT_ROOT)/coverage
COVERAGE_HTML = $(COVERAGE_DIR)/coverage.html

### Add a 'coverage' target to build with coverage, run tests, and generate report
coverage: coverage-clean
	@echo "Building with coverage flags..."
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) coverage-build
	@echo "Running tests..."
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) test
	@echo "Generating HTML coverage report..."
	@mkdir -p $(COVERAGE_DIR)
	@gcovr -r $(PROJECT_ROOT) --html-details -o $(COVERAGE_HTML) --exclude '/usr/*' --exclude '../tests/*'
	@echo "Coverage report generated in $(COVERAGE_HTML)"

### Helper target to build with coverage flags
coverage-build:
	$(MAKE) ARCH=$(ARCH) COMP=$(COMP) clean all coverage=yes optimize=no debug=yes

ifeq ($(coverage), yes)
override CXXFLAGS       += -fprofile-arcs -ftest-coverage --coverage -O0 -g
override CXXFLAGS       := $(filter-out -flto% -O3,$(CXXFLAGS))
override CXXFLAGS_TEST  += -fprofile-arcs -ftest-coverage --coverage
override LDFLAGS        += --coverage
endif

### Add a 'coverage-clean' target to remove previous coverage data
coverage-clean:
	@rm -f *.gcda *.gcno *.gcov
	@rm -rf $(COVERAGE_DIR)
	@rm -f $(COVERAGE_DIR)/coverage.html
