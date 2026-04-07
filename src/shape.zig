const std = @import("std");
const rl = @import("raylib");
const fonts = @import("fonts.zig");

pub const ShapeKind = enum {
    rectangle,
    ellipse,
    line,
    arrow,
    freehand,
    text,
};

pub const Shape = struct {
    kind: ShapeKind,
    start: rl.Vector2,
    end: rl.Vector2,
    color: rl.Color,
    stroke_width: f32,
    points: std.ArrayList(rl.Vector2),
    text_buf: [256]u8 = undefined,
    text_len: usize = 0,
    font_size: f32 = 20,
    selected: bool = false,

    pub fn deinit(self: *Shape, allocator: std.mem.Allocator) void {
        self.points.deinit(allocator);
    }

    pub fn boundingRect(self: Shape) rl.Rectangle {
        return switch (self.kind) {
            .rectangle, .ellipse => .{
                .x = @min(self.start.x, self.end.x),
                .y = @min(self.start.y, self.end.y),
                .width = @abs(self.end.x - self.start.x),
                .height = @abs(self.end.y - self.start.y),
            },
            .line, .arrow => .{
                .x = @min(self.start.x, self.end.x) - 5,
                .y = @min(self.start.y, self.end.y) - 5,
                .width = @abs(self.end.x - self.start.x) + 10,
                .height = @abs(self.end.y - self.start.y) + 10,
            },
            .freehand => blk: {
                if (self.points.items.len == 0) break :blk rl.Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
                var min_x: f32 = self.points.items[0].x;
                var min_y: f32 = self.points.items[0].y;
                var max_x: f32 = min_x;
                var max_y: f32 = min_y;
                for (self.points.items[1..]) |p| {
                    min_x = @min(min_x, p.x);
                    min_y = @min(min_y, p.y);
                    max_x = @max(max_x, p.x);
                    max_y = @max(max_y, p.y);
                }
                break :blk rl.Rectangle{
                    .x = min_x - 5,
                    .y = min_y - 5,
                    .width = max_x - min_x + 10,
                    .height = max_y - min_y + 10,
                };
            },
            .text => blk: {
                const text_z = self.getTextZ();
                const size = rl.measureTextEx(fonts.get(), text_z, self.font_size, 1);
                break :blk rl.Rectangle{
                    .x = self.start.x,
                    .y = self.start.y,
                    .width = @max(size.x, 10),
                    .height = @max(size.y, self.font_size),
                };
            },
        };
    }

    pub fn containsPoint(self: Shape, point: rl.Vector2) bool {
        switch (self.kind) {
            .rectangle, .ellipse => {
                return rl.checkCollisionPointRec(point, self.boundingRect());
            },
            .line, .arrow => {
                return rl.checkCollisionPointLine(point, self.start, self.end, @intFromFloat(self.stroke_width + 6));
            },
            .freehand => {
                for (self.points.items) |p| {
                    const dx = point.x - p.x;
                    const dy = point.y - p.y;
                    if (dx * dx + dy * dy < (self.stroke_width + 6) * (self.stroke_width + 6)) return true;
                }
                return false;
            },
            .text => {
                return rl.checkCollisionPointRec(point, self.boundingRect());
            },
        }
    }

    /// Check if this shape's bounding rect intersects with a given rectangle.
    pub fn intersectsRect(self: Shape, rect: rl.Rectangle) bool {
        const br = self.boundingRect();
        return rl.checkCollisionRecs(br, rect);
    }

    pub fn draw(self: Shape) void {
        switch (self.kind) {
            .rectangle => {
                const rect = self.normalizedRect();
                rl.drawRectangleLinesEx(rect, self.stroke_width, self.color);
            },
            .ellipse => {
                const rect = self.normalizedRect();
                const cx = rect.x + rect.width / 2;
                const cy = rect.y + rect.height / 2;
                rl.drawEllipseLines(
                    @intFromFloat(cx),
                    @intFromFloat(cy),
                    rect.width / 2,
                    rect.height / 2,
                    self.color,
                );
            },
            .line => {
                rl.drawLineEx(self.start, self.end, self.stroke_width, self.color);
            },
            .arrow => {
                rl.drawLineEx(self.start, self.end, self.stroke_width, self.color);
                drawArrowHead(self.start, self.end, self.stroke_width, self.color);
            },
            .freehand => {
                if (self.points.items.len < 2) return;
                for (0..self.points.items.len - 1) |i| {
                    rl.drawLineEx(self.points.items[i], self.points.items[i + 1], self.stroke_width, self.color);
                }
            },
            .text => {
                const text_z = self.getTextZ();
                rl.drawTextEx(fonts.get(), text_z, self.start, self.font_size, 1, self.color);
            },
        }

        if (self.selected) {
            const r = self.boundingRect();
            const sel_rect = rl.Rectangle{
                .x = r.x - 3,
                .y = r.y - 3,
                .width = r.width + 6,
                .height = r.height + 6,
            };
            rl.drawRectangleLinesEx(sel_rect, 1, rl.Color.init(100, 150, 255, 200));
        }
    }

    pub fn getTextZ(self: *const Shape) [:0]const u8 {
        const S = struct {
            threadlocal var buf: [257]u8 = undefined;
        };
        const len = @min(self.text_len, 256);
        @memcpy(S.buf[0..len], self.text_buf[0..len]);
        S.buf[len] = 0;
        return S.buf[0..len :0];
    }

    pub fn setText(self: *Shape, text: []const u8) void {
        const len = @min(text.len, self.text_buf.len);
        @memcpy(self.text_buf[0..len], text[0..len]);
        self.text_len = len;
    }

    pub fn textInsertChar(self: *Shape, c: u8) void {
        if (self.text_len >= self.text_buf.len) return;
        self.text_buf[self.text_len] = c;
        self.text_len += 1;
    }

    pub fn textDeleteChar(self: *Shape) void {
        if (self.text_len > 0) self.text_len -= 1;
    }

    fn normalizedRect(self: Shape) rl.Rectangle {
        return .{
            .x = @min(self.start.x, self.end.x),
            .y = @min(self.start.y, self.end.y),
            .width = @abs(self.end.x - self.start.x),
            .height = @abs(self.end.y - self.start.y),
        };
    }
};

