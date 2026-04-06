const std = @import("std");
const rl = @import("raylib");
const toolbar_mod = @import("toolbar.zig");
const Theme = toolbar_mod.Theme;

pub const Mode = enum {
    hidden,
    save,
    open,
};

pub const Result = enum {
    none,
    confirmed,
    cancelled,
};

pub const CommandBar = struct {
    mode: Mode = .hidden,
    buf: [1024]u8 = undefined,
    len: usize = 0,
    cursor: usize = 0,
    height: f32 = 28,

    // Tab-completion state
    completions: [64]Completion = undefined,
    completion_count: usize = 0,
    completion_idx: usize = 0,
    completion_active: bool = false,

    const Completion = struct {
        name: [256]u8 = undefined,
        name_len: usize = 0,
        is_dir: bool = false,
    };

    pub fn open(self: *CommandBar, mode: Mode, with_filename: bool) void {
        // Default to home directory
        const home = std.process.getEnvVarOwned(std.heap.page_allocator, "USERPROFILE") catch
            std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch
            ".";
        defer if (!std.mem.eql(u8, home, ".")) std.heap.page_allocator.free(home);

        self.mode = mode;

        // Copy home path, normalising backslashes to forward slashes
        self.len = 0;
        for (home) |c| {
            if (self.len >= self.buf.len - 2) break;
            self.buf[self.len] = if (c == '\\') '/' else c;
            self.len += 1;
        }
        // Ensure trailing slash
        if (self.len > 0 and self.buf[self.len - 1] != '/') {
            self.buf[self.len] = '/';
            self.len += 1;
        }
        // Append default filename for save mode
        if (with_filename) {
            const fname = "drawing.zdraw";
            const flen = @min(fname.len, self.buf.len - self.len);
            @memcpy(self.buf[self.len .. self.len + flen], fname[0..flen]);
            self.len += flen;
        }
        self.cursor = self.len;
        self.completion_active = false;
        self.completion_count = 0;
    }

    pub fn close(self: *CommandBar) void {
        self.mode = .hidden;
        self.completion_active = false;
    }

    pub fn getPath(self: *const CommandBar) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn update(self: *CommandBar) Result {
        if (self.mode == .hidden) return .none;

        // Escape to cancel
        if (rl.isKeyPressed(.escape)) {
            self.close();
            return .cancelled;
        }

        // Enter to confirm
        if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter)) {
            return .confirmed;
        }

        // Tab for completion
        if (rl.isKeyPressed(.tab)) {
            self.tabComplete();
            return .none;
        }

        // Backspace
        if ((rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) and self.cursor > 0) {
            self.deleteChar();
        }

        // Handle text input
        var char = rl.getCharPressed();
        while (char != 0) {
            if (char >= 32 and char < 127) {
                self.insertChar(@intCast(char));
            }
            char = rl.getCharPressed();
        }

        self.completion_active = false;

        return .none;
    }

    fn insertChar(self: *CommandBar, c: u8) void {
        if (self.len >= self.buf.len - 1) return;
        // Shift right from cursor
        if (self.cursor < self.len) {
            std.mem.copyBackwards(u8, self.buf[self.cursor + 1 .. self.len + 1], self.buf[self.cursor..self.len]);
        }
        self.buf[self.cursor] = c;
        self.cursor += 1;
        self.len += 1;
    }

    fn deleteChar(self: *CommandBar) void {
        if (self.cursor == 0) return;
        if (self.cursor < self.len) {
            std.mem.copyForwards(u8, self.buf[self.cursor - 1 .. self.len - 1], self.buf[self.cursor..self.len]);
        }
        self.cursor -= 1;
        self.len -= 1;
    }

    fn tabComplete(self: *CommandBar) void {
        if (self.completion_active and self.completion_count > 0) {
            // Cycle through existing completions
            self.completion_idx = (self.completion_idx + 1) % self.completion_count;
            self.applyCompletion(self.completion_idx);
            return;
        }

        // Build completions list
        self.completion_count = 0;
        self.completion_idx = 0;

        const path = self.getPath();

        // Split into dir and prefix based on the full typed path
        var dir_path: []const u8 = ".";
        var prefix: []const u8 = path;

        if (std.mem.lastIndexOfAny(u8, path, "/\\")) |sep| {
            dir_path = if (sep == 0) "/" else path[0..sep];
            prefix = path[sep + 1 ..];
        }

        // Open the directory from the typed absolute/relative path
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch
            std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        var iter = dir.iterate();

        while (self.completion_count < self.completions.len) {
            const entry = iter.next() catch break;
            if (entry == null) break;
            const e = entry.?;

            // Filter by prefix (case-insensitive)
            if (prefix.len > 0) {
                if (e.name.len < prefix.len) continue;
                var matches = true;
                for (0..prefix.len) |i| {
                    if (std.ascii.toLower(e.name[i]) != std.ascii.toLower(prefix[i])) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
            }

            // For open mode, filter to only .zdraw files and directories
            if (self.mode == .open and e.kind != .directory) {
                if (!std.mem.endsWith(u8, e.name, ".zdraw")) continue;
            }

            var comp = &self.completions[self.completion_count];
            const nlen = @min(e.name.len, comp.name.len);
            @memcpy(comp.name[0..nlen], e.name[0..nlen]);
            comp.name_len = nlen;
            comp.is_dir = (e.kind == .directory);
            self.completion_count += 1;
        }

        if (self.completion_count > 0) {
            self.completion_active = true;
            self.applyCompletion(0);
        }
    }

    fn applyCompletion(self: *CommandBar, idx: usize) void {
        const comp = self.completions[idx];
        const path = self.buf[0..self.len];

        // Find the prefix boundary
        var base_len: usize = 0;
        if (std.mem.lastIndexOfAny(u8, path, "/\\")) |sep| {
            base_len = sep + 1;
        }

        const new_len = base_len + comp.name_len + @as(usize, if (comp.is_dir) 1 else 0);
        if (new_len > self.buf.len) return;

        @memcpy(self.buf[base_len .. base_len + comp.name_len], comp.name[0..comp.name_len]);
        if (comp.is_dir) {
            self.buf[base_len + comp.name_len] = '/';
        }
        self.len = new_len;
        self.cursor = new_len;
    }

    pub fn draw(self: *const CommandBar, screen_w: f32, screen_h: f32, theme: Theme) void {
        if (self.mode == .hidden) return;

        const bar_y = screen_h - self.height - 24; // above the status bar
        const bar_h = self.height;

        // Background
        rl.drawRectangle(0, @intFromFloat(bar_y), @intFromFloat(screen_w), @intFromFloat(bar_h), theme.toolbarBg());
        rl.drawLine(0, @intFromFloat(bar_y), @intFromFloat(screen_w), @intFromFloat(bar_y), theme.toolbarBorder());

        // Prompt
        const prompt: [:0]const u8 = switch (self.mode) {
            .save => "Save: ",
            .open => "Open: ",
            .hidden => "",
        };
        const prompt_w: f32 = @floatFromInt(rl.measureText(prompt, 16));
        rl.drawText(prompt, 8, @intFromFloat(bar_y + 6), 16, theme.btnActive());

        // Path text
        var display_buf: [1025:0]u8 = undefined;
        const path = self.getPath();
        @memcpy(display_buf[0..path.len], path);
        display_buf[path.len] = 0;
        const display: [:0]const u8 = display_buf[0..path.len :0];
        rl.drawText(display, @intFromFloat(8 + prompt_w), @intFromFloat(bar_y + 6), 16, theme.textColor());

        // Cursor (blinking)
        const time: f32 = @floatCast(rl.getTime());
        if (@mod(time, 1.0) < 0.6) {
            // Measure text up to cursor to find cursor x position
            var cursor_buf: [1025:0]u8 = undefined;
            const cursor_text = self.buf[0..self.cursor];
            @memcpy(cursor_buf[0..cursor_text.len], cursor_text);
            cursor_buf[cursor_text.len] = 0;
            const cursor_display: [:0]const u8 = cursor_buf[0..cursor_text.len :0];
            const cursor_x: f32 = 8 + prompt_w + @as(f32, @floatFromInt(rl.measureText(cursor_display, 16)));
            rl.drawRectangle(@intFromFloat(cursor_x), @intFromFloat(bar_y + 5), 2, 18, theme.textColor());
        }

        // Show completion hint
        if (self.completion_active and self.completion_count > 1) {
            var hint_buf: [64:0]u8 = undefined;
            const hint = std.fmt.bufPrintZ(&hint_buf, "({d}/{d}) Tab to cycle", .{ self.completion_idx + 1, self.completion_count }) catch return;
            const hint_w: f32 = @floatFromInt(rl.measureText(hint, 12));
            rl.drawText(hint, @intFromFloat(screen_w - hint_w - 12), @intFromFloat(bar_y + 8), 12, theme.textDimColor());
        }
    }
};
