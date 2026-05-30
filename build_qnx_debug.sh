#!/bin/bash
set -e

# QNX jemalloc build script (with profiling/stats support for performance debugging)
# Usage: ./build_qnx_debug.sh [aarch64le|x86_64|armv7le]

# Default architecture
TARGET_ARCH=${1:-aarch64le}

echo "========================================"
echo "Building jemalloc for QNX (${TARGET_ARCH})"
echo "WITH PROFILING AND STATS SUPPORT"
echo "========================================"

# Check QNX SDP environment
if [ -z "$QNX_SDP" ]; then
    # Try default location
    if [ -d "$HOME/qnx800" ]; then
        export QNX_SDP="$HOME/qnx800"
    elif [ -d "/opt/qnx800" ]; then
        export QNX_SDP="/opt/qnx800"
    else
        echo "ERROR: QNX_SDP not set and default location not found"
        echo "Please set QNX_SDP environment variable or source qnxsdp-env.sh"
        exit 1
    fi
fi

echo "QNX SDP: $QNX_SDP"

# Source QNX environment
if [ -f "$QNX_SDP/qnxsdp-env.sh" ]; then
    source "$QNX_SDP/qnxsdp-env.sh"
    echo "Sourced QNX environment"
else
    echo "ERROR: Cannot find qnxsdp-env.sh in $QNX_SDP"
    exit 1
fi

# Set target
export HOST=nto${TARGET_ARCH}
# Use a recognized host tuple for configure
case "$TARGET_ARCH" in
    aarch64le)
        CONFIGURE_HOST="aarch64-unknown-linux-gnu"
        ;;
    x86_64)
        CONFIGURE_HOST="x86_64-unknown-linux-gnu"
        ;;
    armv7le)
        CONFIGURE_HOST="arm-unknown-linux-gnueabi"
        ;;
    *)
        CONFIGURE_HOST="${TARGET_ARCH}-unknown-linux-gnu"
        ;;
esac
echo "Target: $HOST (configure host: $CONFIGURE_HOST)"

# QCC target specification
case "$TARGET_ARCH" in
    aarch64le) QCC_TARGET="gcc_ntoaarch64le" ;;
    x86_64) QCC_TARGET="gcc_ntox86_64" ;;
    armv7le) QCC_TARGET="gcc_ntoarmv7le" ;;
    *) QCC_TARGET="gcc_nto${TARGET_ARCH}" ;;
esac

export CC="qcc -V${QCC_TARGET}"
export CXX="q++ -V${QCC_TARGET}"
export AR=${HOST}-ar
export RANLIB=${HOST}-ranlib
export LD=${HOST}-ld

# Strip tool name varies by architecture
case "$TARGET_ARCH" in
    aarch64le) STRIP=ntoaarch64-strip ;;
    x86_64) STRIP=ntox86_64-strip ;;
    armv7le) STRIP=ntoarm-strip ;;
    *) STRIP=${HOST}-strip ;;
esac

# Compiler flags for QNX (with debug symbols for profiling)
export CFLAGS="-DJEMALLOC_OS_QNX -D_QNX_SOURCE -D_POSIX_C_SOURCE=200809L -O2 -g"
export CXXFLAGS="-DJEMALLOC_OS_QNX -D_QNX_SOURCE -D_POSIX_C_SOURCE=200809L -O2 -g"

# Build directory
BUILD_DIR="build-qnx-${TARGET_ARCH}-debug"
INSTALL_DIR="$(pwd)/install-qnx-${TARGET_ARCH}-debug"

echo ""
echo "Build configuration:"
echo "  CC: $CC"
echo "  CFLAGS: $CFLAGS"
echo "  Build dir: $BUILD_DIR"
echo "  Install dir: $INSTALL_DIR"
echo "  STATS: enabled"
echo "  PROF: enabled"
echo ""

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Run autogen.sh if needed
if [ ! -f "../configure" ]; then
    echo "Running autogen.sh..."
    cd ..
    ./autogen.sh
    cd "$BUILD_DIR"
