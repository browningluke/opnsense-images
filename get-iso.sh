#!/usr/bin/env sh

set -eu

: "${PKR_VAR_MIRROR:?PKR_VAR_MIRROR must be set}"
: "${PKR_VAR_VERSION:?PKR_VAR_VERSION must be set}"

ISO_DIR="${ISO_DIR:-iso}"
KEY_DIR="${KEY_DIR:-keys}"

ISO_NAME="OPNsense-${PKR_VAR_VERSION}-dvd-amd64.iso"
ISO_ARCHIVE="${ISO_NAME}.bz2"
ISO_SIGNATURE="${ISO_NAME}.sig"

BASE_URL="${PKR_VAR_MIRROR%/}/releases/${PKR_VAR_VERSION}"

ISO_ARCHIVE_URL="${BASE_URL}/${ISO_ARCHIVE}"
ISO_SIGNATURE_URL="${BASE_URL}/${ISO_SIGNATURE}"
CHECKSUM_URL="${BASE_URL}/OPNsense-${PKR_VAR_VERSION}-checksums-amd64.sha256"

ISO_ARCHIVE_PATH="${ISO_DIR}/${ISO_ARCHIVE}"
ISO_PATH="${ISO_DIR}/${ISO_NAME}"
ISO_SIGNATURE_PATH="${ISO_DIR}/${ISO_SIGNATURE}"
CHECKSUM_PATH="${ISO_DIR}/OPNsense-${PKR_VAR_VERSION}-checksums-amd64.sha256"
SHA1_PATH="${ISO_PATH}.sha1"

KEY_VERSION="${PKR_VAR_VERSION}"
KEY_PATH="${KEY_DIR}/OPNsense-${KEY_VERSION}.pub"

echo
echo "========================================"
echo "OPNsense image download"
echo "========================================"
echo "Version : ${PKR_VAR_VERSION}"
echo "Mirror  : ${PKR_VAR_MIRROR}"
echo "Image   : ${ISO_NAME}"
echo

mkdir -p "${ISO_DIR}"

#
# Verify that the trusted public key exists locally.
#
if [ ! -f "${KEY_PATH}" ]; then
    echo "ERROR: Trusted OPNsense public key not found:" >&2
    echo "       ${KEY_PATH}" >&2
    echo >&2
    echo "The public key must be committed to the repository." >&2
    echo "Do not download the key automatically from the mirror." >&2
    exit 1
fi

#
# Download helper.
#
download() {
    URL="$1"
    TARGET="$2"

    echo "Downloading:"
    echo "  ${URL}"
    echo

    curl \
        --fail \
        --location \
        --show-error \
        --retry 5 \
        --retry-delay 5 \
        --continue-at - \
        --output "${TARGET}" \
        "${URL}"
}

#
# Download the compressed ISO.
#
if [ -f "${ISO_ARCHIVE_PATH}" ]; then
    echo "Using existing archive:"
    echo "  ${ISO_ARCHIVE_PATH}"
else
    download "${ISO_ARCHIVE_URL}" "${ISO_ARCHIVE_PATH}"
fi

#
# Download the official SHA256 checksum file.
#
if [ -f "${CHECKSUM_PATH}" ]; then
    echo "Using existing checksum file:"
    echo "  ${CHECKSUM_PATH}"
else
    download "${CHECKSUM_URL}" "${CHECKSUM_PATH}"
fi

#
# Extract the expected SHA256 checksum for the exact archive.
#
EXPECTED_SHA256="$(
    awk -v file="${ISO_ARCHIVE}" '
        $1 == "SHA256" && $2 == "(" file ")" && $3 == "=" {
            print $4
            exit
        }
    ' "${CHECKSUM_PATH}"
)"

if [ -z "${EXPECTED_SHA256}" ]; then
    echo >&2
    echo "ERROR: No SHA256 checksum found for:" >&2
    echo "       ${ISO_ARCHIVE}" >&2
    echo >&2
    echo "Checksum file:" >&2
    echo "       ${CHECKSUM_PATH}" >&2
    exit 1
fi

#
# Verify the downloaded .bz2 archive.
#
echo
echo "Verifying SHA256 of ${ISO_ARCHIVE}..."

if ! printf '%s  %s\n' \
        "${EXPECTED_SHA256}" \
        "${ISO_ARCHIVE_PATH}" \
        | sha256sum --check --status -; then

    echo >&2
    echo "ERROR: SHA256 verification failed." >&2
    echo "       ${ISO_ARCHIVE_PATH}" >&2
    echo >&2
    echo "Expected:" >&2
    echo "       ${EXPECTED_SHA256}" >&2
    exit 1
fi

echo "SHA256 verification successful."

#
# Download the detached signature for the ISO.
#
if [ -f "${ISO_SIGNATURE_PATH}" ]; then
    echo "Using existing signature:"
    echo "  ${ISO_SIGNATURE_PATH}"
else
    download "${ISO_SIGNATURE_URL}" "${ISO_SIGNATURE_PATH}"
fi

#
# Extract the ISO.
#
if [ -f "${ISO_PATH}" ]; then
    echo
    echo "Using existing ISO:"
    echo "  ${ISO_PATH}"
else
    echo
    echo "Extracting ${ISO_ARCHIVE}..."

    bzip2 \
        --decompress \
        --keep \
        "${ISO_ARCHIVE_PATH}"
fi

#
# Verify the detached OpenSSL signature.
#
#
# IMPORTANT:
#
# OPNsense signs the uncompressed image.
# The .sig file is base64 encoded.
#
# Therefore:
#
#   .iso.bz2
#       |
#       +-- SHA256 verification
#       |
#       +-- bunzip2
#              |
#              +-- .iso
#                    |
#                    +-- .sig verification
#
echo
echo "Verifying OpenSSL signature..."

SIGNATURE_FILE="$(mktemp)"

cleanup() {
    rm -f "${SIGNATURE_FILE}"
}

trap cleanup EXIT INT TERM

#
# OPNsense signatures are base64 encoded.
#
openssl base64 \
    -d \
    -in "${ISO_SIGNATURE_PATH}" \
    -out "${SIGNATURE_FILE}"

if ! openssl dgst \
        -sha256 \
        -verify "${KEY_PATH}" \
        -signature "${SIGNATURE_FILE}" \
        "${ISO_PATH}"; then

    echo >&2
    echo "ERROR: OPNsense image signature verification failed." >&2
    echo "       ${ISO_PATH}" >&2
    exit 1
fi

echo "OpenSSL signature verification successful."

#
# Calculate SHA1 of the uncompressed ISO.
#
#
# Packer currently expects:
#
#   sha1:<hash>
#
# OPNsense itself publishes SHA256 for the download, but the
# existing Packer configuration in opnsense-images expects SHA1
# for the local, uncompressed ISO.
#
echo
echo "Calculating SHA1 of ${ISO_NAME}..."

ISO_SHA1="$(sha1sum "${ISO_PATH}" | awk '{print $1}')"

printf '%s  %s\n' \
    "${ISO_SHA1}" \
    "${ISO_NAME}" \
    > "${SHA1_PATH}"

echo "ISO SHA1:"
echo "  ${ISO_SHA1}"

echo "SHA1 file:"
echo "  ${SHA1_PATH}"

#
# Export a Packer-compatible value for callers that source this
# script or inspect its output.
#
echo
echo "Packer checksum:"
echo "  sha1:${ISO_SHA1}"
echo
