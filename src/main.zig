const rl = @import("raylib");
const std = @import("std");
const shape_mod = @import("shape.zig");
const Canvas = @import("canvas.zig").Canvas;
const toolbar_mod = @import("toolbar.zig");
const Toolbar = toolbar_mod.Toolbar;
const Tool = toolbar_mod.Tool;
const Theme = toolbar_mod.Theme;
const History = @import("history.zig").History;

const init_width = 1280;
const init_height = 800;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setConfigFlags(.{ .window_resizable = true, .msaa_4x_hint = true });
    rl.initWindow(init_width, init_height, "ZigDraw");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var canvas = Canvas{};
    var toolbar = Toolbar{};
    var shapes = shape_mod.ShapeList.init(allocator);
    defer shapes.deinit();
    var history = History.init(allocator);
    defer history.deinit();

    // Drawing state
    var is_drawing = false;
    var current_shape: ?shape_mod.Shape = null;

    // Selection/drag state
    var is_dragging = false;
    var drag_offset = rl.Vector2{ .x = 0, .y = 0 };
    var drag_index: ?usize = null;

    // Push initial empty state
    try history.pushState(&shapes);

    while (!rl.windowShouldClose()) {
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        const mouse_screen = rl.getMousePosition();
        const mouse_world = canvas.screenToWorld(mouse_screen);
        const in_canvas = mouse_screen.y >= toolbar.height;

        // --- Keyboard shortcuts ---
        toolbar.handleShortcuts();

        // Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo
        const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
        const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        if (ctrl and rl.isKeyPressed(.z) and !shift) {
            try history.undo(&shapes);
        }
        if (ctrl and (rl.isKeyPressed(.y) or (rl.isKeyPressed(.z) and shift))) {
            try history.redo(&shapes);
        }

        // Delete selected
        if (rl.isKeyPressed(.delete) or rl.isKeyPressed(.backspace)) {
            var has_selected = false;
            for (shapes.shapes.items) |s| {
                if (s.selected) {
                    has_selected = true;
                    break;
                }
            }
            if (has_selected) {
                try history.pushState(&shapes);
                shapes.deleteSelected();
            }
        }

        // Escape: cancel drawing or deselect
        if (rl.isKeyPressed(.escape)) {
            if (is_drawing) {
                if (current_shape) |*cs| cs.deinit(allocator);
                current_shape = null;
                is_drawing = false;
            } else {
                shapes.deselectAll();
            }
        }

        // --- Canvas pan/zoom ---
        canvas.update(toolbar.height);

        // --- Tool interaction ---
        if (in_canvas and !canvas.is_panning and !rl.isKeyDown(.space)) {
            switch (toolbar.current_tool) {
                .select => handleSelect(
                    &shapes,
                    &is_dragging,
                    &drag_offset,
                    &drag_index,
                    mouse_world,
                    &history,
                ),
                else => handleDraw(
                    &shapes,
                    &is_drawing,
                    &current_shape,
                    &toolbar,
                    &canvas,
                    mouse_world,
                    allocator,
                    &history,
                ),
            }
        }

        // --- Drawing ---
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(toolbar.theme.bgColor());

        // Draw grid in world space
        canvas.beginDraw();
        drawGrid(&canvas, screen_w, screen_h, toolbar.height, toolbar.theme);
        shapes.drawAll();
        if (current_shape) |cs| cs.draw();
        canvas.endDraw();

        // Draw toolbar (screen space, on top)
        toolbar.draw(screen_w, history.canUndo(), history.canRedo());

        // Handle toolbar undo/redo button clicks
        if (toolbar.undo_clicked) {
            try history.undo(&shapes);
        }
        if (toolbar.redo_clicked) {
            try history.redo(&shapes);
        }

        // Status bar
        drawStatusBar(screen_w, screen_h, &toolbar, &canvas, shapes.shapes.items.len, toolbar.theme);
    }
}

