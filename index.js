loadWasm(fetch("/zig-out/bin/wasm_trampoline.wasm"))
  .then((instance) => {
    const result = callZigWasm(instance, "do_something", {});
    document.getElementById("wasm-target").innerHTML = JSON.stringify(result);
  });
