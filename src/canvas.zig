const rl = @import("raylib");
const std = @import("std");

/// Canvas handles pan and zoom for an infinite 2D drawing surface.
pub const Canvas = struct {
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    zoom: f32 = 1.0,
    is_panning: bool = false,
    pan_start: rl.Vector2 = .{ .x = 0, .y = 0 },

    const min_zoom: f32 = 0.1;
    const max_zoom: f32 = 10.0;
    const zoom_speed: f32 = 0.1;

    /// Convert screen coordinates to world (canvas) coordinates.
    pub fn screenToWorld(self: Canvas, screen_pos: rl.Vector2) rl.Vector2 {
        return .{
            .x = (screen_pos.x - self.offset.x) / self.zoom,
            .y = (screen_pos.y - self.offset.y) / self.zoom,
        };
    }

    /// Convert world coordinates to screen coordinates.
    pub fn worldToScreen(self: Canvas, world_pos: rl.Vector2) rl.Vector2 {
        return .{
            .x = world_pos.x * self.zoom + self.offset.x,
            .y = world_pos.y * self.zoom + self.offset.y,
        };
    }

    /// Handle panning (middle mouse or space+left drag) and zooming (scroll wheel).
    pub fn update(self: *Canvas, toolbar_height: f32) void {
        const mouse = rl.getMousePosition();

        // Don't handle canvas input if mouse is in toolbar area
        if (mouse.y < toolbar_height) return;

        // Panning with middle mouse button
        if (rl.isMouseButtonPressed(.middle)) {
            self.is_panning = true;
            self.pan_start = mouse;
        }
        if (rl.isMouseButtonReleased(.middle)) {
            self.is_panning = false;
        }

        // Also pan with space + left mouse
        if (rl.isKeyDown(.space) and rl.isMouseButtonPressed(.left)) {
            self.is_panning = true;
            self.pan_start = mouse;
        }
        if (rl.isKeyDown(.space) and rl.isMouseButtonReleased(.left)) {
            self.is_panning = false;
        }
        if (rl.isKeyReleased(.space)) {
            self.is_panning = false;
        }

        if (self.is_panning) {
            const delta = rl.Vector2{
                .x = mouse.x - self.pan_start.x,
                .y = mouse.y - self.pan_start.y,
            };
            self.offset.x += delta.x;
            self.offset.y += delta.y;
            self.pan_start = mouse;
        }

        // Zooming with scroll wheel (zoom toward mouse cursor)
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const world_before = self.screenToWorld(mouse);
            self.zoom *= if (wheel > 0) (1.0 + zoom_speed) else (1.0 / (1.0 + zoom_speed));
            self.zoom = std.math.clamp(self.zoom, min_zoom, max_zoom);
            const world_after = self.screenToWorld(mouse);

            // Adjust offset so the world point under the cursor stays put
            self.offset.x += (world_after.x - world_before.x) * self.zoom;
            self.offset.y += (world_after.y - world_before.y) * self.zoom;
        }
    }

    /// Push the camera transform for drawing shapes in world space.
    pub fn beginDraw(self: Canvas) void {
        rl.gl.rlPushMatrix();
        rl.gl.rlTranslatef(self.offset.x, self.offset.y, 0);
        rl.gl.rlScalef(self.zoom, self.zoom, 1);
    }

    /// Pop the camera transform.
    pub fn endDraw(_: Canvas) void {
        rl.gl.rlPopMatrix();
    }

    /// Reset view to origin.
    pub fn resetView(self: *Canvas) void {
        self.offset = .{ .x = 0, .y = 0 };
        self.zoom = 1.0;
    }

    /// Zoom to fit a rectangle in the viewport.
    pub fn zoomToFit(self: *Canvas, rect: rl.Rectangle, screen_w: f32, screen_h: f32, toolbar_h: f32) void {
        if (rect.width < 1 or rect.height < 1) return;
        const available_h = screen_h - toolbar_h;
        const margin: f32 = 40;
        const zoom_x = (screen_w - margin * 2) / rect.width;
        const zoom_y = (available_h - margin * 2) / rect.height;
        self.zoom = std.math.clamp(@min(zoom_x, zoom_y), min_zoom, max_zoom);
        self.offset.x = screen_w / 2 - (rect.x + rect.width / 2) * self.zoom;
        self.offset.y = toolbar_h + available_h / 2 - (rect.y + rect.height / 2) * self.zoom;
    }
};