fi

# Configure for QNX (with stats and profiling for performance debugging)
echo ""
echo "Configuring..."
../configure \
    --host=${CONFIGURE_HOST} \
    --with-lg-page=12 \
    --disable-static \
    --enable-shared \
    --enable-stats \
    --enable-prof \
    --disable-fill \
    --disable-utrace \
    --disable-debug \
    --disable-cxx \
    --without-export \
    --prefix="$INSTALL_DIR"

# Build - use a workaround for QNX qcc/make interaction issue
echo ""
echo "Building..."

# Export SHELL to ensure bash is used
export SHELL=/bin/bash

# Compile all source files manually to work around make/qcc issues
SOURCES="jemalloc arena background_thread base bin bin_info bitmap buf_writer cache_bin ckh counter ctl decay div ecache edata edata_cache ehooks emap eset exp_grow extent extent_dss extent_mmap fxp san san_bump hook hpa hpa_hooks hpdata inspect large log malloc_io mutex nstime pa pa_extra pai pac pages peak_event prof prof_data prof_log prof_recent prof_stats prof_sys psset rtree safety_check sc sec stats sz tcache test_hooks thread_event ticker tsd witness"

CFLAGS_BASE="-std=gnu11 -Wall -Wextra -Wsign-compare -Wundef -Wno-format-zero-length -Wpointer-arith -Wno-missing-braces -Wno-missing-field-initializers -Wno-missing-attributes -g3 -fvisibility=hidden -Wimplicit-fallthrough -O3 -funroll-loops -DJEMALLOC_OS_QNX -D_QNX_SOURCE -D_POSIX_C_SOURCE=200809L -O2 -g -fPIC -DPIC -D_GNU_SOURCE -D_REENTRANT -Iinclude -I../include -DJEMALLOC_NO_PRIVATE_NAMESPACE"

echo "Compiling source files..."
mkdir -p src
for src in $SOURCES; do
    echo "  Compiling $src..."
    qcc -V${QCC_TARGET} $CFLAGS_BASE -c ../src/${src}.c -o src/${src}.sym.o
done

echo "Generating symbols..."
for src in $SOURCES; do
    nm -a src/${src}.sym.o | mawk -f include/jemalloc/internal/private_symbols.awk > src/${src}.sym
done

echo "Linking shared library..."
mkdir -p lib
qcc -V${QCC_TARGET} -shared -Wl,-soname,libjemalloc.so.2 -o lib/libjemalloc.so.2 \
    src/*.sym.o -lm

cd lib
ln -sf libjemalloc.so.2 libjemalloc.so
cd ..

# Install
echo ""
echo "Installing..."
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/include/jemalloc"

cp lib/libjemalloc.so.2 "$INSTALL_DIR/lib/"
cp lib/libjemalloc.so "$INSTALL_DIR/lib/"
cp -r include/jemalloc/* "$INSTALL_DIR/include/jemalloc/"
cp ../include/jemalloc/jemalloc.h "$INSTALL_DIR/include/jemalloc/" 2>/dev/null || true

# Note: Don't strip debug build to keep symbols for profiling
echo ""
echo "========================================"
echo "Build completed successfully!"
echo "========================================"
echo ""
echo "Library: $INSTALL_DIR/lib/libjemalloc.so"
echo "Headers: $INSTALL_DIR/include/jemalloc"
echo ""
echo "Performance debugging features enabled:"
echo "  - JEMALLOC_STATS: Memory allocation statistics"
echo "  - JEMALLOC_PROF:  Heap profiling support"
echo ""
echo "Usage for profiling:"
echo "  export MALLOC_CONF=\"prof:true,prof_prefix:/tmp/jeprof\""
echo "  export LD_LIBRARY_PATH=$INSTALL_DIR/lib:\$LD_LIBRARY_PATH"
echo ""
