const std = @import("std");

const s = @cImport({
    @cInclude("SDL.h");
});

const WINDOW_WIDTH  = 640;
const WINDOW_HEIGHT = 480;

const Point2D = struct {
    x: u16,
    y: u16,
};

const EdgeTableEntry = struct {
    y_min:          u16,
    y_max:          u16,
    x:              f32, // x of y_min if it's ET (not AET)
    inverse_slope:  f32,
};

// Greater than
fn compareEdgeTableEntryByMinY(_: void, lhs: EdgeTableEntry, rhs: EdgeTableEntry) bool {
    return lhs.y_min > rhs.y_min;
}

// Less than
fn compareEdgeTableEntryByX(_: void, lhs: EdgeTableEntry, rhs: EdgeTableEntry) bool {
    return lhs.x < rhs.x;
}

fn RemoveEdgesAET(aet: *std.ArrayList(EdgeTableEntry), y: u16) void {
    loop: while (true) {
        for (aet.items, 0..) |item, i| if (item.y_max == y) {
            _ = aet.orderedRemove(i);
            continue :loop;
        };
        break :loop;
    }
}

pub fn main() !void {
    if (s.SDL_Init(s.SDL_INIT_EVERYTHING) != 0) {
        s.SDL_LogError(s.SDL_LOG_CATEGORY_ERROR, "SDL initialization error: %s\n", s.SDL_GetError());
        return error.initError;
    }
    defer s.SDL_Quit();

    const window: *s.SDL_Window = s.SDL_CreateWindow("ZILBERTE",
                                                     s.SDL_WINDOWPOS_UNDEFINED, s.SDL_WINDOWPOS_UNDEFINED,
                                                     WINDOW_WIDTH, WINDOW_HEIGHT, s.SDL_WINDOW_SHOWN) orelse {
        s.SDL_LogError(s.SDL_LOG_CATEGORY_ERROR, "Error creating a window: %s\n", s.SDL_GetError());
        return error.windowError;
    };
    defer s.SDL_DestroyWindow(window);

    const renderer: *s.SDL_Renderer = s.SDL_CreateRenderer(window, 0, s.SDL_RENDERER_ACCELERATED) orelse {
        s.SDL_LogError(s.SDL_LOG_CATEGORY_ERROR, "Error creating a renderer: %s\n", s.SDL_GetError());
        return error.rendererError;
    };
    defer s.SDL_DestroyRenderer(renderer);

    gameloop: while (true) {
        const time_start: s.Uint64 = s.SDL_GetTicks64();

        // Event processing
        var event: s.SDL_Event = undefined;
        while (s.SDL_PollEvent(&event) != 0) switch (event.type) {
            s.SDL_QUIT => break :gameloop,
            else => {},
        };

        // Draw background
        _ = s.SDL_SetRenderDrawColor(renderer, 0x23, 0xF0, 0xC7, 0xFF); // Is there a way to "squeeze" those colors into one... structure?
        _ = s.SDL_RenderClear(renderer);

        var polygon = [_]Point2D{
            .{ .x = 2,  .y = 5  },
            .{ .x = 7,  .y = 2  },
            .{ .x = 8,  .y = 4  },
            .{ .x = 10, .y = 1  },
            .{ .x = 12, .y = 7  },
            .{ .x = 16, .y = 10 },
            .{ .x = 18, .y = 6  },
            .{ .x = 20, .y = 12 },
            .{ .x = 6,  .y = 14 },
            .{ .x = 2,  .y = 11 },
        };
        for (&polygon) |*point| {
            point.x *= 20;
            point.y *= 20;
        }

        // Draw polygon outline
        _ = s.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
        inline for (0..polygon.len) |i|
            _ = s.SDL_RenderDrawLine(renderer,
                                     @as(c_int, polygon[i].x), polygon[i].y,
                                     @as(c_int, polygon[(i + 1) % polygon.len].x), polygon[(i + 1) % polygon.len].y);
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        const allocator = gpa.allocator();

        // Create ET
        var et = try std.ArrayList(EdgeTableEntry).initCapacity(allocator, polygon.len);
        defer et.deinit();

        for (0..polygon.len) |i| {
            const A = polygon[i];
            const B = polygon[(i + 1) % polygon.len];

            const entry: EdgeTableEntry = .{
                .y_min = switch (A.y <= B.y) {
                    true  => A.y,
                    false => B.y,
                },
                .y_max = switch (A.y > B.y) {
                    true  => A.y,
                    false => B.y,
                },
                .x = switch (A.y <= B.y) {
                    true  => @as(f32, @floatFromInt(A.x)),
                    false => @as(f32, @floatFromInt(B.x)),
                },
                .inverse_slope = switch (A.x == B.x) {
                    false => ( @as(f32, @floatFromInt(A.x)) - @as(f32, @floatFromInt(B.x)) ) /
                             ( @as(f32, @floatFromInt(A.y)) - @as(f32, @floatFromInt(B.y)) ),
                    true  => 0,
                }
            };
            
            try et.append(entry);
        }

        std.sort.insertion(EdgeTableEntry, et.items, {}, compareEdgeTableEntryByMinY);

        var y = et.items[et.items.len - 1].y_min;

        var aet = std.ArrayList(EdgeTableEntry).init(allocator);
        defer aet.deinit();

        while (et.items.len != 0 or aet.items.len != 0) {
            // Move edges in ET with Ymin = y into AET
            while (et.items.len != 0 and et.items[et.items.len - 1].y_min == y)
                try aet.append(et.pop());

            // Sort AET on X
            std.sort.insertion(EdgeTableEntry, aet.items, {}, compareEdgeTableEntryByX);
            
            // Draw pixels
            var inside = false;
            var x1: f32 = undefined;
            var x2: f32 = undefined;
            for (aet.items) |edge| {
                switch (inside) {
                    false => x1 = edge.x,
                    true  => x2 = edge.x,
                }
                
                inside = !inside;

                if (!inside) {
                    const x1_ceiled = @as(c_int, @intFromFloat(@ceil(x1)));
                    const x2_floored = @as(c_int, @intFromFloat(@floor(x2)));
                    _ = s.SDL_RenderDrawLine(renderer, x1_ceiled, y, x2_floored, y);
                }
            }

            y += 1;
            RemoveEdgesAET(&aet, y);

            // Update x values
            for (aet.items) |*item|
                item.x += item.inverse_slope;

            _ = s.SDL_SetRenderDrawColor(renderer, 0xEF, 0x76, 0x7A, 0xFF);
            s.SDL_RenderPresent(renderer);

            s.SDL_Delay(50);
        }

        s.SDL_Log("Scene render time (ms): %llu\n", s.SDL_GetTicks64() - time_start);

        break :gameloop;
    }
}
