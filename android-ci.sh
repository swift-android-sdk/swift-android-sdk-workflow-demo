#!/bin/bash -ex

if [[ -z "${2}" ]]; then
  echo "$0: Usage: $0 build/test org/package"
  exit 1
fi

ACT=${1}
ORG=$(echo "${2}" | cut -d '/' -f 1)
PACKAGE=$(echo "${2}" | cut -d '/' -f 2)

git clone https://github.com/${ORG}/${PACKAGE}
cd ${PACKAGE}

TRIPLE="${ANDROID_EMULATOR_ARCH_TRIPLE}-unknown-linux-android${ANDROID_API}"
swiftly run swift build --swift-sdk "${TRIPLE}" --build-tests +"${SWIFT_TOOLCHAIN_VERSION}"

if [[ "${ACT}" == "build" ]]; then
  # build-only, not test, so we are done
  exit 0
fi

if [[ "${ACT}" != "test" ]]; then
  # build-only, not test
  echo "$0: Usage: $0 build/test org/package"
  exit 1
fi

STAGING="android-test-${PACKAGE}"
rm -rf .build/"${STAGING}"
mkdir .build/"${STAGING}"

# for the common case of tests referencing their own files as hardwired resource paths
cp -a Tests .build/"${STAGING}"

cd .build/
cp -a debug/*.xctest "${STAGING}"
cp -a debug/*.resources "${STAGING}" || true
cp -a ${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/sysroot/usr/lib/${ANDROID_EMULATOR_ARCH_TRIPLE}-linux-android/libc++_shared.so "${STAGING}"
cp -a ${SWIFT_ANDROID_SDK_HOME}/swift-android/swift-resources/usr/lib/swift-${ANDROID_EMULATOR_ARCH_TRIPLE}/android/*.so "${STAGING}"

adb push ${STAGING} /data/local/tmp/

cd -

TEST_CMD="./${PACKAGE}PackageTests.xctest"
TEST_SHELL="cd /data/local/tmp/${STAGING}"
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD}"

# Run a second time with the Swift Testing library
# We additionally need to handle the special exit code EXIT_NO_TESTS_FOUND (69 on Android),
# which can happen when the tests link to Testing, but no tests are executed
# see: https://github.com/swiftlang/swift-package-manager/blob/1b593469e8ad3daf2cc10e798340bd2de68c402d/Sources/Commands/SwiftTestCommand.swift#L1542
TEST_SHELL="${TEST_SHELL} && ${TEST_CMD} --testing-library swift-testing && [ \$? -eq 0 ] || [ \$? -eq 69 ]"

adb shell "${TEST_SHELL}"

