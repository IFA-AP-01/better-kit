import Foundation

/// Swift wrapper over the uvie-rs C API. Not thread-safe: use it from one thread only.
final class UvieEngine {
    private let handle: OpaquePointer
    private var buffer = [CChar](repeating: 0, count: 512)

    init() {
        handle = uvie_engine_new()
    }

    deinit {
        uvie_engine_free(handle)
    }

    func configure(method: InputMethod, modern: Bool, englishOverride: Bool, quickTelex: Bool) {
        uvie_engine_set_input_method(handle, Int32(method.rawValue))
        uvie_engine_set_modern_orthography(handle, modern ? 1 : 0)
        uvie_engine_set_english_override(handle, englishOverride ? 1 : 0)
        uvie_engine_set_quick_telex(handle, quickTelex ? 1 : 0)
        reset()
    }

    var isComposing: Bool { uvie_engine_is_composing(handle) != 0 }

    func feed(_ ch: CChar) -> (Int, String) {
        diff { uvie_engine_feed(handle, ch, $0, $1) }
    }

    func backspace() -> (Int, String) {
        diff { uvie_engine_backspace(handle, $0, $1) }
    }

    func commit() -> (Int, String) {
        diff { uvie_engine_commit(handle, $0, $1) }
    }

    func reset() {
        uvie_engine_reset(handle)
    }

    var currentOutput: String {
        string { uvie_engine_current_output(handle, $0, $1) }
    }

    var rawChars: String {
        string { uvie_engine_raw_chars(handle, $0, $1) }
    }

    private func diff(_ call: (UnsafeMutablePointer<CChar>, Int) -> Int) -> (Int, String) {
        let count = buffer.count
        return buffer.withUnsafeMutableBufferPointer { buf -> (Int, String) in
            buf[0] = 0
            let bs = call(buf.baseAddress!, count)
            return (bs, String(cString: buf.baseAddress!))
        }
    }

    private func string(_ call: (UnsafeMutablePointer<CChar>, Int) -> Int) -> String {
        let count = buffer.count
        return buffer.withUnsafeMutableBufferPointer { buf -> String in
            buf[0] = 0
            _ = call(buf.baseAddress!, count)
            return String(cString: buf.baseAddress!)
        }
    }
}
