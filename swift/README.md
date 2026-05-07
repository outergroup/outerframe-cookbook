# Outerframe Cookbook Swift

Swift implementation of the macOS outerframe cookbook.

## Build

From this directory:

```bash
./build_site.sh
```

That produces a ready-to-upload static site in `build/site/`:

- `cookbook-macos-swift.outer`
- `binaries/OuterframeCookbookSwift/index.html`
- `binaries/OuterframeCookbookSwift/macos-arm`
- `binaries/OuterframeCookbookSwift/macos-x86`

By default, the generated `.outer` file points at `/binaries/OuterframeCookbookSwift`. If you host it under a subpath, set `BINARY_URL_PATH` when building:

```bash
BINARY_URL_PATH=/demo/binaries/OuterframeCookbookSwift ./build_site.sh
```

## Local Testing

Build the site, then serve it locally:

```bash
python3 ../Scripts/serve_site.py --root build/site --port 8025
```

Then open this URL in Outer Loop:

```text
http://127.0.0.1:8025/cookbook-macos-swift.outer
```
