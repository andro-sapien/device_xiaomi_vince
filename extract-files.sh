#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017, 2019 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# If we're being sourced by the common script that we called,
# stop right here. No need to go down the rabbit hole.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    return
fi

set -e

# Required!
DEVICE=vince
VENDOR=xiaomi

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

CHERISH_ROOT="${MY_DIR}/../../.."

HELPER="${CHERISH_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=false

SECTION=
KANG=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${CHERISH_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}"/proprietary-files.txt "${SRC}" \
        "${KANG}" --section "${SECTION}"

function blob_fixup() {
	case "${1}" in

	product/lib64/libdpmframework.so)
	    "${PATCHELF}" --add-needed libdpmframework_shim.so "${2}"
	;;
	vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc)
	    sed -i 's/fps_hal/vendor.fps_hal/' "${2}"
	    sed -i 's/group.*/& uhid/' "${2}"
	;;
	vendor/lib64/libvendor.goodix.hardware.fingerprint@1.0-service.so)
	    "${PATCHELF_0_8}" --remove-needed "libprotobuf-cpp-lite.so" "${2}"
	;;
	vendor/lib/libmmcamera_ppeiscore.so)
	    "${PATCHELF}" --add-needed libmmcamera_ppeiscore_shim.so  "${DEVICE_BLOB_ROOT}"/vendor/lib/libmmcamera_ppeiscore.so
	;;
	vendor/lib/libmmcamera2_iface_modules.so)
	    # Always set 0 (Off) as CDS mode in iface_util_set_cds_mode
	    sed -i -e 's|\x1d\xb3\x20\x68|\x1d\xb3\x00\x20|g' "${2}"
	    PATTERN_FOUND=$(hexdump -ve '1/1 "%.2x"' "${2}" | grep -E -o "1db30020" | wc -l)
	    if [ $PATTERN_FOUND != "1" ]; then
	        echo "Critical blob modification weren't applied on ${2}!"
	        exit;
	    fi
	;;
	esac

}

DEVICE_BLOB_ROOT="${CHERISH_ROOT}"/vendor/"${VENDOR}"/"${DEVICE}"/proprietary

# Camera configs
sed -i "s|/system/etc/camera|/vendor/etc/camera|g" "${DEVICE_BLOB_ROOT}"/vendor/lib/libmmcamera2_sensor_modules.so

# Camera socket
sed -i "s|/data/misc/camera/cam_socket|/data/vendor/qcam/cam_socket|g" "${DEVICE_BLOB_ROOT}"/vendor/bin/mm-qcamera-daemon

# Camera data
for CAMERA_LIB in libmmcamera2_cpp_module.so libmmcamera2_dcrf.so libmmcamera2_iface_modules.so libmmcamera2_imglib_modules.so libmmcamera2_mct.so libmmcamera2_pproc_modules.so libmmcamera2_q3a_core.so libmmcamera2_sensor_modules.so libmmcamera2_stats_algorithm.so libmmcamera2_stats_modules.so libmmcamera_dbg.so libmmcamera_imglib.so libmmcamera_pdafcamif.so libmmcamera_pdaf.so libmmcamera_tintless_algo.so libmmcamera_tintless_bg_pca_algo.so libmmcamera_tuning.so; do
    sed -i "s|/data/misc/camera/|/data/vendor/qcam/|g" "${DEVICE_BLOB_ROOT}"/vendor/lib/${CAMERA_LIB}
done

# Camera debug log file
sed -i "s|persist.camera.debug.logfile|persist.vendor.camera.dbglog|g" "${DEVICE_BLOB_ROOT}"/vendor/lib/libmmcamera_dbg.so

"${MY_DIR}/setup-makefiles.sh"
