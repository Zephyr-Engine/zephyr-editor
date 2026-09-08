/// Compile-time FNV-1a over a name, used to turn stable string identifiers
/// (panel ids, action ids) into `u64` keys without a runtime registry.
pub fn fnv1a(comptime name: []const u8) u64 {
    comptime var hash: u64 = 14695981039346656037;
    inline for (name) |byte| {
        hash = (hash ^ byte) *% 1099511628211;
    }
    return hash;
}
