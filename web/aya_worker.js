/**
 * Web Worker for Aya inference engine.
 * Runs Emscripten module in a separate thread so the UI never freezes.
 *
 * Messages IN (from main thread):
 *   { type: 'init', bytes: ArrayBuffer }
 *   { type: 'generate', prompt: string, maxTokens: number, temperature: number, topK: number }
 *   { type: 'dispose' }
 *
 * Messages OUT (to main thread):
 *   { type: 'initDone', success: bool, error?: string }
 *   { type: 'token', text: string }
 *   { type: 'generateDone' }
 *   { type: 'error', message: string }
 */

// Import the Emscripten module factory
importScripts('aya_engine.js');

let Module = null;
let ctxPtr = 0;

self.onmessage = async function(e) {
  const msg = e.data;

  if (msg.type === 'init') {
    try {
      // Initialize Emscripten module
      if (!Module) {
        Module = await AyaModule();
      }

      // Free previous context if any
      if (ctxPtr !== 0) {
        Module.ccall('aya_free', null, ['number'], [ctxPtr]);
        ctxPtr = 0;
      }

      const bytes = new Uint8Array(msg.bytes);
      const length = bytes.length;

      // Allocate WASM heap and copy model data
      const bufferPtr = Module._malloc(length);
      if (bufferPtr === 0) {
        self.postMessage({ type: 'initDone', success: false, error: 'malloc failed for ' + length + ' bytes' });
        return;
      }

      // Bulk copy into WASM heap via wasmMemory (HEAPU8 is a local var, not on Module)
      const heapView = new Uint8Array(Module.wasmMemory.buffer);
      heapView.set(bytes, bufferPtr);

      // Call aya_init_buffer
      ctxPtr = Module.ccall('aya_init_buffer', 'number', ['number', 'number'], [bufferPtr, length]);

      if (ctxPtr === 0) {
        Module._free(bufferPtr);
        self.postMessage({ type: 'initDone', success: false, error: 'aya_init_buffer returned null' });
        return;
      }

      self.postMessage({ type: 'initDone', success: true });
    } catch (err) {
      self.postMessage({ type: 'initDone', success: false, error: String(err) });
    }
  }

  else if (msg.type === 'generate') {
    try {
      if (ctxPtr === 0) {
        self.postMessage({ type: 'error', message: 'No model loaded' });
        return;
      }

      // Allocate prompt string
      const promptLen = Module.lengthBytesUTF8(msg.prompt);
      const promptPtr = Module._malloc(promptLen + 1);
      Module.stringToUTF8(msg.prompt, promptPtr, promptLen + 1);

      // Call aya_generate (no callback — single-threaded within worker is fine)
      const resultPtr = Module.ccall(
        'aya_generate', 'number',
        ['number', 'number', 'number', 'number', 'number', 'number', 'number'],
        [ctxPtr, promptPtr, msg.maxTokens, msg.temperature, msg.topK, 0, 0]
      );

      Module._free(promptPtr);

      if (resultPtr !== 0) {
        const text = Module.UTF8ToString(resultPtr);
        // Send words as individual tokens for streaming feel
        const words = text.split(' ');
        for (let i = 0; i < words.length; i++) {
          const chunk = i === 0 ? words[i] : ' ' + words[i];
          self.postMessage({ type: 'token', text: chunk });
        }
        Module.ccall('aya_free_string', null, ['number'], [resultPtr]);
      }

      self.postMessage({ type: 'generateDone' });
    } catch (err) {
      self.postMessage({ type: 'error', message: String(err) });
    }
  }

  else if (msg.type === 'dispose') {
    if (ctxPtr !== 0 && Module) {
      Module.ccall('aya_free', null, ['number'], [ctxPtr]);
      ctxPtr = 0;
    }
    Module = null;
  }
};
