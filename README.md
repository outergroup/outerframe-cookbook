# OuterframeCookbook

This is a static-hosted outerframe cookbook app. The default page is a table of contents that switches between the included layer-backed examples.

It includes:

- A small standalone Xcode project that builds `OuterframeCookbook.bundle`
- Vendored outerframe host/runtime Swift files copied from `Top`
- A Python script that generates the `.outer` descriptor
- A Python script that serves the generated site locally with the right MIME type for `.outer`

## Build

From this directory:

```bash
./build_site.sh
```

That produces a ready-to-upload static site in `build/site/`:

- `cookbook.outer`
- `binaries/OuterframeCookbook/index.html`
- `binaries/OuterframeCookbook/macos-arm`
- `binaries/OuterframeCookbook/macos-x86`

If you want the raw build command, `build_site.sh` runs `xcodebuild` against `OuterframeCookbook.xcodeproj` and then archives the built bundle with `aa`.

By default, the generated `.outer` file points at `/binaries/OuterframeCookbook`, so the uploaded site is intended to live at the web server root. If you want to host it under a subpath, set `BINARY_URL_PATH` when building, for example:

```bash
BINARY_URL_PATH=/demo/binaries/OuterframeCookbook ./build_site.sh
```

## Local testing

Build the site, then serve it locally:

```bash
python3 Scripts/serve_site.py --root build/site --port 8026
```

Then open this URL in Outer Loop:

```text
http://127.0.0.1:8025/cookbook.outer
```

Specific entries can also be loaded by fragment:

```text
http://127.0.0.1:8025/cookbook.outer#manual_scroll
http://127.0.0.1:8025/cookbook.outer#nested_scroll
http://127.0.0.1:8025/cookbook.outer#timeline_range
http://127.0.0.1:8025/cookbook.outer#giant_page
http://127.0.0.1:8025/cookbook.outer#n_cube
```

## Deploying to a static server

Upload the contents of `build/site/` to your server.

The server needs to satisfy these rules:

- `cookbook.outer` should be served as `application/vnd.outerframe`
- `binaries/OuterframeCookbook/` should return a body containing `macos-arm` and `macos-x86`
- `binaries/OuterframeCookbook/macos-arm` and `binaries/OuterframeCookbook/macos-x86` should be served as raw binary data

After upload, navigate Outer Loop to the deployed `.outer` URL.
