function callZigWasm(module, func, object) {
    const encodedString = TextEncoder().encode(JSON.stringify(object));
    const stringAddress = module.instance.exports.allocate(encodedString.byteLength);
    try {
      const dest = UInt8Array(module.instance.exports.memory.buffer, stringAddress);
      dest.set(encodedString);
      const result = module.instance.exports[func](stringAddress, encodedString.byteLength);
      console.log(result);
    } finally {
      module.instance.exports.free(stringAddress, encodedString.byteLength);
    }
}
