const rl = @import("raylib");

const font_data = @embedFile("JetBrainsMonoNerdFont-Regular");

var loaded_font: ?rl.Font = null;

pub fn get() rl.Font {
    if (loaded_font) |f| return f;
    loaded_font = rl.loadFontFromMemory(".ttf", font_data, 32, null) catch null;
    if (loaded_font) |*f| {
        rl.setTextureFilter(f.texture, .bilinear);
    }
    return loaded_font orelse (rl.getFontDefault() catch unreachable);
}

pub fn drawText(text: [:0]const u8, x: i32, y: i32, size: i32, color: rl.Color) void {
    const font = get();
    const font_size: f32 = @floatFromInt(size);
    rl.drawTextEx(font, text, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, font_size, 1, color);
}

pub fn measureText(text: [:0]const u8, size: i32) i32 {
    const font = get();
    const font_size: f32 = @floatFromInt(size);
    const v = rl.measureTextEx(font, text, font_size, 1);
    return @intFromFloat(v.x);
}
