#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${SCRIPT_DIR}/build}"
SITE_ROOT="${SITE_ROOT:-${BUILD_ROOT}/site}"

rm -rf "${BUILD_ROOT}"
mkdir -p "${SITE_ROOT}"

echo "==> Building Swift cookbook"
BUILD_ROOT="${BUILD_ROOT}/swift" \
SITE_ROOT="${SITE_ROOT}" \
BINARY_SITE_PATH="binaries/OuterframeCookbookSwift" \
BINARY_URL_PATH="${SWIFT_BINARY_URL_PATH:-/binaries/OuterframeCookbookSwift}" \
"${SCRIPT_DIR}/swift/build_site.sh"

echo "==> Building Objective-C cookbook"
BUILD_ROOT="${BUILD_ROOT}/objc" \
SITE_ROOT="${SITE_ROOT}" \
BINARY_SITE_PATH="binaries/OuterframeCookbookObjC" \
BINARY_URL_PATH="${OBJC_BINARY_URL_PATH:-/binaries/OuterframeCookbookObjC}" \
"${SCRIPT_DIR}/objc/build_site.sh"

echo "Site ready at ${SITE_ROOT}"
