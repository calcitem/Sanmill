let wasm_bindgen = (function(exports) {
    let script_src;
    if (typeof document !== 'undefined' && document.currentScript !== null) {
        script_src = new URL(document.currentScript.src, location.href).toString();
    }

    class WorkerPool {
        static __wrap(ptr) {
            ptr = ptr >>> 0;
            const obj = Object.create(WorkerPool.prototype);
            obj.__wbg_ptr = ptr;
            WorkerPoolFinalization.register(obj, obj.__wbg_ptr, obj);
            return obj;
        }
        __destroy_into_raw() {
            const ptr = this.__wbg_ptr;
            this.__wbg_ptr = 0;
            WorkerPoolFinalization.unregister(this);
            return ptr;
        }
        free() {
            const ptr = this.__destroy_into_raw();
            wasm.__wbg_workerpool_free(ptr, 0);
        }
        /**
         * @param {number | null} [initial]
         * @param {string | null} [script_src]
         * @param {string | null} [worker_js_preamble]
         * @param {string | null} [wasm_bindgen_name]
         * @returns {WorkerPool}
         */
        static new(initial, script_src, worker_js_preamble, wasm_bindgen_name) {
            try {
                const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
                var ptr0 = isLikeNone(script_src) ? 0 : passStringToWasm0(script_src, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                var len0 = WASM_VECTOR_LEN;
                var ptr1 = isLikeNone(worker_js_preamble) ? 0 : passStringToWasm0(worker_js_preamble, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                var len1 = WASM_VECTOR_LEN;
                var ptr2 = isLikeNone(wasm_bindgen_name) ? 0 : passStringToWasm0(wasm_bindgen_name, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                var len2 = WASM_VECTOR_LEN;
                wasm.workerpool_new(retptr, isLikeNone(initial) ? 0x100000001 : (initial) >>> 0, ptr0, len0, ptr1, len1, ptr2, len2);
                var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
                var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
                var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
                if (r2) {
                    throw takeObject(r1);
                }
                return WorkerPool.__wrap(r0);
            } finally {
                wasm.__wbindgen_add_to_stack_pointer(16);
            }
        }
        /**
         * Creates a new `WorkerPool` which immediately creates `initial` workers.
         *
         * The pool created here can be used over a long period of time, and it
         * will be initially primed with `initial` workers. Currently workers are
         * never released or gc'd until the whole pool is destroyed.
         *
         * # Errors
         *
         * Returns any error that may happen while a JS web worker is created and a
         * message is sent to it.
         * @param {number} initial
         * @param {string} script_src
         * @param {string} worker_js_preamble
         * @param {string} wasm_bindgen_name
         */
        constructor(initial, script_src, worker_js_preamble, wasm_bindgen_name) {
            try {
                const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
                const ptr0 = passStringToWasm0(script_src, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len0 = WASM_VECTOR_LEN;
                const ptr1 = passStringToWasm0(worker_js_preamble, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len1 = WASM_VECTOR_LEN;
                const ptr2 = passStringToWasm0(wasm_bindgen_name, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len2 = WASM_VECTOR_LEN;
                wasm.workerpool_new_raw(retptr, initial, ptr0, len0, ptr1, len1, ptr2, len2);
                var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
                var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
                var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
                if (r2) {
                    throw takeObject(r1);
                }
                this.__wbg_ptr = r0 >>> 0;
                WorkerPoolFinalization.register(this, this.__wbg_ptr, this);
                return this;
            } finally {
                wasm.__wbindgen_add_to_stack_pointer(16);
            }
        }
    }
    if (Symbol.dispose) WorkerPool.prototype[Symbol.dispose] = WorkerPool.prototype.free;
    exports.WorkerPool = WorkerPool;

    /**
     * @param {number} call_id
     * @param {any} ptr_
     * @param {number} rust_vec_len_
     * @param {number} data_len_
     */
    function frb_dart_fn_deliver_output(call_id, ptr_, rust_vec_len_, data_len_) {
        wasm.frb_dart_fn_deliver_output(call_id, addHeapObject(ptr_), rust_vec_len_, data_len_);
    }
    exports.frb_dart_fn_deliver_output = frb_dart_fn_deliver_output;

    /**
     * # Safety
     *
     * This should never be called manually.
     * @param {any} handle
     * @param {any} dart_handler_port
     * @returns {number}
     */
    function frb_dart_opaque_dart2rust_encode(handle, dart_handler_port) {
        const ret = wasm.frb_dart_opaque_dart2rust_encode(addHeapObject(handle), addHeapObject(dart_handler_port));
        return ret >>> 0;
    }
    exports.frb_dart_opaque_dart2rust_encode = frb_dart_opaque_dart2rust_encode;

    /**
     * @param {number} ptr
     */
    function frb_dart_opaque_drop_thread_box_persistent_handle(ptr) {
        wasm.frb_dart_opaque_drop_thread_box_persistent_handle(ptr);
    }
    exports.frb_dart_opaque_drop_thread_box_persistent_handle = frb_dart_opaque_drop_thread_box_persistent_handle;

    /**
     * @param {number} ptr
     * @returns {any}
     */
    function frb_dart_opaque_rust2dart_decode(ptr) {
        const ret = wasm.frb_dart_opaque_rust2dart_decode(ptr);
        return takeObject(ret);
    }
    exports.frb_dart_opaque_rust2dart_decode = frb_dart_opaque_rust2dart_decode;

    /**
     * @returns {number}
     */
    function frb_get_rust_content_hash() {
        const ret = wasm.frb_get_rust_content_hash();
        return ret;
    }
    exports.frb_get_rust_content_hash = frb_get_rust_content_hash;

    /**
     * @param {number} func_id
     * @param {any} port_
     * @param {any} ptr_
     * @param {number} rust_vec_len_
     * @param {number} data_len_
     */
    function frb_pde_ffi_dispatcher_primary(func_id, port_, ptr_, rust_vec_len_, data_len_) {
        wasm.frb_pde_ffi_dispatcher_primary(func_id, addHeapObject(port_), addHeapObject(ptr_), rust_vec_len_, data_len_);
    }
    exports.frb_pde_ffi_dispatcher_primary = frb_pde_ffi_dispatcher_primary;

    /**
     * @param {number} func_id
     * @param {any} ptr_
     * @param {number} rust_vec_len_
     * @param {number} data_len_
     * @returns {any}
     */
    function frb_pde_ffi_dispatcher_sync(func_id, ptr_, rust_vec_len_, data_len_) {
        const ret = wasm.frb_pde_ffi_dispatcher_sync(func_id, addHeapObject(ptr_), rust_vec_len_, data_len_);
        return takeObject(ret);
    }
    exports.frb_pde_ffi_dispatcher_sync = frb_pde_ffi_dispatcher_sync;

    /**
     * ## Safety
     * This function reclaims a raw pointer created by [`TransferClosure`], and therefore
     * should **only** be used in conjunction with it.
     * Furthermore, the WASM module in the worker must have been initialized with the shared
     * memory from the host JS scope.
     * @param {number} payload
     * @param {any[]} transfer
     */
    function receive_transfer_closure(payload, transfer) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passArrayJsValueToWasm0(transfer, wasm.__wbindgen_export);
            const len0 = WASM_VECTOR_LEN;
            wasm.receive_transfer_closure(retptr, payload, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            if (r1) {
                throw takeObject(r0);
            }
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    exports.receive_transfer_closure = receive_transfer_closure;

    function wasm_start_callback() {
        wasm.wasm_start_callback();
    }
    exports.wasm_start_callback = wasm_start_callback;
    function __wbg_get_imports() {
        const import0 = {
            __proto__: null,
            __wbg___wbindgen_debug_string_ab4b34d23d6778bd: function(arg0, arg1) {
                const ret = debugString(getObject(arg1));
                const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len1 = WASM_VECTOR_LEN;
                getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
            },
            __wbg___wbindgen_is_falsy_c07bb72123e65555: function(arg0) {
                const ret = !getObject(arg0);
                return ret;
            },
            __wbg___wbindgen_is_undefined_29a43b4d42920abd: function(arg0) {
                const ret = getObject(arg0) === undefined;
                return ret;
            },
            __wbg___wbindgen_jsval_eq_d3465d8a07697228: function(arg0, arg1) {
                const ret = getObject(arg0) === getObject(arg1);
                return ret;
            },
            __wbg___wbindgen_memory_dfa12096f400c9bd: function() {
                const ret = wasm.memory;
                return addHeapObject(ret);
            },
            __wbg___wbindgen_module_b5e6fb95dbdb7d7e: function() {
                const ret = wasmModule;
                return addHeapObject(ret);
            },
            __wbg___wbindgen_number_get_c7f42aed0525c451: function(arg0, arg1) {
                const obj = getObject(arg1);
                const ret = typeof(obj) === 'number' ? obj : undefined;
                getDataViewMemory0().setFloat64(arg0 + 8 * 1, isLikeNone(ret) ? 0 : ret, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
            },
            __wbg___wbindgen_string_get_7ed5322991caaec5: function(arg0, arg1) {
                const obj = getObject(arg1);
                const ret = typeof(obj) === 'string' ? obj : undefined;
                var ptr1 = isLikeNone(ret) ? 0 : passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                var len1 = WASM_VECTOR_LEN;
                getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
            },
            __wbg___wbindgen_throw_6b64449b9b9ed33c: function(arg0, arg1) {
                throw new Error(getStringFromWasm0(arg0, arg1));
            },
            __wbg__wbg_cb_unref_b46c9b5a9f08ec37: function(arg0) {
                getObject(arg0)._wbg_cb_unref();
            },
            __wbg_createObjectURL_46e1b0c55389893b: function() { return handleError(function (arg0, arg1) {
                const ret = URL.createObjectURL(getObject(arg1));
                const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len1 = WASM_VECTOR_LEN;
                getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
            }, arguments); },
            __wbg_data_bb9dffdd1e99cf2d: function(arg0) {
                const ret = getObject(arg0).data;
                return addHeapObject(ret);
            },
            __wbg_error_7bfe3b7ebaaa5936: function(arg0, arg1) {
                console.error(getStringFromWasm0(arg0, arg1));
            },
            __wbg_error_a6fa202b58aa1cd3: function(arg0, arg1) {
                let deferred0_0;
                let deferred0_1;
                try {
                    deferred0_0 = arg0;
                    deferred0_1 = arg1;
                    console.error(getStringFromWasm0(arg0, arg1));
                } finally {
                    wasm.__wbindgen_export4(deferred0_0, deferred0_1, 1);
                }
            },
            __wbg_eval_0f5002e126d86aff: function() { return handleError(function (arg0, arg1) {
                const ret = eval(getStringFromWasm0(arg0, arg1));
                return addHeapObject(ret);
            }, arguments); },
            __wbg_get_6011fa3a58f61074: function() { return handleError(function (arg0, arg1) {
                const ret = Reflect.get(getObject(arg0), getObject(arg1));
                return addHeapObject(ret);
            }, arguments); },
            __wbg_instanceof_BroadcastChannel_5df9429897d85c56: function(arg0) {
                let result;
                try {
                    result = getObject(arg0) instanceof BroadcastChannel;
                } catch (_) {
                    result = false;
                }
                const ret = result;
                return ret;
            },
            __wbg_instanceof_ErrorEvent_2875f0fa957e8d48: function(arg0) {
                let result;
                try {
                    result = getObject(arg0) instanceof ErrorEvent;
                } catch (_) {
                    result = false;
                }
                const ret = result;
                return ret;
            },
            __wbg_instanceof_MessageEvent_551f81fec2cc0225: function(arg0) {
                let result;
                try {
                    result = getObject(arg0) instanceof MessageEvent;
                } catch (_) {
                    result = false;
                }
                const ret = result;
                return ret;
            },
            __wbg_instanceof_MessagePort_01f71fc6be292c9d: function(arg0) {
                let result;
                try {
                    result = getObject(arg0) instanceof MessagePort;
                } catch (_) {
                    result = false;
                }
                const ret = result;
                return ret;
            },
            __wbg_length_9f1775224cf1d815: function(arg0) {
                const ret = getObject(arg0).length;
                return ret;
            },
            __wbg_log_cec7fe8f094ff8b7: function(arg0, arg1) {
                console.log(getStringFromWasm0(arg0, arg1));
            },
            __wbg_message_aa7e2704b8b86e2a: function(arg0, arg1) {
                const ret = getObject(arg1).message;
                const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len1 = WASM_VECTOR_LEN;
                getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
            },
            __wbg_name_4fa65b35fc398da1: function(arg0, arg1) {
                const ret = getObject(arg1).name;
                const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len1 = WASM_VECTOR_LEN;
                getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
            },
            __wbg_new_0c7403db6e782f19: function(arg0) {
                const ret = new Uint8Array(getObject(arg0));
                return addHeapObject(ret);
            },
            __wbg_new_227d7c05414eb861: function() {
                const ret = new Error();
                return addHeapObject(ret);
            },
            __wbg_new_682678e2f47e32bc: function() {
                const ret = new Array();
                return addHeapObject(ret);
            },
            __wbg_new_aa8d0fa9762c29bd: function() {
                const ret = new Object();
                return addHeapObject(ret);
            },
            __wbg_new_aadb2b3f13e701cf: function() { return handleError(function (arg0, arg1) {
                const ret = new BroadcastChannel(getStringFromWasm0(arg0, arg1));
                return addHeapObject(ret);
            }, arguments); },
            __wbg_new_d9e8ade8a7fba252: function() { return handleError(function (arg0, arg1) {
                const ret = new Worker(getStringFromWasm0(arg0, arg1));
                return addHeapObject(ret);
            }, arguments); },
            __wbg_new_from_slice_b5ea43e23f6008c0: function(arg0, arg1) {
                const ret = new Uint8Array(getArrayU8FromWasm0(arg0, arg1));
                return addHeapObject(ret);
            },
            __wbg_new_with_blob_sequence_and_options_c1581ddb17deb8ba: function() { return handleError(function (arg0, arg1) {
                const ret = new Blob(getObject(arg0), getObject(arg1));
                return addHeapObject(ret);
            }, arguments); },
            __wbg_postMessage_05c4f5b252fddf64: function() { return handleError(function (arg0, arg1) {
                getObject(arg0).postMessage(getObject(arg1));
            }, arguments); },
            __wbg_postMessage_2e8ce5e10ce05091: function() { return handleError(function (arg0, arg1, arg2) {
                getObject(arg0).postMessage(getObject(arg1), getObject(arg2));
            }, arguments); },
            __wbg_postMessage_59736484efc322cf: function() { return handleError(function (arg0, arg1) {
                getObject(arg0).postMessage(getObject(arg1));
            }, arguments); },
            __wbg_postMessage_fd3e922532e00928: function() { return handleError(function (arg0, arg1) {
                getObject(arg0).postMessage(getObject(arg1));
            }, arguments); },
            __wbg_prototypesetcall_a6b02eb00b0f4ce2: function(arg0, arg1, arg2) {
                Uint8Array.prototype.set.call(getArrayU8FromWasm0(arg0, arg1), getObject(arg2));
            },
            __wbg_push_471a5b068a5295f6: function(arg0, arg1) {
                const ret = getObject(arg0).push(getObject(arg1));
                return ret;
            },
            __wbg_set_022bee52d0b05b19: function() { return handleError(function (arg0, arg1, arg2) {
                const ret = Reflect.set(getObject(arg0), getObject(arg1), getObject(arg2));
                return ret;
            }, arguments); },
            __wbg_set_onerror_b785ebcd32c1528e: function(arg0, arg1) {
                getObject(arg0).onerror = getObject(arg1);
            },
            __wbg_set_onmessage_9d59339e7810516a: function(arg0, arg1) {
                getObject(arg0).onmessage = getObject(arg1);
            },
            __wbg_set_type_8b2743f6b4de4035: function(arg0, arg1, arg2) {
                getObject(arg0).type = getStringFromWasm0(arg1, arg2);
            },
            __wbg_stack_3b0d974bbf31e44f: function(arg0, arg1) {
                const ret = getObject(arg1).stack;
                const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
                const len1 = WASM_VECTOR_LEN;
                getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
                getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
            },
            __wbg_static_accessor_GLOBAL_8cfadc87a297ca02: function() {
                const ret = typeof global === 'undefined' ? null : global;
                return isLikeNone(ret) ? 0 : addHeapObject(ret);
            },
            __wbg_static_accessor_GLOBAL_THIS_602256ae5c8f42cf: function() {
                const ret = typeof globalThis === 'undefined' ? null : globalThis;
                return isLikeNone(ret) ? 0 : addHeapObject(ret);
            },
            __wbg_static_accessor_SELF_e445c1c7484aecc3: function() {
                const ret = typeof self === 'undefined' ? null : self;
                return isLikeNone(ret) ? 0 : addHeapObject(ret);
            },
            __wbg_static_accessor_WINDOW_f20e8576ef1e0f17: function() {
                const ret = typeof window === 'undefined' ? null : window;
                return isLikeNone(ret) ? 0 : addHeapObject(ret);
            },
            __wbg_unshift_951ea71d9d2dc660: function(arg0, arg1) {
                const ret = getObject(arg0).unshift(getObject(arg1));
                return ret;
            },
            __wbindgen_cast_0000000000000001: function(arg0, arg1) {
                // Cast intrinsic for `Closure(Closure { owned: true, function: Function { arguments: [NamedExternref("Event")], shim_idx: 108, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
                const ret = makeMutClosure(arg0, arg1, __wasm_bindgen_func_elem_598);
                return addHeapObject(ret);
            },
            __wbindgen_cast_0000000000000002: function(arg0, arg1) {
                // Cast intrinsic for `Closure(Closure { owned: true, function: Function { arguments: [NamedExternref("MessageEvent")], shim_idx: 108, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
                const ret = makeMutClosure(arg0, arg1, __wasm_bindgen_func_elem_598_1);
                return addHeapObject(ret);
            },
            __wbindgen_cast_0000000000000003: function(arg0) {
                // Cast intrinsic for `F64 -> Externref`.
                const ret = arg0;
                return addHeapObject(ret);
            },
            __wbindgen_cast_0000000000000004: function(arg0, arg1) {
                // Cast intrinsic for `Ref(String) -> Externref`.
                const ret = getStringFromWasm0(arg0, arg1);
                return addHeapObject(ret);
            },
            __wbindgen_object_clone_ref: function(arg0) {
                const ret = getObject(arg0);
                return addHeapObject(ret);
            },
            __wbindgen_object_drop_ref: function(arg0) {
                takeObject(arg0);
            },
        };
        return {
            __proto__: null,
            "./rust_lib_sanmill_bg.js": import0,
        };
    }

    function __wasm_bindgen_func_elem_598(arg0, arg1, arg2) {
        wasm.__wasm_bindgen_func_elem_598(arg0, arg1, addHeapObject(arg2));
    }

    function __wasm_bindgen_func_elem_598_1(arg0, arg1, arg2) {
        wasm.__wasm_bindgen_func_elem_598_1(arg0, arg1, addHeapObject(arg2));
    }

    const WorkerPoolFinalization = (typeof FinalizationRegistry === 'undefined')
        ? { register: () => {}, unregister: () => {} }
        : new FinalizationRegistry(ptr => wasm.__wbg_workerpool_free(ptr >>> 0, 1));

    function addHeapObject(obj) {
        if (heap_next === heap.length) heap.push(heap.length + 1);
        const idx = heap_next;
        heap_next = heap[idx];

        heap[idx] = obj;
        return idx;
    }

    const CLOSURE_DTORS = (typeof FinalizationRegistry === 'undefined')
        ? { register: () => {}, unregister: () => {} }
        : new FinalizationRegistry(state => wasm.__wbindgen_export5(state.a, state.b));

    function debugString(val) {
        // primitive types
        const type = typeof val;
        if (type == 'number' || type == 'boolean' || val == null) {
            return  `${val}`;
        }
        if (type == 'string') {
            return `"${val}"`;
        }
        if (type == 'symbol') {
            const description = val.description;
            if (description == null) {
                return 'Symbol';
            } else {
                return `Symbol(${description})`;
            }
        }
        if (type == 'function') {
            const name = val.name;
            if (typeof name == 'string' && name.length > 0) {
                return `Function(${name})`;
            } else {
                return 'Function';
            }
        }
        // objects
        if (Array.isArray(val)) {
            const length = val.length;
            let debug = '[';
            if (length > 0) {
                debug += debugString(val[0]);
            }
            for(let i = 1; i < length; i++) {
                debug += ', ' + debugString(val[i]);
            }
            debug += ']';
            return debug;
        }
        // Test for built-in
        const builtInMatches = /\[object ([^\]]+)\]/.exec(toString.call(val));
        let className;
        if (builtInMatches && builtInMatches.length > 1) {
            className = builtInMatches[1];
        } else {
            // Failed to match the standard '[object ClassName]'
            return toString.call(val);
        }
        if (className == 'Object') {
            // we're a user defined class or Object
            // JSON.stringify avoids problems with cycles, and is generally much
            // easier than looping through ownProperties of `val`.
            try {
                return 'Object(' + JSON.stringify(val) + ')';
            } catch (_) {
                return 'Object';
            }
        }
        // errors
        if (val instanceof Error) {
            return `${val.name}: ${val.message}\n${val.stack}`;
        }
        // TODO we could test for more things here, like `Set`s and `Map`s.
        return className;
    }

    function dropObject(idx) {
        if (idx < 1028) return;
        heap[idx] = heap_next;
        heap_next = idx;
    }

    function getArrayU8FromWasm0(ptr, len) {
        ptr = ptr >>> 0;
        return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
    }

    let cachedDataViewMemory0 = null;
    function getDataViewMemory0() {
        if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || (cachedDataViewMemory0.buffer.detached === undefined && cachedDataViewMemory0.buffer !== wasm.memory.buffer)) {
            cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
        }
        return cachedDataViewMemory0;
    }

    function getStringFromWasm0(ptr, len) {
        ptr = ptr >>> 0;
        return decodeText(ptr, len);
    }

    let cachedUint8ArrayMemory0 = null;
    function getUint8ArrayMemory0() {
        if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
            cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
        }
        return cachedUint8ArrayMemory0;
    }

    function getObject(idx) { return heap[idx]; }

    function handleError(f, args) {
        try {
            return f.apply(this, args);
        } catch (e) {
            wasm.__wbindgen_export3(addHeapObject(e));
        }
    }

    let heap = new Array(1024).fill(undefined);
    heap.push(undefined, null, true, false);

    let heap_next = heap.length;

    function isLikeNone(x) {
        return x === undefined || x === null;
    }

    function makeMutClosure(arg0, arg1, f) {
        const state = { a: arg0, b: arg1, cnt: 1 };
        const real = (...args) => {

            // First up with a closure we increment the internal reference
            // count. This ensures that the Rust closure environment won't
            // be deallocated while we're invoking it.
            state.cnt++;
            const a = state.a;
            state.a = 0;
            try {
                return f(a, state.b, ...args);
            } finally {
                state.a = a;
                real._wbg_cb_unref();
            }
        };
        real._wbg_cb_unref = () => {
            if (--state.cnt === 0) {
                wasm.__wbindgen_export5(state.a, state.b);
                state.a = 0;
                CLOSURE_DTORS.unregister(state);
            }
        };
        CLOSURE_DTORS.register(real, state, state);
        return real;
    }

    function passArrayJsValueToWasm0(array, malloc) {
        const ptr = malloc(array.length * 4, 4) >>> 0;
        const mem = getDataViewMemory0();
        for (let i = 0; i < array.length; i++) {
            mem.setUint32(ptr + 4 * i, addHeapObject(array[i]), true);
        }
        WASM_VECTOR_LEN = array.length;
        return ptr;
    }

    function passStringToWasm0(arg, malloc, realloc) {
        if (realloc === undefined) {
            const buf = cachedTextEncoder.encode(arg);
            const ptr = malloc(buf.length, 1) >>> 0;
            getUint8ArrayMemory0().subarray(ptr, ptr + buf.length).set(buf);
            WASM_VECTOR_LEN = buf.length;
            return ptr;
        }

        let len = arg.length;
        let ptr = malloc(len, 1) >>> 0;

        const mem = getUint8ArrayMemory0();

        let offset = 0;

        for (; offset < len; offset++) {
            const code = arg.charCodeAt(offset);
            if (code > 0x7F) break;
            mem[ptr + offset] = code;
        }
        if (offset !== len) {
            if (offset !== 0) {
                arg = arg.slice(offset);
            }
            ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
            const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
            const ret = cachedTextEncoder.encodeInto(arg, view);

            offset += ret.written;
            ptr = realloc(ptr, len, offset, 1) >>> 0;
        }

        WASM_VECTOR_LEN = offset;
        return ptr;
    }

    function takeObject(idx) {
        const ret = getObject(idx);
        dropObject(idx);
        return ret;
    }

    let cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
    cachedTextDecoder.decode();
    function decodeText(ptr, len) {
        return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
    }

    const cachedTextEncoder = new TextEncoder();

    if (!('encodeInto' in cachedTextEncoder)) {
        cachedTextEncoder.encodeInto = function (arg, view) {
            const buf = cachedTextEncoder.encode(arg);
            view.set(buf);
            return {
                read: arg.length,
                written: buf.length
            };
        };
    }

    let WASM_VECTOR_LEN = 0;

    let wasmModule, wasm;
    function __wbg_finalize_init(instance, module) {
        wasm = instance.exports;
        wasmModule = module;
        cachedDataViewMemory0 = null;
        cachedUint8ArrayMemory0 = null;
        wasm.__wbindgen_start();
        return wasm;
    }

    async function __wbg_load(module, imports) {
        if (typeof Response === 'function' && module instanceof Response) {
            if (typeof WebAssembly.instantiateStreaming === 'function') {
                try {
                    return await WebAssembly.instantiateStreaming(module, imports);
                } catch (e) {
                    const validResponse = module.ok && expectedResponseType(module.type);

                    if (validResponse && module.headers.get('Content-Type') !== 'application/wasm') {
                        console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n", e);

                    } else { throw e; }
                }
            }

            const bytes = await module.arrayBuffer();
            return await WebAssembly.instantiate(bytes, imports);
        } else {
            const instance = await WebAssembly.instantiate(module, imports);

            if (instance instanceof WebAssembly.Instance) {
                return { instance, module };
            } else {
                return instance;
            }
        }

        function expectedResponseType(type) {
            switch (type) {
                case 'basic': case 'cors': case 'default': return true;
            }
            return false;
        }
    }

    function initSync(module) {
        if (wasm !== undefined) return wasm;


        if (module !== undefined) {
            if (Object.getPrototypeOf(module) === Object.prototype) {
                ({module} = module)
            } else {
                console.warn('using deprecated parameters for `initSync()`; pass a single object instead')
            }
        }

        const imports = __wbg_get_imports();
        if (!(module instanceof WebAssembly.Module)) {
            module = new WebAssembly.Module(module);
        }
        const instance = new WebAssembly.Instance(module, imports);
        return __wbg_finalize_init(instance, module);
    }

    async function __wbg_init(module_or_path) {
        if (wasm !== undefined) return wasm;


        if (module_or_path !== undefined) {
            if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
                ({module_or_path} = module_or_path)
            } else {
                console.warn('using deprecated parameters for the initialization function; pass a single object instead')
            }
        }

        if (module_or_path === undefined && script_src !== undefined) {
            module_or_path = script_src.replace(/\.js$/, "_bg.wasm");
        }
        const imports = __wbg_get_imports();

        if (typeof module_or_path === 'string' || (typeof Request === 'function' && module_or_path instanceof Request) || (typeof URL === 'function' && module_or_path instanceof URL)) {
            module_or_path = fetch(module_or_path);
        }

        const { instance, module } = await __wbg_load(await module_or_path, imports);

        return __wbg_finalize_init(instance, module);
    }

    return Object.assign(__wbg_init, { initSync }, exports);
})({ __proto__: null });
