const std = @import("std");

fn fromMem(T: anytype, binary_data: []align(@alignOf(T)) u8) T {
    std.debug.assert(binary_data.len == @sizeOf(T));
    const data = @ptrCast(*T, binary_data);
    var buffer = [_]u8{0} ** @sizeOf(T);
    const return_value = std.mem.bytesAsValue(T, buffer[0..@sizeOf(T)]);
    inline for (@typeInfo(T).Struct.fields) |field| {
        // Convert big endian to machine-native endian
        @field(return_value, field.name) = switch (@typeInfo(field.field_type)) {
            .Struct => fromMem(field.field_type, binary_data[@offsetOf(T, field.name) .. @offsetOf(T, field.name) + @sizeOf(field.field_type)]),
            .Int => std.mem.bigToNative(field.field_type, @field(data, field.name)),
            else => @field(data, field.name),
        };
    }
    return return_value.*;
}

const TimeStamp = extern struct {
    second: u32,
    nanosecond: u32,
};

const Stat = extern struct {
    created: TimeStamp,
    modified: TimeStamp,
    dev: u32,
    inode: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    file_size: u32,
};

const CacheHeader = extern struct {
    signature: [4]u8 = .{ 'D', 'I', 'R', 'C' },
    version: u32 = 2,
    entry_count: u32,
};

const CacheEntryWithoutName = extern struct {
    stat: Stat,
    sha1: [20]u8,
    namelen: u16,
};

const CacheEntry = struct {
    index: u8,
    stat: Stat,
    sha1: [20]u8,
    namelen: u16,
    name: []u8,
};

pub const CacheReader = struct {
    memory: []align(std.mem.page_size) u8,
    entry_index: u8 = 0,
    position: u32 = @sizeOf(CacheHeader),

    pub fn header(self: *CacheReader) CacheHeader {
        return fromMem(CacheHeader, self.memory[0..@sizeOf(CacheHeader)]);
    }

    pub fn next(self: *CacheReader) ?CacheEntry {
        self.entry_index += 1;
        if (self.entry_index > self.header().entry_count) return null;
        const nth_entry_without_name = fromMem(CacheEntryWithoutName, self.memory[self.position .. self.position + @sizeOf(CacheEntryWithoutName)]);

        // Offset does not equal to @sizeOf(CacheEntryWithoutName)+nth_entry.namelen
        // (this include zero-padding -- adjustment of alignment)
        const name_offset = @offsetOf(CacheEntryWithoutName, "namelen") + @sizeOf(@TypeOf(@field(nth_entry_without_name, "namelen")));
        const nth_entry_name = self.memory[self.position + name_offset .. self.position + name_offset + nth_entry_without_name.namelen];

        // Add zero-padding to position
        // https://github.com/git/git/blob/cee0c2750bb5f1b38f15ef961517e03c2e39c9ec/read-cache.c#L1263
        self.position += (name_offset + nth_entry_without_name.namelen + 8) & ~@as(u8, 7);
        return CacheEntry{
            .index = self.entry_index - 1,
            .stat = nth_entry_without_name.stat,
            .sha1 = nth_entry_without_name.sha1,
            .namelen = nth_entry_without_name.namelen,
            .name = nth_entry_name,
        };
    }

    fn rewind(self: *CacheHeader) void {
        self.entry_index = 0;
        self.position = @sizeOf(CacheHeader);
    }
};

test "Read .git/index" {
    var gitdir = try std.fs.cwd().openDir(".git", .{});
    defer gitdir.close();
    var index_file = try gitdir.openFile("index", .{});
    defer index_file.close();

    const mapped = try std.os.mmap(null, (try index_file.stat()).size, std.os.PROT.READ, std.os.MAP.PRIVATE, index_file.handle, 0);
    defer std.os.munmap(mapped);

    var reader = CacheReader{ .memory = mapped };
    // std.debug.print("\n", .{});
    // std.debug.print("HEADER: {}\n", .{reader.header()});
    // while (reader.next()) |entry| {
    //     std.debug.print("{d}TH ENTRY: {}\n", .{ entry.index, entry });
    // }
    while (reader.next()) |_| {}
}
