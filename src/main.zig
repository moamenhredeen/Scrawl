const rl = @import("raylib");
const std = @import("std");
const shape_mod = @import("shape.zig");
const Canvas = @import("canvas.zig").Canvas;
const toolbar_mod = @import("toolbar.zig");
const Toolbar = toolbar_mod.Toolbar;
const Tool = toolbar_mod.Tool;
const Theme = toolbar_mod.Theme;
const History = @import("history.zig").History;
const file_io = @import("file_io.zig");
const CommandBar = @import("command_bar.zig").CommandBar;
const CmdMode = @import("command_bar.zig").Mode;
const fonts = @import("fonts.zig");

const init_width = 1280;
const init_height = 800;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setConfigFlags(.{ .window_resizable = true, .msaa_4x_hint = true });
    rl.initWindow(init_width, init_height, "ZigDraw");
    defer rl.closeWindow();
    rl.setExitKey(.null);
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

    // Text editing state
    var is_editing_text = false;

    // Selection/drag state
    var is_dragging = false;
    var drag_start = rl.Vector2{ .x = 0, .y = 0 };
    var drag_last = rl.Vector2{ .x = 0, .y = 0 };

    // Marquee selection state
    var is_marquee = false;
    var marquee_start = rl.Vector2{ .x = 0, .y = 0 };

    // Command bar state
    var cmd_bar = CommandBar{};

    // Current file path (set after save or open)
    var current_file_buf: [1024]u8 = undefined;
    var current_file_len: usize = 0;

    // Toast notification state
    var toast_msg: [:0]const u8 = "";
    var toast_timer: f32 = 0;

    // Push initial empty state
    try history.pushState(&shapes);

    while (!rl.windowShouldClose()) {
        const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
        const mouse_screen = rl.getMousePosition();
        const mouse_world = canvas.screenToWorld(mouse_screen);
        const in_canvas = mouse_screen.y >= toolbar.height;

        // --- Keyboard shortcuts (disabled when command bar or text editing is active) ---
        const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
        const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        if (cmd_bar.mode == .hidden and !is_editing_text) {
            toolbar.handleShortcuts();

            // Ctrl+Z undo, Ctrl+Y / Ctrl+Shift+Z redo
            if (ctrl and rl.isKeyPressed(.z) and !shift) {
                try history.undo(&shapes);
            }
            if (ctrl and (rl.isKeyPressed(.y) or (rl.isKeyPressed(.z) and shift))) {
                try history.redo(&shapes);
            }
        }

        // Delete selected (only when command bar hidden and not editing text)
        if (cmd_bar.mode == .hidden and !is_editing_text and (rl.isKeyPressed(.delete) or rl.isKeyPressed(.backspace))) {
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

        // Escape: cancel text editing, cancel drawing, deselect, or reset tool
        if (rl.isKeyPressed(.escape) and cmd_bar.mode == .hidden) {
            if (is_editing_text) {
                // Cancel text editing, discard the text shape
                if (current_shape) |*cs| cs.deinit(allocator);
                current_shape = null;
                is_editing_text = false;
            } else if (is_drawing) {
                if (current_shape) |*cs| cs.deinit(allocator);
                current_shape = null;
                is_drawing = false;
            } else if (toolbar.current_tool != .select) {
                toolbar.current_tool = .select;
            } else {
                shapes.deselectAll();
            }
        }

        // Ctrl+S save, Ctrl+O load — open command bar
        if (cmd_bar.mode == .hidden) {
            if (ctrl and rl.isKeyPressed(.s)) {
                if (current_file_len > 0) {
                    // Save directly to known file
                    if (file_io.save(&shapes, current_file_buf[0..current_file_len])) {
                        toast_msg = "Saved!";
                        toast_timer = 2.0;
                    } else |_| {
                        toast_msg = "Save failed!";
                        toast_timer = 2.0;
                    }
                } else {
                    cmd_bar.open(.save, true);
                }
            }
            if (ctrl and rl.isKeyPressed(.o)) {
                cmd_bar.open(.open, false);
            }
        }

        // Command bar input handling
        const cmd_result = cmd_bar.update();
        if (cmd_result == .confirmed) {
            const path = cmd_bar.getPath();
            if (path.len > 0) {
                switch (cmd_bar.mode) {
                    .save => {
                        if (file_io.save(&shapes, path)) {
                            // Remember the file path
                            const plen = @min(path.len, current_file_buf.len);
                            @memcpy(current_file_buf[0..plen], path[0..plen]);
                            current_file_len = plen;
                            toast_msg = "Saved!";
                            toast_timer = 2.0;
                        } else |_| {
                            toast_msg = "Save failed!";
                            toast_timer = 2.0;
                        }
                    },
                    .open => {
                        if (file_io.load(&shapes, path)) {
                            // Remember the file path
                            const plen = @min(path.len, current_file_buf.len);
                            @memcpy(current_file_buf[0..plen], path[0..plen]);
                            current_file_len = plen;
                            toast_msg = "Loaded!";
                            toast_timer = 2.0;
                            history.pushState(&shapes) catch {};
                        } else |_| {
                            toast_msg = "Load failed!";
                            toast_timer = 2.0;
                        }
                    },
                    .hidden => {},
                }
            }
            cmd_bar.close();
        }

        // --- Canvas pan/zoom (skip when command bar is active) ---
        if (cmd_bar.mode == .hidden) canvas.update(toolbar.height);

        // --- Text editing input ---
        if (is_editing_text) {
            if (current_shape) |*cs| {
                // Enter confirms the text
                if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter)) {
                    if (cs.text_len > 0) {
                        try history.pushState(&shapes);
                        try shapes.add(cs.*);
                    } else {
                        cs.deinit(allocator);
                    }
                    current_shape = null;
                    is_editing_text = false;
                } else {
                    // Backspace
                    if (rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) {
                        cs.textDeleteChar();
                    }
                    // Character input
                    var char = rl.getCharPressed();
                    while (char != 0) {
                        if (char >= 32 and char < 127) {
                            cs.textInsertChar(@intCast(char));
                        }
                        char = rl.getCharPressed();
                    }
                }
            }
        }

        // --- Tool interaction (skip when command bar is active or editing text) ---
        if (in_canvas and !canvas.is_panning and !rl.isKeyDown(.space) and cmd_bar.mode == .hidden and !is_editing_text) {
            switch (toolbar.current_tool) {
                .select => handleSelect(
                    &shapes,
                    &is_dragging,
                    &drag_start,
                    &drag_last,
                    &is_marquee,
                    &marquee_start,
                    mouse_world,
                    &history,
                ),
                .text => {
                    // Click to place text insertion point
                    if (rl.isMouseButtonPressed(.left)) {
                        current_shape = shape_mod.Shape{
                            .kind = .text,
                            .start = mouse_world,
                            .end = mouse_world,
                            .color = toolbar.currentColor(),
                            .stroke_width = toolbar.currentStrokeWidth(),
                            .font_size = 20,
                            .points = .empty,
                        };
                        is_editing_text = true;
                    }
                },
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
        if (current_shape) |cs| {
            cs.draw();
            // Draw blinking cursor for text editing
            if (is_editing_text and cs.kind == .text) {
                const time: f32 = @floatCast(rl.getTime());
                if (@mod(time, 1.0) < 0.6) {
                    const text_z = cs.getTextZ();
                    const text_size = rl.measureTextEx(fonts.get(), text_z, cs.font_size, 1);
                    const cursor_x = cs.start.x + text_size.x;
                    const cursor_y = cs.start.y;
                    rl.drawLineEx(
                        .{ .x = cursor_x, .y = cursor_y },
                        .{ .x = cursor_x, .y = cursor_y + cs.font_size },
                        1.0 / canvas.zoom,
                        cs.color,
                    );
                }
            }
        }
        // Draw marquee selection rectangle
        if (is_marquee) {
            const mrect = normalizeRect(marquee_start, mouse_world);
            rl.drawRectangleLinesEx(mrect, 1.0 / canvas.zoom, rl.Color.init(100, 150, 255, 200));
            rl.drawRectangleRec(mrect, rl.Color.init(100, 150, 255, 40));
        }
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

        // Command bar (above status bar)
        cmd_bar.draw(screen_w, screen_h, toolbar.theme);

        // Status bar
        drawStatusBar(screen_w, screen_h, &toolbar, &canvas, shapes.shapes.items.len, toolbar.theme);

        // Toast notification
        if (toast_timer > 0) {
            toast_timer -= rl.getFrameTime();
            const alpha: u8 = if (toast_timer > 0.5) 220 else if (toast_timer > 0) @intFromFloat(toast_timer * 440) else 0;
            const tw: f32 = @floatFromInt(fonts.measureText(toast_msg, 16));
            const tx = screen_w / 2 - tw / 2 - 12;
            const ty = screen_h - 60;
            rl.drawRectangleRounded(.{ .x = tx, .y = ty, .width = tw + 24, .height = 28 }, 0.4, 8, rl.Color.init(50, 50, 70, alpha));
            fonts.drawText(toast_msg, @intFromFloat(tx + 12), @intFromFloat(ty + 6), 16, rl.Color.init(220, 220, 230, alpha));
        }
    }
}