fn handleSelect(
    shapes: *shape_mod.ShapeList,
    is_dragging: *bool,
    drag_offset: *rl.Vector2,
    drag_index: *?usize,
    mouse_world: rl.Vector2,
    history: *History,
) void {
    if (rl.isMouseButtonPressed(.left)) {
        if (shapes.findAt(mouse_world)) |idx| {
            if (!shapes.shapes.items[idx].selected) {
                shapes.deselectAll();
                shapes.shapes.items[idx].selected = true;
            }
            is_dragging.* = true;
            drag_index.* = idx;
            drag_offset.* = .{
                .x = mouse_world.x - shapes.shapes.items[idx].start.x,
                .y = mouse_world.y - shapes.shapes.items[idx].start.y,
            };
        } else {
            shapes.deselectAll();
        }
    }

    if (is_dragging.* and rl.isMouseButtonDown(.left)) {
        if (drag_index.*) |idx| {
            if (idx < shapes.shapes.items.len) {
                const s = &shapes.shapes.items[idx];
                const dx = mouse_world.x - drag_offset.*.x - s.start.x;
                const dy = mouse_world.y - drag_offset.*.y - s.start.y;
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

    if (rl.isMouseButtonReleased(.left) and is_dragging.*) {
        is_dragging.* = false;
        // Push state after drag
        history.pushState(shapes) catch {};
        drag_index.* = null;
    }
}

fn handleDraw(
    shapes: *shape_mod.ShapeList,
    is_drawing: *bool,
    current_shape: *?shape_mod.Shape,
    toolbar: *Toolbar,
    _: *Canvas,
    mouse_world: rl.Vector2,
    allocator: std.mem.Allocator,
    history: *History,
) void {
    const kind = toolbar.toolToShapeKind() orelse return;

    if (rl.isMouseButtonPressed(.left)) {
        is_drawing.* = true;
        current_shape.* = shape_mod.Shape{
            .kind = kind,
            .start = mouse_world,
            .end = mouse_world,
            .color = toolbar.currentColor(),
            .stroke_width = toolbar.currentStrokeWidth(),
            .points = .empty,
        };
        if (kind == .freehand) {
            current_shape.*.?.points.append(allocator, mouse_world) catch {};
        }
    }

    if (is_drawing.* and rl.isMouseButtonDown(.left)) {
        if (current_shape.*) |*cs| {
            cs.end = mouse_world;
            if (kind == .freehand) {
                cs.points.append(allocator, mouse_world) catch {};
            }
        }
    }

    if (rl.isMouseButtonReleased(.left) and is_drawing.*) {
        is_drawing.* = false;
        if (current_shape.*) |cs| {
            // Only add if shape has some size
            const dx = cs.end.x - cs.start.x;
            const dy = cs.end.y - cs.start.y;
            const has_size = (dx * dx + dy * dy > 4) or (cs.kind == .freehand and cs.points.items.len > 2);
            if (has_size) {
                history.pushState(shapes) catch {};
                shapes.add(cs) catch {};
            } else {
                var tmp = cs;
                tmp.deinit(allocator);
            }
            current_shape.* = null;
        }
    }
}

fn drawGrid(canvas: *const Canvas, screen_w: f32, screen_h: f32, toolbar_h: f32, theme: Theme) void {
    // Determine grid spacing based on zoom
    var grid_size: f32 = 20;
    if (canvas.zoom < 0.3) grid_size = 100;
    if (canvas.zoom < 0.1) grid_size = 500;

    const top_left = canvas.screenToWorld(.{ .x = 0, .y = toolbar_h });
    const bottom_right = canvas.screenToWorld(.{ .x = screen_w, .y = screen_h });

    const start_x = @floor(top_left.x / grid_size) * grid_size;
    const start_y = @floor(top_left.y / grid_size) * grid_size;

    const gc = theme.gridColor();

    var x = start_x;
    while (x <= bottom_right.x) : (x += grid_size) {
        rl.drawLineV(
            .{ .x = x, .y = top_left.y },
            .{ .x = x, .y = bottom_right.y },
            gc,
        );
    }

    var y = start_y;
    while (y <= bottom_right.y) : (y += grid_size) {
        rl.drawLineV(
            .{ .x = top_left.x, .y = y },
            .{ .x = bottom_right.x, .y = y },
            gc,
        );
    }
}

fn drawStatusBar(screen_w: f32, screen_h: f32, toolbar: *const Toolbar, canvas: *const Canvas, shape_count: usize, theme: Theme) void {
    const bar_h: f32 = 24;
    const y: f32 = screen_h - bar_h;

    rl.drawRectangle(0, @intFromFloat(y), @intFromFloat(screen_w), @intFromFloat(bar_h), theme.statusBarBg());
    const tc = theme.statusBarText();

    // Tool name
    const tool_name: [:0]const u8 = switch (toolbar.current_tool) {
        .select => "Select (V)",
        .rectangle => "Rectangle (R)",
        .ellipse => "Ellipse (O)",
        .line => "Line (L)",
        .arrow => "Arrow (A)",
        .freehand => "Pen (P)",
    };
    rl.drawText(tool_name, 10, @intFromFloat(y + 4), 14, tc);

    // Zoom
    var zoom_buf: [32]u8 = undefined;
    const zoom_pct: i32 = @intFromFloat(canvas.zoom * 100);
    const zoom_text = std.fmt.bufPrintZ(&zoom_buf, "{d}%", .{zoom_pct}) catch "?";
    rl.drawText(zoom_text, @intFromFloat(screen_w / 2 - 30), @intFromFloat(y + 4), 14, tc);

    // Shape count
    var count_buf: [32]u8 = undefined;
    const count_text = std.fmt.bufPrintZ(&count_buf, "{d} shapes", .{shape_count}) catch "?";
    rl.drawText(count_text, @intFromFloat(screen_w - 120), @intFromFloat(y + 4), 14, tc);
}
