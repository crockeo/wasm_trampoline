function loadWasm(res) {
  let instanceRef = null;
  
  return new Promise((resolve) => {
    WebAssembly.compileStreaming(res)
      .then((module) => {
        function nativeConsoleLog(stringPtr, width) {
          const contents = new Uint8Array(instanceRef.exports.memory.buffer, stringPtr, width);
          console.log(new TextDecoder().decode(contents));
        }
        return WebAssembly.instantiate(module, { env: { native_console_log: nativeConsoleLog } })
      })
      .then((instance) => {
        instanceRef = instance;
        resolve(instance)
      });
  });
}

function callZigWasm(instance, func, object) {
    const encodedString = new TextEncoder().encode(JSON.stringify(object));
    const stringAddress = instance.exports.allocate(encodedString.byteLength);
    try {
      const dest = new Uint8Array(instance.exports.memory.buffer, stringAddress, encodedString.byteLength);
      dest.set(encodedString);
      
      const result_addr = instance.exports[func](stringAddress, encodedString.byteLength);

      const result_len = (new Uint8Array(instance.exports.memory.buffer, result_addr)).indexOf(0);
      const result_arr = new Uint8Array(instance.exports.memory.buffer, result_addr, result_len);
      const result = (new TextDecoder()).decode(result_arr);
      return JSON.parse(result);
    } finally {
      instance.exports.free(stringAddress, encodedString.byteLength);
    }
}
