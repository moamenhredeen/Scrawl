const rl = @import("raylib");
const rg = @import("raygui");
const shape_mod = @import("shape.zig");

pub const Tool = enum {
    select,
    rectangle,
    ellipse,
    line,
    arrow,
    freehand,
    text,
};

pub const ColorPreset = struct {
    color: rl.Color,
    name: []const u8,
};

pub const color_presets = [_]ColorPreset{
    .{ .color = rl.Color.init(255, 255, 255, 255), .name = "White" },
    .{ .color = rl.Color.init(229, 57, 53, 255), .name = "Red" },
    .{ .color = rl.Color.init(67, 160, 71, 255), .name = "Green" },
    .{ .color = rl.Color.init(30, 136, 229, 255), .name = "Blue" },
    .{ .color = rl.Color.init(255, 179, 0, 255), .name = "Yellow" },
    .{ .color = rl.Color.init(142, 36, 170, 255), .name = "Purple" },
    .{ .color = rl.Color.init(255, 109, 0, 255), .name = "Orange" },
    .{ .color = rl.Color.init(0, 200, 200, 255), .name = "Cyan" },
};

pub const stroke_widths = [_]f32{ 1.0, 2.0, 3.0, 5.0, 8.0 };

pub const Theme = enum {
    dark,
    light,

    pub fn bgColor(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(24, 24, 32, 255),
            .light => rl.Color.init(240, 240, 245, 255),
        };
    }

    pub fn gridColor(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(38, 38, 50, 255),
            .light => rl.Color.init(210, 210, 220, 255),
        };
    }

    pub fn toolbarBg(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(35, 35, 45, 255),
            .light => rl.Color.init(225, 225, 232, 255),
        };
    }

    pub fn toolbarBorder(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(60, 60, 80, 255),
            .light => rl.Color.init(180, 180, 195, 255),
        };
    }

    pub fn textColor(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(200, 200, 210, 255),
            .light => rl.Color.init(40, 40, 50, 255),
        };
    }

    pub fn textDimColor(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(100, 100, 110, 255),
            .light => rl.Color.init(160, 160, 170, 255),
        };
    }

    pub fn btnBase(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(50, 50, 65, 255),
            .light => rl.Color.init(210, 212, 222, 255),
        };
    }

    pub fn btnBorder(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(70, 70, 90, 255),
            .light => rl.Color.init(170, 170, 185, 255),
        };
    }

    pub fn btnActive(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(80, 100, 180, 255),
            .light => rl.Color.init(90, 120, 210, 255),
        };
    }

    pub fn statusBarBg(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(30, 30, 40, 255),
            .light => rl.Color.init(220, 220, 228, 255),
        };
    }

    pub fn statusBarText(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(160, 160, 180, 255),
            .light => rl.Color.init(80, 80, 100, 255),
        };
    }

    pub fn swatchHighlight(self: Theme) rl.Color {
        return switch (self) {
            .dark => rl.Color.init(255, 255, 255, 255),
            .light => rl.Color.init(30, 30, 40, 255),
        };
    }
};

