const std = @import("std");
const rl = @import("raylib");
const shape_mod = @import("shape.zig");

/// ZigDraw binary file format (.zdraw)
///
/// Header:
///   [4 bytes] magic: "ZDRW"
///   [2 bytes] version: u16 (currently 1)
///   [4 bytes] shape_count: u32
///
/// Per shape:
///   [1 byte]  kind: u8 (ShapeKind enum ordinal)
///   [8 bytes] start: f32 x, f32 y
///   [8 bytes] end: f32 x, f32 y
///   [4 bytes] color: r, g, b, a
///   [4 bytes] stroke_width: f32
///   [4 bytes] point_count: u32  (0 for non-freehand)
///   [8 * point_count bytes] points: f32 x, f32 y each
const magic = [4]u8{ 'Z', 'D', 'R', 'W' };
const format_version: u16 = 1;

pub const FileError = error{
    InvalidMagic,
    UnsupportedVersion,
    UnexpectedEof,
    WriteFailed,
};

pub fn save(shape_list: *const shape_mod.ShapeList, path: []const u8) !void {
    const file = try createFile(path);
    defer file.close();
    var buf: [4096]u8 = undefined;
    var w = file.writer(&buf);
    const writer = &w.interface;

    // Header
    try writer.writeAll(&magic);
    const ver_le = std.mem.nativeToLittle(u16, format_version);
    try writer.writeAll(std.mem.asBytes(&ver_le));
    const count: u32 = @intCast(shape_list.shapes.items.len);
    const count_le = std.mem.nativeToLittle(u32, count);
    try writer.writeAll(std.mem.asBytes(&count_le));

    // Shapes
    for (shape_list.shapes.items) |s| {
        try writer.writeAll(&[1]u8{@intFromEnum(s.kind)});

        // start
        try writer.writeAll(std.mem.asBytes(&s.start.x));
        try writer.writeAll(std.mem.asBytes(&s.start.y));
        // end
        try writer.writeAll(std.mem.asBytes(&s.end.x));
        try writer.writeAll(std.mem.asBytes(&s.end.y));
        // color
        try writer.writeAll(&[4]u8{ s.color.r, s.color.g, s.color.b, s.color.a });
        // stroke_width
        try writer.writeAll(std.mem.asBytes(&s.stroke_width));
        // points
        const point_count: u32 = @intCast(s.points.items.len);
        const pc_le = std.mem.nativeToLittle(u32, point_count);
        try writer.writeAll(std.mem.asBytes(&pc_le));
        for (s.points.items) |p| {
            try writer.writeAll(std.mem.asBytes(&p.x));
            try writer.writeAll(std.mem.asBytes(&p.y));
        }
    }
    try writer.flush();
}

pub fn load(shape_list: *shape_mod.ShapeList, path: []const u8) !void {
    const file = try openFile(path);
    defer file.close();
    var buf: [4096]u8 = undefined;
    var r = file.reader(&buf);
    const reader = &r.interface;

    // Header
    const magic_ptr = try reader.takeArray(4);
    if (!std.mem.eql(u8, magic_ptr, &magic)) {
        return FileError.InvalidMagic;
    }

    const version = std.mem.littleToNative(u16, @bitCast((try reader.takeArray(2)).*));
    if (version != format_version) {
        return FileError.UnsupportedVersion;
    }

    const shape_count = std.mem.littleToNative(u32, @bitCast((try reader.takeArray(4)).*));

    // Clear existing shapes
    for (shape_list.shapes.items) |*s| s.deinit(shape_list.allocator);
    shape_list.shapes.clearRetainingCapacity();

    // Read shapes
    for (0..shape_count) |_| {
        const kind_byte = try reader.takeByte();
        const kind: shape_mod.ShapeKind = @enumFromInt(kind_byte);

        const start_x = @as(f32, @bitCast((try reader.takeArray(4)).*));
        const start_y = @as(f32, @bitCast((try reader.takeArray(4)).*));
        const end_x = @as(f32, @bitCast((try reader.takeArray(4)).*));
        const end_y = @as(f32, @bitCast((try reader.takeArray(4)).*));

        const color_ptr = try reader.takeArray(4);

        const stroke_width = @as(f32, @bitCast((try reader.takeArray(4)).*));

        const point_count = std.mem.littleToNative(u32, @bitCast((try reader.takeArray(4)).*));

        var points: std.ArrayList(rl.Vector2) = .empty;
        for (0..point_count) |_| {
            const px = @as(f32, @bitCast((try reader.takeArray(4)).*));
            const py = @as(f32, @bitCast((try reader.takeArray(4)).*));
            try points.append(shape_list.allocator, .{ .x = px, .y = py });
        }

        const shape = shape_mod.Shape{
            .kind = kind,
            .start = .{ .x = start_x, .y = start_y },
            .end = .{ .x = end_x, .y = end_y },
            .color = rl.Color.init(color_ptr[0], color_ptr[1], color_ptr[2], color_ptr[3]),
            .stroke_width = stroke_width,
            .points = points,
            .selected = false,
        };
        try shape_list.shapes.append(shape_list.allocator, shape);
    }
}

fn isAbsolute(path: []const u8) bool {
    if (path.len >= 1 and (path[0] == '/' or path[0] == '\\')) return true;
    if (path.len >= 3 and path[1] == ':' and (path[2] == '/' or path[2] == '\\')) return true;
    return false;
}

fn toNativePath(path: []const u8, out: *[std.fs.max_path_bytes]u8) []const u8 {
    const len = @min(path.len, out.len);
    for (0..len) |i| {
        out[i] = if (path[i] == '/') '\\' else path[i];
    }
    return out[0..len];
}

fn createFile(path: []const u8) !std.fs.File {
    if (isAbsolute(path)) {
        var native_buf: [std.fs.max_path_bytes]u8 = undefined;
        const native = toNativePath(path, &native_buf);
        return std.fs.createFileAbsolute(native, .{});
    }
    return std.fs.cwd().createFile(path, .{});
}

fn openFile(path: []const u8) !std.fs.File {
    if (isAbsolute(path)) {
        var native_buf: [std.fs.max_path_bytes]u8 = undefined;
        const native = toNativePath(path, &native_buf);
        return std.fs.openFileAbsolute(native, .{});
    }
    return std.fs.cwd().openFile(path, .{});
}
