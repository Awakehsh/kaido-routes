# App release

Ship one `main` commit as version `X.Y.Z` to TestFlight. `MARKETING_VERSION` in
`project.yml` must already read `X.Y.Z` on that commit.

## 1. Qualify the release commit

```sh
git fetch origin
RELEASE_SHA=$(git rev-parse origin/main)
gh workflow run ios-qualification.yml --ref main
gh run list --workflow verify.yml --commit "$RELEASE_SHA"
gh run list --workflow ios-qualification.yml --commit "$RELEASE_SHA"
```

Both lists must show a `completed success` run for `$RELEASE_SHA`.

## 2. Tag

```sh
git tag -a vX.Y.Z "$RELEASE_SHA" -m "Kaido Routes X.Y.Z"
git push origin vX.Y.Z
```

## 3. Archive

Run from the checkout that holds `Signing.local.xcconfig`. The build number is
the tag's commit count, so every later release archives with a higher one.

```sh
git worktree add --detach build/release vX.Y.Z
cp Apps/KaidoRoutesApp/Config/Signing.local.xcconfig \
  build/release/Apps/KaidoRoutesApp/Config/
xcodebuild archive \
  -project build/release/KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/KaidoRoutes-X.Y.Z.xcarchive \
  -allowProvisioningUpdates \
  KAIDO_BUILD_NUMBER=$(git rev-list --count vX.Y.Z)
```

## 4. Validate the bundle

```sh
python3 build/release/scripts/validate_ios_release_bundle.py \
  build/KaidoRoutes-X.Y.Z.xcarchive
```

It must report `X.Y.Z (<build number>)`.

## 5. Export and upload

The archive is development-signed; export re-signs it for App Store
distribution and uploads it to App Store Connect with the Apple ID signed in to
Xcode.

```sh
xcodebuild -exportArchive \
  -archivePath build/KaidoRoutes-X.Y.Z.xcarchive \
  -exportOptionsPlist \
  build/release/Apps/KaidoRoutesApp/Config/ExportOptions.plist \
  -exportPath build/export-X.Y.Z \
  -allowProvisioningUpdates
git worktree remove build/release
```

## 6. TestFlight smoke

On the owner's iPhone, install `X.Y.Z (<build number>)` from TestFlight over
the existing `app.kaidoroutes`, then open the information sheet and confirm
the version and build.