pub const Toolbar = struct {
    current_tool: Tool = .select,
    current_color_idx: usize = 0,
    current_stroke_idx: usize = 2,
    height: f32 = 50,
    undo_clicked: bool = false,
    redo_clicked: bool = false,
    theme: Theme = .dark,

    pub fn currentColor(self: Toolbar) rl.Color {
        return color_presets[self.current_color_idx].color;
    }

    pub fn currentStrokeWidth(self: Toolbar) f32 {
        return stroke_widths[self.current_stroke_idx];
    }

    pub fn toolToShapeKind(self: Toolbar) ?shape_mod.ShapeKind {
        return switch (self.current_tool) {
            .select => null,
            .rectangle => .rectangle,
            .ellipse => .ellipse,
            .line => .line,
            .arrow => .arrow,
            .freehand => .freehand,
            .text => .text,
        };
    }

    pub fn draw(self: *Toolbar, screen_width: f32, can_undo: bool, can_redo: bool) void {
        const sw = @as(i32, @intFromFloat(screen_width));
        const h = @as(i32, @intFromFloat(self.height));

        self.undo_clicked = false;
        self.redo_clicked = false;

        const t = self.theme;

        // Background
        rl.drawRectangle(0, 0, sw, h, t.toolbarBg());
        rl.drawLine(0, h, sw, h, t.toolbarBorder());

        // Style overrides for current theme
        rg.setStyle(.default, .{ .control = .text_color_normal }, colorToInt(t.textColor()));
        rg.setStyle(.default, .{ .control = .base_color_normal }, colorToInt(t.btnBase()));
        rg.setStyle(.default, .{ .control = .border_color_normal }, colorToInt(t.btnBorder()));
        rg.setStyle(.default, .{ .control = .base_color_pressed }, colorToInt(t.btnActive()));

        var x: f32 = 8;
        const y: f32 = 8;
        const btn_w: f32 = 34;
        const btn_h: f32 = 34;
        const gap: f32 = 3;

        // Tool buttons
        const tool_labels = [_][:0]const u8{ "Sel", "Rec", "Ell", "Lin", "Arr", "Pen", "Txt" };
        const tools = [_]Tool{ .select, .rectangle, .ellipse, .line, .arrow, .freehand, .text };

        for (tools, 0..) |tool, i| {
            const is_active = self.current_tool == tool;
            if (is_active) {
                rg.setStyle(.default, .{ .control = .base_color_normal }, colorToInt(t.btnActive()));
            }

            if (rg.button(.{ .x = x, .y = y, .width = btn_w, .height = btn_h }, tool_labels[i])) {
                self.current_tool = tool;
            }

            if (is_active) {
                rg.setStyle(.default, .{ .control = .base_color_normal }, colorToInt(t.btnBase()));
            }
            x += btn_w + gap;
        }

        // Separator
        x += 8;
        rl.drawLine(@intFromFloat(x), 4, @intFromFloat(x), h - 4, t.toolbarBorder());
        x += 12;

        // Color swatches
        for (color_presets, 0..) |preset, i| {
            const swatch_rect = rl.Rectangle{ .x = x, .y = y + 2, .width = 28, .height = 28 };
            rl.drawRectangleRec(swatch_rect, preset.color);
            if (i == self.current_color_idx) {
                rl.drawRectangleLinesEx(.{
                    .x = swatch_rect.x - 2,
                    .y = swatch_rect.y - 2,
                    .width = swatch_rect.width + 4,
                    .height = swatch_rect.height + 4,
                }, 2, t.swatchHighlight());
            }
            // Click detection
            if (rl.isMouseButtonPressed(.left)) {
                const mouse = rl.getMousePosition();
                if (rl.checkCollisionPointRec(mouse, swatch_rect)) {
                    self.current_color_idx = i;
                }
            }
            x += 32;
        }

        // Separator
        x += 8;
        rl.drawLine(@intFromFloat(x), 4, @intFromFloat(x), h - 4, t.toolbarBorder());
        x += 12;

        // Stroke width buttons
        for (stroke_widths, 0..) |sw_val, i| {
            const is_active = self.current_stroke_idx == i;
            if (is_active) {
                rg.setStyle(.default, .{ .control = .base_color_normal }, colorToInt(t.btnActive()));
            }

            const label: [:0]const u8 = switch (i) {
                0 => "1",
                1 => "2",
                2 => "3",
                3 => "5",
                4 => "8",
                else => "?",
            };
            _ = sw_val;

            if (rg.button(.{ .x = x, .y = y, .width = btn_w, .height = btn_h }, label)) {
                self.current_stroke_idx = i;
            }

            if (is_active) {
                rg.setStyle(.default, .{ .control = .base_color_normal }, colorToInt(t.btnBase()));
            }
            x += btn_w + gap;
        }

        // Separator
        x += 8;
        rl.drawLine(@intFromFloat(x), 4, @intFromFloat(x), h - 4, t.toolbarBorder());
        x += 12;

        // Undo / Redo buttons
        {
            if (!can_undo) {
                rg.setStyle(.default, .{ .control = .text_color_normal }, colorToInt(t.textDimColor()));
            }
            if (rg.button(.{ .x = x, .y = y, .width = btn_w + 10, .height = btn_h }, "Undo") and can_undo) {
                self.undo_clicked = true;
            }
            rg.setStyle(.default, .{ .control = .text_color_normal }, colorToInt(t.textColor()));
            x += btn_w + 10 + gap;

            if (!can_redo) {
                rg.setStyle(.default, .{ .control = .text_color_normal }, colorToInt(t.textDimColor()));
            }
            if (rg.button(.{ .x = x, .y = y, .width = btn_w + 10, .height = btn_h }, "Redo") and can_redo) {
                self.redo_clicked = true;
            }
            rg.setStyle(.default, .{ .control = .text_color_normal }, colorToInt(t.textColor()));
            x += btn_w + 10 + gap;
        }

        // Separator
        x += 8;
        rl.drawLine(@intFromFloat(x), 4, @intFromFloat(x), h - 4, t.toolbarBorder());
        x += 12;

        // Theme toggle button
        {
            const theme_label: [:0]const u8 = switch (self.theme) {
                .dark => "Light",
                .light => "Dark",
            };
            if (rg.button(.{ .x = x, .y = y, .width = btn_w + 16, .height = btn_h }, theme_label)) {
                self.theme = switch (self.theme) {
                    .dark => .light,
                    .light => .dark,
                };
            }
        }
    }

    /// Handle keyboard shortcuts for tool selection
    pub fn handleShortcuts(self: *Toolbar) void {
        if (rl.isKeyPressed(.v) or rl.isKeyPressed(.one)) self.current_tool = .select;
        if (rl.isKeyPressed(.r) or rl.isKeyPressed(.two)) self.current_tool = .rectangle;
        if (rl.isKeyPressed(.o) or rl.isKeyPressed(.three)) self.current_tool = .ellipse;
        if (rl.isKeyPressed(.l) or rl.isKeyPressed(.four)) self.current_tool = .line;
        if (rl.isKeyPressed(.a) or rl.isKeyPressed(.five)) self.current_tool = .arrow;
        if (rl.isKeyPressed(.p) or rl.isKeyPressed(.six)) self.current_tool = .freehand;
        if (rl.isKeyPressed(.t) or rl.isKeyPressed(.seven)) self.current_tool = .text;
    }

    fn colorToInt(c: rl.Color) i32 {
        return @bitCast([4]u8{ c.a, c.b, c.g, c.r });
    }
};
