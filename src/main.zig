const std = @import("std");
const sdl = @import("sdl.zig");
const CHIP8 = @import("chip.zig");
const process = std.process;

var window: ?*sdl.SDL_Window = null;
var renderer: ?*sdl.SDL_Renderer = null;
var texture: ?*sdl.SDL_Texture = null;

var cpu: *CHIP8 = undefined;

const keymap: [16]c_int = [_]c_int{
    sdl.SDL_SCANCODE_X,
    sdl.SDL_SCANCODE_1,
    sdl.SDL_SCANCODE_2,
    sdl.SDL_SCANCODE_3,
    sdl.SDL_SCANCODE_Q,
    sdl.SDL_SCANCODE_W,
    sdl.SDL_SCANCODE_E,
    sdl.SDL_SCANCODE_A,
    sdl.SDL_SCANCODE_S,
    sdl.SDL_SCANCODE_D,
    sdl.SDL_SCANCODE_Z,
    sdl.SDL_SCANCODE_C,
    sdl.SDL_SCANCODE_4,
    sdl.SDL_SCANCODE_R,
    sdl.SDL_SCANCODE_F,
    sdl.SDL_SCANCODE_V,
};

pub fn init() !void {
    // zig fmt: off
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) < 0)
        @panic("SDL Initialization Failed!");

    window = sdl.SDL_CreateWindow(
        "CHIP8",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        1024,
        512,
        0
    );

    renderer = sdl.SDL_CreateRenderer(window, -1, 0);

    if (renderer == null)
        @panic("SDL Renderer Initialization Failed!");

    texture = sdl.SDL_CreateTexture(
        renderer,
        sdl.SDL_PIXELFORMAT_RGBX8888,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        64,
        32
    );

    if (texture == null)
        @panic("SDL Texture Creation Failed!");
    // zig fmt: on
}

pub fn deinit() void {
    sdl.SDL_DestroyWindow(window);
    sdl.SDL_Quit();
}

pub fn loadROM(filename: []const u8) !void {
    var inputFile = try std.fs.cwd().openFile(filename, .{});
    defer inputFile.close();

    const size = try inputFile.getEndPos();
    var reader = inputFile.reader();

    var i: usize = 0;
    while (i < size) : (i += 1) {
        cpu.memory[i + 0x200] = try reader.readByte();
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    cpu = try allocator.create(CHIP8);
    cpu.init();

    var args = try process.argsWithAllocator(allocator);
    _ = args.skip();

    const filename = args.next() orelse {
        std.debug.print("No ROM given!\n", .{});
        return;
    };

    try loadROM(filename);

    try init();
    defer deinit();

    var running = true;
    while (running) {
        cpu.cycle();

        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e) > 0) {
            switch (e.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    var i: usize = 0;
                    while (i < 16) : (i += 1) {
                        if (e.key.keysym.scancode == keymap[i]) {
                            cpu.keys[i] = 1;
                        }
                    }
                },
                sdl.SDL_KEYUP => {
                    var i: usize = 0;
                    while (i < 16) : (i += 1) {
                        if (e.key.keysym.scancode == keymap[i]) {
                            cpu.keys[i] = 0;
                        }
                    }
                },
                else => {},
            }
        }

        _ = sdl.SDL_RenderClear(renderer);

        var bytes: ?[*]u32 = null;
        var pitch: c_int = 0;

        // _ = sdl.SDL_LockTexture(texture, null, @ptrCast([*c]?*anyopaque, &bytes), &pitch);
        _ = sdl.SDL_LockTexture(texture, null, @ptrCast(&bytes), &pitch);

        for (cpu.graphics, 0..) |g, idx| {
            bytes.?[idx] = if (g == 1) 0xFFFFFFFF else 0x000000FF;
        }

        sdl.SDL_UnlockTexture(texture);

        _ = sdl.SDL_RenderCopy(renderer, texture, null, null);
        _ = sdl.SDL_RenderPresent(renderer);

        std.time.sleep(16 * 1000 * 1000);
    }
}