fn handleSelect(
    shapes: *shape_mod.ShapeList,
    is_dragging: *bool,
    drag_start: *rl.Vector2,
    drag_last: *rl.Vector2,
    is_marquee: *bool,
    marquee_start: *rl.Vector2,
    mouse_world: rl.Vector2,
    history: *History,
) void {
    const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);

    if (rl.isMouseButtonPressed(.left)) {
        if (shapes.findAt(mouse_world)) |idx| {
            // Clicked on a shape
            if (shift) {
                // Shift+click: toggle this shape's selection
                shapes.shapes.items[idx].selected = !shapes.shapes.items[idx].selected;
            } else {
                if (!shapes.shapes.items[idx].selected) {
                    shapes.deselectAll();
                    shapes.shapes.items[idx].selected = true;
                }
            }
            // Start dragging all selected shapes
            is_dragging.* = true;
            drag_start.* = mouse_world;
            drag_last.* = mouse_world;
        } else {
            // Clicked on empty space: start marquee selection
            if (!shift) {
                shapes.deselectAll();
            }
            is_marquee.* = true;
            marquee_start.* = mouse_world;
        }
    }

    // Dragging selected shapes
    if (is_dragging.* and rl.isMouseButtonDown(.left)) {
        const dx = mouse_world.x - drag_last.*.x;
        const dy = mouse_world.y - drag_last.*.y;
        shapes.moveSelected(dx, dy);
        drag_last.* = mouse_world;
    }

    if (rl.isMouseButtonReleased(.left) and is_dragging.*) {
        is_dragging.* = false;
        // Only push history if we actually moved
        const dx = mouse_world.x - drag_start.*.x;
        const dy = mouse_world.y - drag_start.*.y;
        if (dx * dx + dy * dy > 1) {
            history.pushState(shapes) catch {};
        }
    }

    // Marquee selection: update while dragging
    if (is_marquee.* and rl.isMouseButtonDown(.left)) {
        // Selection happens on release
    }

    if (rl.isMouseButtonReleased(.left) and is_marquee.*) {
        is_marquee.* = false;
        const sel_rect = normalizeRect(marquee_start.*, mouse_world);
        if (sel_rect.width > 2 or sel_rect.height > 2) {
            shapes.selectInRect(sel_rect);
        }
    }
}

/// Build a normalized rectangle from two corner points.
fn normalizeRect(a: rl.Vector2, b: rl.Vector2) rl.Rectangle {
    return .{
        .x = @min(a.x, b.x),
        .y = @min(a.y, b.y),
        .width = @abs(b.x - a.x),
        .height = @abs(b.y - a.y),
    };
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
        .text => "Text (T)",
    };
    fonts.drawText(tool_name, 10, @intFromFloat(y + 4), 14, tc);

    // Zoom
    var zoom_buf: [32]u8 = undefined;
    const zoom_pct: i32 = @intFromFloat(canvas.zoom * 100);
    const zoom_text = std.fmt.bufPrintZ(&zoom_buf, "{d}%", .{zoom_pct}) catch "?";
    fonts.drawText(zoom_text, @intFromFloat(screen_w / 2 - 30), @intFromFloat(y + 4), 14, tc);

    // Shape count
    var count_buf: [32]u8 = undefined;
    const count_text = std.fmt.bufPrintZ(&count_buf, "{d} shapes", .{shape_count}) catch "?";
    fonts.drawText(count_text, @intFromFloat(screen_w - 120), @intFromFloat(y + 4), 14, tc);
}
