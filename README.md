# Outerframe macOS Cookbooks

Example [outerframe](https://github.com/outergroup/outerframe) content for macOS in two implementations:

- `swift/` contains the Swift cookbook sources for `cookbook-macos-swift.outer`
- `objc/` contains the Objective-C cookbook sources for `cookbook-macos-objc.outer`

Both cookbooks expose the same page list so the Swift and Objective-C vendored libraries can be manually tested against similar content.

The repo has one Xcode project, `OuterframeCookbook.xcodeproj`, with two bundle targets:

- `OuterframeCookbookSwift`
- `OuterframeCookbookObjC`

The shared `OuterframeCookbooks` scheme builds both targets.

## Build Both

From this directory:

```bash
./build_site.sh
```

That produces a ready-to-upload static site in `build/site/`:

- `cookbook-macos-swift.outer`
- `cookbook-macos-objc.outer`
- `binaries/OuterframeCookbookSwift/`
- `binaries/OuterframeCookbookObjC/`

By default, generated `.outer` files point at `/binaries/...`, so the uploaded site is intended to live at a web server root. Override the binary URLs when hosting under a subpath:

```bash
SWIFT_BINARY_URL_PATH=/demo/binaries/OuterframeCookbookSwift \
OBJC_BINARY_URL_PATH=/demo/binaries/OuterframeCookbookObjC \
./build_site.sh
```

Each language folder also has its own `build_site.sh` for building only that cookbook through the shared Xcode project.

## Local Testing

Build the site, then serve it locally:

```bash
python3 Scripts/serve_site.py --root build/site --port 8025
```

Then open either URL in Outer Loop:

```text
http://127.0.0.1:8025/cookbook-macos-swift.outer
http://127.0.0.1:8025/cookbook-macos-objc.outer
```

## Deploying to a Static Server

Upload the contents of `build/site/` to your server.

The server needs to satisfy these rules:

- `cookbook-macos-swift.outer` and `cookbook-macos-objc.outer` should be served as `application/vnd.outerframe`
- `binaries/OuterframeCookbookSwift/macos-arm`, `binaries/OuterframeCookbookSwift/macos-x86`, `binaries/OuterframeCookbookObjC/macos-arm`, and `binaries/OuterframeCookbookObjC/macos-x86` should be served as raw binary data

`build_site.sh` also writes `index.html` files under each binary directory with a plain-text list of supported platforms. Current Outer Loop builds directly request the current platform archive, but the listings are harmless to upload.

### AWS S3

Put the correct `Content-Type` metadata on the S3 objects.

If the site is hosted at the bucket root:

```bash
BUCKET=your-bucket-name

for cookbook in cookbook-macos-swift cookbook-macos-objc; do
  aws s3 cp "build/site/${cookbook}.outer" "s3://${BUCKET}/${cookbook}.outer" \
    --content-type "application/vnd.outerframe"
done

for app in OuterframeCookbookSwift OuterframeCookbookObjC; do
  aws s3 cp "build/site/binaries/${app}/index.html" "s3://${BUCKET}/binaries/${app}/index.html" \
    --content-type "text/plain; charset=utf-8"

  for platform in macos-arm macos-x86; do
    aws s3 cp "build/site/binaries/${app}/${platform}" "s3://${BUCKET}/binaries/${app}/${platform}" \
      --content-type "application/octet-stream"
  done
done
```

If the site is hosted under an S3 path prefix, rebuild with matching binary paths and upload to the same prefix:

```bash
PREFIX=demo

SWIFT_BINARY_URL_PATH="/${PREFIX}/binaries/OuterframeCookbookSwift" \
OBJC_BINARY_URL_PATH="/${PREFIX}/binaries/OuterframeCookbookObjC" \
./build_site.sh

for cookbook in cookbook-macos-swift cookbook-macos-objc; do
  aws s3 cp "build/site/${cookbook}.outer" "s3://${BUCKET}/${PREFIX}/${cookbook}.outer" \
    --content-type "application/vnd.outerframe"
done

for app in OuterframeCookbookSwift OuterframeCookbookObjC; do
  aws s3 cp "build/site/binaries/${app}/index.html" "s3://${BUCKET}/${PREFIX}/binaries/${app}/index.html" \
    --content-type "text/plain; charset=utf-8"

  for platform in macos-arm macos-x86; do
    aws s3 cp "build/site/binaries/${app}/${platform}" "s3://${BUCKET}/${PREFIX}/binaries/${app}/${platform}" \
      --content-type "application/octet-stream"
  done
done
```

Check the deployed metadata:

```bash
curl -I https://your-domain.example/cookbook-macos-swift.outer
curl -I https://your-domain.example/cookbook-macos-objc.outer
curl -I https://your-domain.example/binaries/OuterframeCookbookSwift/macos-arm
curl -I https://your-domain.example/binaries/OuterframeCookbookObjC/macos-arm
```

The `.outer` responses must include `Content-Type: application/vnd.outerframe`. The platform archive responses should be `application/octet-stream`.

After upload, navigate Outer Loop to the deployed `.outer` URLs.

## Vendored Objective-C Library

The Objective-C cookbook vendors the same `Vendor/OuterframeC` and `Vendor/Common` files as `~/dev/src/hello-outerframe-macOS-objc`. When those vendored files need changes, update both copies together so the cookbook remains a realistic manual test target for the Objective-C library.
