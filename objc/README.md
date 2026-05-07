# Outerframe Cookbook Objective-C

Objective-C implementation of the macOS outerframe cookbook.

It intentionally uses the C-native `Vendor/OuterframeC` host wrapper so this project can serve as a manual test target for the Objective-C vendored library.

## Build

From this directory:

```bash
./build_site.sh
```

That produces a ready-to-upload static site in `build/site/`:

- `cookbook-macos-objc.outer`
- `binaries/OuterframeCookbookObjC/index.html`
- `binaries/OuterframeCookbookObjC/macos-arm`
- `binaries/OuterframeCookbookObjC/macos-x86`

By default, the generated `.outer` file points at `/binaries/OuterframeCookbookObjC`. If you host it under a subpath, set `BINARY_URL_PATH` when building:

```bash
BINARY_URL_PATH=/demo/binaries/OuterframeCookbookObjC ./build_site.sh
```

## Local Testing

Build the site, then serve it locally:

```bash
python3 ../Scripts/serve_site.py --root build/site --port 8025
```

Then open this URL in Outer Loop:

```text
http://127.0.0.1:8025/cookbook-macos-objc.outer
```
