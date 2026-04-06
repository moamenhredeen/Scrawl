const std = @import("std");
const shape_mod = @import("shape.zig");
const rl = @import("raylib");

/// A snapshot-based undo/redo history.
/// Each entry is a full copy of the shape list state.
const max_history = 50;

pub const Action = struct {
    /// Serialized list of shape data (without freehand points for memory).
    shapes: []ShapeSnapshot,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Action) void {
        for (self.shapes) |*s| s.deinit(self.allocator);
        self.allocator.free(self.shapes);
    }
};

pub const ShapeSnapshot = struct {
    kind: shape_mod.ShapeKind,
    start: rl.Vector2,
    end: rl.Vector2,
    color: rl.Color,
    stroke_width: f32,
    points: []rl.Vector2,

    pub fn deinit(self: *ShapeSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.points);
    }
};

pub const History = struct {
    undo_stack: std.ArrayList(Action) = .empty,
    redo_stack: std.ArrayList(Action) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) History {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *History) void {
        for (self.undo_stack.items) |*a| a.deinit();
        self.undo_stack.deinit(self.allocator);
        for (self.redo_stack.items) |*a| a.deinit();
        self.redo_stack.deinit(self.allocator);
    }

    /// Take a snapshot of the current shape list and push to undo stack.
    pub fn pushState(self: *History, shape_list: *const shape_mod.ShapeList) !void {
        // Clear redo stack on new action
        for (self.redo_stack.items) |*a| a.deinit();
        self.redo_stack.clearRetainingCapacity();

        const action = try self.snapshot(shape_list);
        try self.undo_stack.append(self.allocator, action);

        // Trim old history
        while (self.undo_stack.items.len > max_history) {
            var old = self.undo_stack.orderedRemove(0);
            old.deinit();
        }
    }

    pub fn undo(self: *History, shape_list: *shape_mod.ShapeList) !void {
        if (self.undo_stack.items.len == 0) return;

        // Save current state to redo
        const current = try self.snapshot(shape_list);
        try self.redo_stack.append(self.allocator, current);

        // Pop from undo and restore
        var action = self.undo_stack.pop().?;
        self.restoreFrom(&action, shape_list);
        action.deinit();
    }

    pub fn redo(self: *History, shape_list: *shape_mod.ShapeList) !void {
        if (self.redo_stack.items.len == 0) return;

        // Save current state to undo
        const current = try self.snapshot(shape_list);
        try self.undo_stack.append(self.allocator, current);

        // Pop from redo and restore
        var action = self.redo_stack.pop().?;
        self.restoreFrom(&action, shape_list);
        action.deinit();
    }

    pub fn canUndo(self: History) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn canRedo(self: History) bool {
        return self.redo_stack.items.len > 0;
    }

    fn snapshot(self: *History, shape_list: *const shape_mod.ShapeList) !Action {
        const shapes = try self.allocator.alloc(ShapeSnapshot, shape_list.shapes.items.len);
        for (shape_list.shapes.items, 0..) |s, i| {
            const pts = try self.allocator.alloc(rl.Vector2, s.points.items.len);
            @memcpy(pts, s.points.items);
            shapes[i] = .{
                .kind = s.kind,
                .start = s.start,
                .end = s.end,
                .color = s.color,
                .stroke_width = s.stroke_width,
                .points = pts,
            };
        }
        return .{
            .shapes = shapes,
            .allocator = self.allocator,
        };
    }

    fn restoreFrom(_: *History, action: *Action, shape_list: *shape_mod.ShapeList) void {
        // Clear current shapes
        for (shape_list.shapes.items) |*s| s.deinit(shape_list.allocator);
        shape_list.shapes.clearRetainingCapacity();

        // Rebuild from snapshot
        for (action.shapes) |snap| {
            var points: std.ArrayList(rl.Vector2) = .empty;
            points.appendSlice(shape_list.allocator, snap.points) catch continue;

            const new_shape = shape_mod.Shape{
                .kind = snap.kind,
                .start = snap.start,
                .end = snap.end,
                .color = snap.color,
                .stroke_width = snap.stroke_width,
                .points = points,
                .selected = false,
            };
            shape_list.shapes.append(shape_list.allocator, new_shape) catch continue;
        }
    }
};
