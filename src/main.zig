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
    y_min:          c_int,
    y_max:          c_int,
    x_of_y_min:     c_int,
    inverse_slope:  f32,
};

fn compareEdgeTableEntryByMinY(_: void, lhs: EdgeTableEntry, rhs: EdgeTableEntry) bool {
    return lhs.y_min < rhs.y_min;
}

fn compareEdgeTableEntryByX(_: void, lhs: EdgeTableEntry, rhs: EdgeTableEntry) bool {
    return lhs.x_of_y_min < rhs.x_of_y_min;
}

fn getPolygonMinY(polygon: []const Point2D) u32 {
    var y: u32 = std.math.maxInt(u32);
    for (polygon) |vertex| {
        if (vertex.y < y) y = vertex.y;
    }
    return y;
}

fn getPolygonMaxY(polygon: []const Point2D) u32 {
    var y: u32 = std.math.minInt(u32);
    for (polygon) |vertex| {
        if (vertex.y > y) y = vertex.y;
    }
    return y;
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
        std.debug.print("\n", .{});

        const time_start: s.Uint64 = s.SDL_GetTicks64();

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
            .{.x = 2, .y = 3},      // A
            .{.x = 7, .y = 1},      // B
            .{.x = 13, .y = 5},     // C
            .{.x = 13, .y = 11},    // D
            .{.x = 7, .y = 7},      // E
            .{.x = 2, .y = 9},      // F
        };

        // Draw polygon outline
        _ = s.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xFF);
        inline for (0..polygon.len) |i| _ = s.SDL_RenderDrawLine(renderer, polygon[i].x, polygon[i].y, polygon[(i + 1) % polygon.len].x, polygon[(i + 1) % polygon.len].y);

        // Create "Edge Table (ET)"
        var edge_table: [polygon.len]EdgeTableEntry = undefined;
        inline for (0..polygon.len) |i| {
            const A = &polygon[i % polygon.len];
            const B = &polygon[(i + 1) % polygon.len];

            if (A.y <= B.y) {
                edge_table[i % polygon.len].y_min = A.y;
                edge_table[i % polygon.len].y_max = B.y;
                edge_table[i % polygon.len].x_of_y_min = A.x;
                edge_table[i % polygon.len].inverse_slope = switch (A.x == B.x) {
                    true => 0,
                    false => 1.0 / @as(f32, ( @as(f32, (@as(f32, A.y) - @as(f32, B.y))) / @as(f32, (@as(f32, A.x) - @as(f32, B.x))) )),
                };
            } else {
                edge_table[i % polygon.len].y_min = B.y;
                edge_table[i % polygon.len].y_max = A.y;
                edge_table[i % polygon.len].x_of_y_min = B.x;
                edge_table[i % polygon.len].inverse_slope = switch (A.x == B.x) {
                    true => 0,
                    false => 1.0 / @as(f32, ( @as(f32, (@as(f32, A.y) - @as(f32, B.y))) / @as(f32, (@as(f32, A.x) - @as(f32, B.x))) )),
                };
            }
        }

        // Sort ET by `y_min` field
        std.sort.insertion(EdgeTableEntry, &edge_table, {}, compareEdgeTableEntryByMinY);
        for (edge_table) |i| std.debug.print("({d}, {d}, {d}, {d})\n", .{i.y_min, i.y_max, i.x_of_y_min, i.inverse_slope});

        // Get min and max y values
        const y_min = getPolygonMinY(&polygon);
        const y_max = getPolygonMaxY(&polygon);
        std.debug.print("y_min = {d}, y_max = {d}\n", .{y_min, y_max});

        // Create "Active Edge Table (AET)"
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};

        // This causes segfault. Probably must be a global variable or something.
        // _ = gpa.deinit();

        const allocator = gpa.allocator();

        // Do not deinit() because toOwnedSlice()
        var aet_list = std.ArrayList(EdgeTableEntry).init(allocator);
        aet_list.deinit();

        // Main loop
        for (y_min..y_max + 1) |y| {
            // Move any edges from the ET to the AET where y = y_min
            for (edge_table) |edge| {
                if (edge.y_min == y) try aet_list.append(edge);
            }
            std.debug.print("AET before:\t{any}\n", .{aet_list.items});

            // This gives slice, which is (kinda like?) array pointer
            var aet_slice = aet_list.items;

            // Sort AET by x field
            std.sort.insertion(EdgeTableEntry, aet_slice, {}, compareEdgeTableEntryByX);
            std.debug.print("AET after:\t{any}\n", .{aet_list.items});

            // Fill current line using pairs of x coordinates from AET
            std.debug.print("Imagine filling...\n", .{});

            // std.debug.print("Waiting for 8192 ms now...\n", .{});
            // s.SDL_Delay(8192);
        }
        
        _ = s.SDL_SetRenderDrawColor(renderer, 0xEF, 0x76, 0x7A, 0xFF);

        _ = s.SDL_RenderPresent(renderer);

        s.SDL_Log("Scene render time (ms): %llu\n", s.SDL_GetTicks64() - time_start);

        break :gameloop;
    }
}
