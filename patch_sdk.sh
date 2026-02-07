#!/bin/bash
# Patch Milk-V SDK link flags for tinyalsa dependency.
# This fixes undefined references to pcm_* from libcvi_audio.so during ISP tool build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${1:-$SCRIPT_DIR/duo-buildroot-sdk-v2}"
TINYALSA_FLAGS="-Wl,--no-as-needed -ltinyalsa -Wl,--as-needed"
RTSP_LIB_FLAGS="-Wl,--no-as-needed -lcvi_rtsp_service -lcvi_rtsp -Wl,--as-needed"
RTSP_LIB_LINE="LIBS += -L/source/cvi_rtsp/src -L/source/cvi_rtsp/service -ldl ${RTSP_LIB_FLAGS}"
LOCAL_LDFLAGS_LINE='LOCAL_LDFLAGS = -Wl,--allow-shlib-undefined -Wl,--copy-dt-needed-entries -Wl,--no-as-needed $(LIBS) -Wl,-rpath-link=$(CVI_RTSP_LIB_PATH) -L$(CVI_ISPD2_PATH) -L$(CVI_RTSP_LIB_PATH) -lm -lpthread -lrt -Wl,--as-needed'

if [ ! -d "$SDK_DIR" ]; then
    echo "patch_sdk.sh: SDK directory not found: $SDK_DIR"
    exit 1
fi

patch_makefile() {
    local file="$1"
    local changed=0

    # 1) Keep tinyalsa linked even with --as-needed toolchains.
    if ! grep -q -- "$TINYALSA_FLAGS" "$file"; then
        if grep -q -- "-ltinyalsa" "$file"; then
            sed -i 's/-ltinyalsa/-Wl,--no-as-needed -ltinyalsa -Wl,--as-needed/' "$file"
            changed=1
        elif grep -qE '^LIBS[[:space:]]*\+=.*-lsbc' "$file"; then
            sed -i -E '/^LIBS[[:space:]]*\+=.*-lsbc/ s/$/ -Wl,--no-as-needed -ltinyalsa -Wl,--as-needed/' "$file"
            changed=1
        elif grep -qE '^LIBS[[:space:]]*\+=' "$file"; then
            sed -i -E '0,/^LIBS[[:space:]]*\+=/ s/$/ -Wl,--no-as-needed -ltinyalsa -Wl,--as-needed/' "$file"
            changed=1
        fi
    fi

    # 2) Ensure RTSP service comes before RTSP core and is not dropped by as-needed.
    if ! grep -q -- "$RTSP_LIB_FLAGS" "$file"; then
        if grep -q 'LIBS += -L/source/cvi_rtsp/src -L/source/cvi_rtsp/service -ldl -lcvi_rtsp -lcvi_rtsp_service' "$file"; then
            sed -i 's|LIBS += -L/source/cvi_rtsp/src -L/source/cvi_rtsp/service -ldl -lcvi_rtsp -lcvi_rtsp_service|'"$RTSP_LIB_LINE"'|' "$file"
            changed=1
        fi
    fi

    # 3) Normalize final link flags for host-linker compatibility.
    # Some host toolchains are stricter about unresolved symbols in dependent shared libs.
    if ! grep -qF "$LOCAL_LDFLAGS_LINE" "$file"; then
        if grep -q '^LOCAL_LDFLAGS =' "$file"; then
            sed -i "s|^LOCAL_LDFLAGS = .*|${LOCAL_LDFLAGS_LINE}|" "$file"
        else
            printf '\n%s\n' "$LOCAL_LDFLAGS_LINE" >> "$file"
        fi
        changed=1
    fi

    if grep -q -- "$TINYALSA_FLAGS" "$file" && \
       grep -q -- "$RTSP_LIB_FLAGS" "$file" && \
       grep -q -- '-Wl,--allow-shlib-undefined' "$file" && \
       grep -q -- '-Wl,--copy-dt-needed-entries' "$file" && \
       grep -q 'LOCAL_LDFLAGS = -Wl,--allow-shlib-undefined -Wl,--copy-dt-needed-entries -Wl,--no-as-needed $(LIBS)' "$file" && \
       grep -q -- '-lrt' "$file" && \
       grep -q -- '-Wl,--as-needed' "$file"; then
        if [ "$changed" -eq 1 ]; then
            echo "patch_sdk.sh: patched $file"
        else
            echo "patch_sdk.sh: already patched $file"
        fi
        return 0
    fi

    echo "patch_sdk.sh: failed to patch $file"
    return 1
}

patch_pkgconfig() {
    local file="$1"
    local changed=0

    if [ ! -f "$file" ]; then
        return 0
    fi

    if grep -q -- "$TINYALSA_FLAGS" "$file"; then
        echo "patch_sdk.sh: already patched $file"
        return 0
    fi

    if grep -q -- "-ltinyalsa" "$file"; then
        sed -i 's/-ltinyalsa/-Wl,--no-as-needed -ltinyalsa -Wl,--as-needed/' "$file"
        changed=1
    elif grep -q '^Libs:' "$file"; then
        sed -i "/^Libs:/ s/$/ $TINYALSA_FLAGS/" "$file"
        changed=1
    fi

    if grep -q -- "$TINYALSA_FLAGS" "$file"; then
        if [ "$changed" -eq 1 ]; then
            echo "patch_sdk.sh: patched $file"
        else
            echo "patch_sdk.sh: verified $file"
        fi
        return 0
    fi

    echo "patch_sdk.sh: failed to patch $file"
    return 1
}

patch_rtsp_test_makefile() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 0
    fi

    if grep -qE '^-?LDFLAGS.*-lrt([[:space:]]|$)' "$file"; then
        echo "patch_sdk.sh: already patched $file"
        return 0
    fi

    if grep -q '^LDFLAGS += .*MW_AUDIO_LIB' "$file"; then
        sed -i '/^LDFLAGS += .*MW_AUDIO_LIB/ s/$/ -lrt/' "$file"
        echo "patch_sdk.sh: patched $file"
        return 0
    fi

    echo "patch_sdk.sh: failed to patch $file"
    return 1
}

PATCH_ROOT="$SDK_DIR/cvi_mpi/modules/isp"
if [ -d "$PATCH_ROOT" ]; then
    mapfile -t PATCH_FILES < <(find "$PATCH_ROOT" -type f -path "*/isp-tool-daemon/isp_daemon_tool/Makefile" 2>/dev/null | sort)
else
    PATCH_FILES=()
fi

if [ "${#PATCH_FILES[@]}" -eq 0 ]; then
    echo "patch_sdk.sh: warning: no isp_daemon_tool Makefiles found in $SDK_DIR"
fi

for f in "${PATCH_FILES[@]}"; do
    patch_makefile "$f"
done

patch_pkgconfig "$SDK_DIR/cvi_mpi/pkgconfig/cvi_audio.pc"
patch_rtsp_test_makefile "$SDK_DIR/cvi_rtsp/test/Makefile"
