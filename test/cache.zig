const std = @import("std");
const assert = std.debug.assert;
const cache = @import("../src/cache.zig");

test "Read test/cache/index" {
    const mapped = @embedFile("./cache/index");
    var buffer align(std.mem.page_size) = [_]u8{0} ** mapped.len;
    std.mem.copy(u8, &buffer, mapped);

    var reader = cache.CacheReader{ .memory = &buffer };
    const header = reader.header();
    assert(std.mem.eql(u8, header.signature[0..], "DIRC"));
    assert(header.version == 2);
    assert(header.entry_count == 2);

    while (reader.next()) |entry| {
        switch (entry.index) {
            0 => {
                assert(std.mem.eql(u8, entry.name, "build.zig"));
            },
            1 => {
                assert(std.mem.eql(u8, entry.name, "src/cache.zig"));
            },
            else => unreachable,
        }
    }
}
