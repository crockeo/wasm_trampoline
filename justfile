serve:
    python3.13 -m http.server

build-forever:
    watchexec -w . -e zig -- zig build
