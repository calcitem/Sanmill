// SPDX-License-Identifier: AGPL-3.0-or-later

declare module "*.wasm" {
  const module: WebAssembly.Module;
  export default module;
}
