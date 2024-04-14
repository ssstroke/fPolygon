const std = @import("std");

const s = @cImport({
    @cInclude("SDL.h");
});

const WINDOW_WIDTH = 640;
const WINDOW_HEIGHT = 480;

// TODO: Use `usize` or `u32` and then use @as(c_int, ...) syntax when calling SDL functions.
const Point2D = struct {
    x: u32,
    y: u32,
};

const EdgeTableEntry = struct {
    y_min:          u32,
    y_max:          u32,
    x:              u32, // x of y_min if it's ET (not AET)
    inverse_slope:  f32,
};

fn compareEdgeTableEntryByMinY(_: void, lhs: EdgeTableEntry, rhs: EdgeTableEntry) bool {
    return lhs.y_min > rhs.y_min;
}

fn compareEdgeTableEntryByX(_: void, lhs: EdgeTableEntry, rhs: EdgeTableEntry) bool {
    return lhs.x < rhs.x;
}

fn RemoveEdgesAET(aet: *std.ArrayList(EdgeTableEntry), y: u32) void {
    loop: while (true) {
        for (aet.items, 0..) |item, i| {
            if (item.y_max == y) {
                _ = aet.orderedRemove(i);
                continue :loop;
            }
        }
        break :loop;
    }
}

pub fn main() !void {
    // --------------------
    // -- Initialization --
    // --------------------
    if (s.SDL_Init(s.SDL_INIT_EVERYTHING) != 0) {
        s.SDL_LogError(s.SDL_LOG_CATEGORY_ERROR, "SDL initialization error: %s\n", s.SDL_GetError());
        return error.initError;
    }
    defer s.SDL_Quit();

    const window: *s.SDL_Window = s.SDL_CreateWindow("ZILBERTE", s.SDL_WINDOWPOS_UNDEFINED, s.SDL_WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, s.SDL_WINDOW_SHOWN) orelse {
        s.SDL_LogError(s.SDL_LOG_CATEGORY_ERROR, "Error creating a window: %s\n", s.SDL_GetError());
        return error.windowError;
    };
    defer s.SDL_DestroyWindow(window);

    const renderer: *s.SDL_Renderer = s.SDL_CreateRenderer(window, 0, s.SDL_RENDERER_ACCELERATED) orelse {
        s.SDL_LogError(s.SDL_LOG_CATEGORY_ERROR, "Error creating a renderer: %s\n", s.SDL_GetError());
        return error.rendererError;
    };
    defer s.SDL_DestroyRenderer(renderer);

    // --------------------
    // -- Game loop -------
    // --------------------
    gameloop: while (true) {
        // const time_start: s.Uint64 = s.SDL_GetTicks64();

        // Event processing
        var event: s.SDL_Event = undefined;
        while (s.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                s.SDL_QUIT => {
                    break :gameloop;
                },
                else => {},
            }
        }

        // Draw background
        _ = s.SDL_SetRenderDrawColor(renderer, 0x23, 0xF0, 0xC7, 0xFF); // Is there a way to "squeeze" those colors into one... structure?
        _ = s.SDL_RenderClear(renderer);

        const polygon = [_]Point2D{
            .{.x = 2 * 10, .y = 3 * 10},      // A
            .{.x = 7 * 10, .y = 1 * 10},      // B
            .{.x = 13 * 10, .y = 5 * 10},     // C
            .{.x = 13 * 10, .y = 11 * 10},    // D
            .{.x = 7 * 10, .y = 7 * 10},      // E
            .{.x = 2 * 10, .y = 9 * 10},      // F
        };

        // Draw polygon outline
        _ = s.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
        inline for (0..polygon.len) |i| _ = s.SDL_RenderDrawLine(renderer, polygon[i].x, polygon[i].y, polygon[(i + 1) % polygon.len].x, polygon[(i + 1) % polygon.len].y);
        
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        // Will need it later
        var y: u32 = std.math.maxInt(u32);

        // Create ET
        var et = try std.ArrayList(EdgeTableEntry).initCapacity(allocator, polygon.len);
        defer et.deinit();
        for (0..polygon.len) |i| {
            const A = polygon[i];
            const B = polygon[(i + 1) % polygon.len];

            const entry: EdgeTableEntry = .{
                .y_min = switch (A.y <= B.y) {
                    true => A.y,
                    false => B.y,
                },
                .y_max = switch (A.y > B.y) {
                    true => A.y,
                    false => B.y,
                },
                .x = switch (A.y <= B.y) {
                    true => A.x,
                    false => B.x,
                },
                .inverse_slope = switch (A.x == B.x) {
                    false => ( @as(f32, @floatFromInt(B.x)) - @as(f32, @floatFromInt(A.x)) ) /
                             ( @as(f32, @floatFromInt(B.y)) - @as(f32, @floatFromInt(A.y)) ),
                    true => 0,
                }
            };
            try et.append(entry);

            if (entry.y_min < y) y = entry.y_min;
        }

        std.sort.insertion(EdgeTableEntry, et.items, {}, compareEdgeTableEntryByMinY);

        // Create AET
        var aet = std.ArrayList(EdgeTableEntry).init(allocator);
        defer aet.deinit();

        while (et.items.len != 0 or aet.items.len != 0) {
            std.debug.print("\n", .{});

            // Move ET edges with vertices' whose y_min == y
            while (et.items.len != 0 and et.items[et.items.len - 1].y_min == y)
                try aet.append(et.pop());

            // Sort AET by x
            std.sort.insertion(EdgeTableEntry, aet.items, {}, compareEdgeTableEntryByX);

            for (aet.items) |item| {
                std.debug.print("{}\n", .{item});
            }

            // Fill pixels
            std.debug.print("Drawing pixels...\n", .{});
            _ = s.SDL_SetRenderDrawColor(renderer, 0xEF, 0x76, 0x7A, 0xFF);
            _ = s.SDL_RenderDrawLine(renderer, @intCast(aet.items[0].x), @intCast(y), @intCast(aet.items[1].x), @intCast(y));

            y += 1;

            // Remove AET edges with vertices' whose y_max == y
            std.debug.print("Remove AET edges...\n", .{});
            RemoveEdgesAET(&aet, y);

            // Update x values
            std.debug.print("Update x values...\n", .{});
            for (aet.items) |*item| {
                const x_as_f32: f32 = @as(f32, @floatFromInt(item.x));
                const result: f32 = x_as_f32 + item.inverse_slope;
                const result_as_u32: u32 = @as(u32, @intFromFloat(@round(result)));
                item.x = result_as_u32;
            }

            _ = s.SDL_RenderPresent(renderer);
            s.SDL_Delay(500);
        }        

        // s.SDL_Log("Scene render time (ms): %llu\n", s.SDL_GetTicks64() - time_start);

        // break :gameloop;
    }
}
