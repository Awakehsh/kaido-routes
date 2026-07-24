#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
project_path="${repository_root}/KaidoRoutesApp.xcodeproj"
scheme_name="KaidoRoutesApp"
simulator_name="Kaido Routes Preview"
device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
derived_data_path="${repository_root}/DerivedData/KaidoRoutesApp"
bundle_identifier="app.kaidoroutes.preview"

if [[ ! -d "${project_path}" ]]; then
  echo "ERROR: ${project_path} is missing. Run: xcodegen generate"
  exit 1
fi

runtime_identifier="$(
  xcrun simctl list runtimes available -j |
    plutil -extract runtimes.0.identifier raw -o - -
)"

if [[ -z "${runtime_identifier}" ]]; then
  echo "ERROR: no iOS Simulator runtime is installed."
  echo "Run: xcodebuild -downloadPlatform iOS"
  exit 1
fi

device_identifier="$(
  xcrun simctl list devices available |
    sed -n "s/^[[:space:]]*${simulator_name} (\([0-9A-F-]*\)).*/\1/p" |
    head -n 1
)"

if [[ -z "${device_identifier}" ]]; then
  device_identifier="$(
    xcrun simctl create \
      "${simulator_name}" \
      "${device_type}" \
      "${runtime_identifier}"
  )"
fi

open -a Simulator
xcrun simctl boot "${device_identifier}" 2>/dev/null || true
xcrun simctl bootstatus "${device_identifier}" -b

xcodebuild \
  -project "${project_path}" \
  -scheme "${scheme_name}" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${device_identifier}" \
  -derivedDataPath "${derived_data_path}" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="${derived_data_path}/Build/Products/Debug-iphonesimulator/KaidoRoutes.app"

if [[ ! -d "${app_path}" ]]; then
  echo "ERROR: built app not found at ${app_path}"
  exit 1
fi

xcrun simctl install "${device_identifier}" "${app_path}"
xcrun simctl launch "${device_identifier}" "${bundle_identifier}"

echo "PASS: Kaido Routes is running in simulator ${simulator_name}"