fn drawArrowHead(from: rl.Vector2, to: rl.Vector2, thickness: f32, color: rl.Color) void {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 1) return;

    const nx = dx / len;
    const ny = dy / len;
    const arrow_size: f32 = @max(10, thickness * 4);

    const p1 = rl.Vector2{
        .x = to.x - arrow_size * nx + arrow_size * 0.4 * ny,
        .y = to.y - arrow_size * ny - arrow_size * 0.4 * nx,
    };
    const p2 = rl.Vector2{
        .x = to.x - arrow_size * nx - arrow_size * 0.4 * ny,
        .y = to.y - arrow_size * ny + arrow_size * 0.4 * nx,
    };
    rl.drawLineEx(to, p1, thickness, color);
    rl.drawLineEx(to, p2, thickness, color);
}

pub const ShapeList = struct {
    shapes: std.ArrayList(Shape) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ShapeList {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ShapeList) void {
        for (self.shapes.items) |*s| s.deinit(self.allocator);
        self.shapes.deinit(self.allocator);
    }

    pub fn add(self: *ShapeList, shape: Shape) !void {
        try self.shapes.append(self.allocator, shape);
    }

    pub fn remove(self: *ShapeList, index: usize) void {
        var s = self.shapes.orderedRemove(index);
        s.deinit(self.allocator);
    }

    pub fn deselectAll(self: *ShapeList) void {
        for (self.shapes.items) |*s| s.selected = false;
    }

    pub fn drawAll(self: ShapeList) void {
        for (self.shapes.items) |s| s.draw();
    }

    pub fn findAt(self: ShapeList, point: rl.Vector2) ?usize {
        // Search in reverse so topmost shapes are found first
        var i: usize = self.shapes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.shapes.items[i].containsPoint(point)) return i;
        }
        return null;
    }

    pub fn deleteSelected(self: *ShapeList) void {
        var i: usize = self.shapes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.shapes.items[i].selected) {
                self.remove(i);
            }
        }
    }

    pub fn hasSelected(self: ShapeList) bool {
        for (self.shapes.items) |s| {
            if (s.selected) return true;
        }
        return false;
    }

    /// Select all shapes whose bounding rect intersects the given rectangle.
    pub fn selectInRect(self: *ShapeList, rect: rl.Rectangle) void {
        for (self.shapes.items) |*s| {
            if (s.intersectsRect(rect)) {
                s.selected = true;
            }
        }
    }

    /// Move all selected shapes by a delta.
    pub fn moveSelected(self: *ShapeList, dx: f32, dy: f32) void {
        for (self.shapes.items) |*s| {
            if (s.selected) {
                s.start.x += dx;
                s.start.y += dy;
                s.end.x += dx;
                s.end.y += dy;
                for (s.points.items) |*p| {
                    p.x += dx;
                    p.y += dy;
                }
            }
        }
    }
};
