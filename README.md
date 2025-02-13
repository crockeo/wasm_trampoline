# wasm-trampoline

I wanted to use Zig compiled to WASM in another that I've been working on,
but I couldn't find very good examples of how to do Javascript <> Zig interop.
This repo aims to be a reasonably good example using Zig `0.13.0`.

## Usage

```shell
# To produce the wasm binary at zig-out/bin/wasm_trampoline.wasm
zig build

# Host any kind of static file HTTP server,
# serving from the root of the repo.
# I like to use Python :)
python3.13 -m http.server
```

## License

[MIT Open Source](./LICENSE)
