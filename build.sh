#!/bin/sh -e

# This script runs one build with setup environment variables: BUILD_LIBPCAP,
# REMOTE, CC, CMAKE, CRYPTO and SMB.

: "${BUILD_LIBPCAP:=no}"
: "${REMOTE:=no}"
: "${CC:=gcc}"
: "${CMAKE:=no}"
: "${CRYPTO:=no}"
: "${SMB:=no}"
: "${TCPDUMP_TAINTED:=no}"
: "${TCPDUMP_CMAKE_TAINTED:=no}"
: "${MAKE_BIN:=make}"
# At least one OS (AIX 7) where this software can build does not have at least
# one command (mktemp) required for a successful run of "make releasetar".
: "${TEST_RELEASETAR:=yes}"

. ./build_common.sh
# Install directory prefix
if [ -z "$PREFIX" ]; then
    PREFIX=`mktempdir tcpdump_build`
    echo "PREFIX set to '$PREFIX'"
    DELETE_PREFIX=yes
fi
TCPDUMP_BIN="$PREFIX/bin/tcpdump"
# For TESTrun
export TCPDUMP_BIN

print_cc_version

# The norm is to compile without any warnings, but tcpdump builds on some OSes
# are not warning-free for one or another reason.  If you manage to fix one of
# these cases, please remember to remove respective exemption below to help any
# later warnings in the same matrix subset trigger an error.

case `cc_id`/`os_id` in
suncc-5.1[45]/SunOS-5.11)
    # Various E_STATEMENT_NOT_REACHED and E_DEPRECATED_ATT warnings.
    TCPDUMP_TAINTED=yes
    ;;
tcc-*/*)
    # print-802_11.c:3317: warning: assignment discards qualifiers from pointer
    #   target type
    TCPDUMP_TAINTED=yes
    ;;
*)
    ;;
esac

[ "$TCPDUMP_TAINTED" != yes ] && CFLAGS=`cc_werr_cflags`

case `cc_id`/`os_id` in
clang-*/SunOS-5.11)
    # Work around https://www.illumos.org/issues/16369
    [ "`uname -o`" = illumos ] && grep -Fq OpenIndiana /etc/release && CFLAGS="-Wno-fuse-ld-path${CFLAGS:+ $CFLAGS}"
    ;;
esac

# If necessary, set TCPDUMP_CMAKE_TAINTED here to exempt particular cmake from
# warnings. Use as specific terms as possible (e.g. some specific version and
# some specific OS).

[ "$TCPDUMP_CMAKE_TAINTED" != yes ] && CMAKE_OPTIONS='-Werror=dev'

if [ "$CMAKE" = no ]; then
    if [ "$BUILD_LIBPCAP" = yes ]; then
        echo "Using PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
        run_after_echo ./autogen.sh
        run_after_echo ./configure --with-crypto="$CRYPTO" \
            --enable-smb="$SMB" --prefix="$PREFIX"
        LD_LIBRARY_PATH="$PREFIX/lib"
        export LD_LIBRARY_PATH
    else
        run_after_echo ./autogen.sh
        run_after_echo ./configure --with-crypto="$CRYPTO" \
            --enable-smb="$SMB" --prefix="$PREFIX" --disable-local-libpcap
    fi
else
    # See libpcap build.sh for the rationale.
    run_after_echo rm -rf CMakeFiles/ CMakeCache.txt build/
    run_after_echo mkdir build
    run_after_echo cd build
    if [ "$BUILD_LIBPCAP" = yes ]; then
        run_after_echo cmake ${CMAKE_OPTIONS:+"$CMAKE_OPTIONS"} \
            -DWITH_CRYPTO="$CRYPTO" -DENABLE_SMB="$SMB" \
            ${CFLAGS:+-DEXTRA_CFLAGS="$CFLAGS"} \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" ..
        LD_LIBRARY_PATH="$PREFIX/lib"
        export LD_LIBRARY_PATH
    else
        run_after_echo cmake ${CMAKE_OPTIONS:+"$CMAKE_OPTIONS"} \
            -DWITH_CRYPTO="$CRYPTO" -DENABLE_SMB="$SMB" \
             ${CFLAGS:+-DEXTRA_CFLAGS="$CFLAGS"} \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" ..
    fi
fi
run_after_echo "$MAKE_BIN" -s clean
if [ "$CMAKE" = no ]; then
    run_after_echo "$MAKE_BIN" -s ${CFLAGS:+CFLAGS="$CFLAGS"}
else
    # The "-s" flag is a no-op and CFLAGS is set using -DEXTRA_CFLAGS above.
    run_after_echo "$MAKE_BIN"
fi
run_after_echo "$MAKE_BIN" install
print_so_deps "$TCPDUMP_BIN"
run_after_echo "$TCPDUMP_BIN" -h
# The "-D" flag depends on HAVE_PCAP_FINDALLDEVS and it would not be difficult
# to run the command below only if the macro is defined.  That said, it seems
# more useful to run it anyway: every system that currently runs this script
# has pcap_findalldevs(), thus if the macro isn't defined, it means something
# went wrong in the build process (as was observed with GCC, CMake and the
# system libpcap on Solaris 11).
run_after_echo "$TCPDUMP_BIN" -D
if [ "$CIRRUS_CI" = true ]; then
    # Likewise for the "-J" flag and HAVE_PCAP_SET_TSTAMP_TYPE.
    run_after_echo sudo \
        ${LD_LIBRARY_PATH:+LD_LIBRARY_PATH="$LD_LIBRARY_PATH"} \
        "$TCPDUMP_BIN" -J
    run_after_echo sudo \
        ${LD_LIBRARY_PATH:+LD_LIBRARY_PATH="$LD_LIBRARY_PATH"} \
        "$TCPDUMP_BIN" -L
fi
if [ "$BUILD_LIBPCAP" = yes ]; then
    run_after_echo "$MAKE_BIN" check
fi
if [ "$CMAKE" = no ]; then
    [ "$TEST_RELEASETAR" = yes ] && run_after_echo "$MAKE_BIN" releasetar
fi
if [ "$CIRRUS_CI" = true ]; then
    run_after_echo sudo \
        ${LD_LIBRARY_PATH:+LD_LIBRARY_PATH="$LD_LIBRARY_PATH"} \
        "$TCPDUMP_BIN" -#n -c 10
fi
handle_matrix_debug
if [ "$DELETE_PREFIX" = yes ]; then
    run_after_echo rm -rf "$PREFIX"
fi
# vi: set tabstop=4 softtabstop=0 expandtab shiftwidth=4 smarttab autoindent :
