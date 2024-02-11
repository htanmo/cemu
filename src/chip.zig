const std = @import("std");
const cstd = @cImport(@cInclude("stdlib.h"));
const time = @cImport(@cInclude("time.h"));

opcode: u16,
memory: [4096]u8,
graphics: [64 * 32]u8,
registers: [16]u8,
index: u16,
program_counter: u16,

delay_timer: u8,
sound_timer: u8,

stack: [16]u16,
sp: u16,

keys: [16]u8,

// zig fmt: off
const chip8_fontset = [_]u8
{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
};
// zig fmt: on

const Self = @This();

pub fn init(self: *Self) void {
    cstd.srand(@intCast(time.time(0))); // srand(time(NULL));

    self.program_counter = 0x200;
    self.opcode = 0;
    self.index = 0;
    self.sp = 0;
    self.delay_timer = 0;
    self.sound_timer = 0;

    for (&self.graphics) |*x| {
        x.* = 0;
    }
    for (&self.memory) |*x| {
        x.* = 0;
    }
    for (&self.stack) |*x| {
        x.* = 0;
    }
    for (&self.registers) |*x| {
        x.* = 0;
    }
    for (&self.keys) |*x| {
        x.* = 0;
    }
    for (chip8_fontset, 0..) |c, idx| {
        self.memory[idx] = c;
    }
}

fn increment_pc(self: *Self) void {
    self.program_counter += 2;
}

pub fn cycle(self: *Self) void {
    self.opcode = @as(u16, @intCast(self.memory[self.program_counter])) << 8 | self.memory[self.program_counter + 1];

    //X000
    const first = self.opcode >> 12;

    switch (first) {
        0x0 => {
            if (self.opcode == 0x00E0) {
                for (&self.graphics) |*pixel| {
                    pixel.* = 0;
                }
            } else if (self.opcode == 0x00EE) {
                self.program_counter = self.stack[self.sp];
                self.sp -= 1;
            }
            self.increment_pc();
        },
        0x1 => {
            self.program_counter = self.opcode & 0x0FFF;
        },
        0x2 => {
            self.stack[self.sp] = self.program_counter;
            self.sp += 1;
            self.program_counter = self.opcode & 0x0FFF;
        },
        0x3 => {
            const x = (self.opcode & 0x0F00) >> 8;

            if (self.registers[x] == self.opcode & 0x00FF) {
                self.increment_pc();
            }
            self.increment_pc();
        },
        0x4 => {
            const x = (self.opcode & 0x0F00) >> 8;

            if (self.registers[x] != self.opcode & 0x00FF) {
                self.increment_pc();
            }
            self.increment_pc();
        },
        0x5 => {
            const x = (self.opcode & 0x0F00) >> 8;
            const y = (self.opcode & 0x00F0) >> 4;

            if (self.registers[x] == self.registers[y]) {
                self.increment_pc();
            }
            self.increment_pc();
        },
        0x6 => {
            const x = (self.opcode & 0x0F00) >> 8;
            self.registers[x] = @truncate(self.opcode & 0x00FF);
            self.increment_pc();
        },
        0x7 => {
            @setRuntimeSafety(false);
            const x = (self.opcode & 0x0F00) >> 8;
            self.registers[x] += @truncate(self.opcode & 0x00FF);
            self.increment_pc();
        },
        0x8 => {
            const x = (self.opcode & 0x0F00) >> 8;
            const y = (self.opcode & 0x00F0) >> 4;
            const m = self.opcode & 0x000F;

            switch (m) {
                0 => self.registers[x] = self.registers[y],
                1 => self.registers[x] |= self.registers[y],
                2 => self.registers[x] &= self.registers[y],
                3 => self.registers[x] ^= self.registers[y],
                4 => {
                    @setRuntimeSafety(false);
                    var sum: u16 = self.registers[x];
                    sum += self.registers[y];

                    self.registers[0xF] = if (sum > 255) 1 else 0;
                    self.registers[x] = @truncate(sum & 0x00FF);
                },
                5 => {
                    @setRuntimeSafety(false);
                    self.registers[0xF] = if (self.registers[x] > self.registers[y]) 1 else 0;
                    self.registers[x] = self.registers[y] - self.registers[x];
                },
                6 => {
                    self.registers[0xF] = self.registers[x] & 1;
                    self.registers[x] >>= 1;
                },
                7 => {
                    @setRuntimeSafety(false);
                    self.registers[0xF] = if (self.registers[y] > self.registers[x]) 1 else 0;
                    self.registers[x] = self.registers[y] - self.registers[x];
                },
                14 => {
                    self.registers[0xF] = if (self.registers[x] & 0x80 != 0) 1 else 0;
                    self.registers[x] <<= 1;
                },
                else => {},
            }

            self.increment_pc();
        },
        0x9 => {
            const x = (self.opcode & 0x0F00) >> 8;
            const y = (self.opcode & 0x00F0) >> 4;

            if (self.registers[x] != self.registers[y]) {
                self.increment_pc();
            }
            self.increment_pc();
        },
        0xA => {
            self.index = self.opcode & 0x0FFF;
            self.increment_pc();
        },
        0xB => {
            self.program_counter = (self.opcode & 0x0FFF) + @as(u16, @intCast(self.registers[0]));
        },
        0xC => {
            const x = (self.opcode & 0x0F00) >> 8;
            const kk = self.opcode & 0x00FF;

            self.registers[x] = @truncate(@as(u8, @intCast(cstd.rand())) & kk);
            self.increment_pc();
        },
        0xD => {
            self.registers[0xF] = 0;

            const xx = (self.opcode & 0x0F00) >> 8;
            const yy = (self.opcode & 0x00F0) >> 4;
            const nn = self.opcode & 0x000F;

            const regX = self.registers[xx];
            const regY = self.registers[yy];

            var y: usize = 0;
            while (y < nn) : (y += 1) {
                const pixel = self.memory[self.index + y];

                var x: usize = 0;
                while (x < 8) : (x += 1) {
                    const msb: u8 = 0x80;

                    // 0b01010101
                    if (pixel & (msb >> @intCast(x)) != 0) {
                        const tX = (regX + x) % 64;
                        const tY = (regY + y) % 32;

                        const idx = tX + tY * 64;

                        self.graphics[idx] ^= 1;

                        if (self.graphics[idx] == 0) {
                            self.registers[0xF] = 1;
                        }
                    }
                }
            }
            self.increment_pc();
        },
        0xE => {
            const x = (self.opcode & 0x0F00) >> 8;
            const kk = self.opcode & 0x00FF;

            if (kk == 0x9E) {
                if (self.keys[self.registers[x]] == 1) {
                    self.increment_pc();
                }
            } else if (kk == 0xA1) {
                if (self.keys[self.registers[x]] != 1) {
                    self.increment_pc();
                }
            }
            self.increment_pc();
        },
        0xF => {
            const x = (self.opcode & 0x0F00) >> 8;
            const kk = self.opcode & 0x00FF;

            if (kk == 0x07) {
                self.registers[x] = self.delay_timer;
            } else if (kk == 0x0A) {
                var key_pressed = false;

                for (self.keys, 0..) |v, idx| {
                    if (v != 0) {
                        self.registers[x] = @truncate(idx);
                        key_pressed = true;
                        break;
                    }
                }

                if (!key_pressed)
                    return;
            } else if (kk == 0x15) {
                self.delay_timer = self.registers[x];
            } else if (kk == 0x18) {
                self.sound_timer = self.registers[x];
            } else if (kk == 0x1E) {
                self.index += self.registers[x];
            } else if (kk == 0x29) {
                if (self.registers[x] < 16) {
                    self.index = self.registers[x] * 0x5;
                }
            } else if (kk == 0x33) {
                self.memory[self.index] = self.registers[x] / 100;
                self.memory[self.index + 1] = (self.registers[x] / 10) % 10;
                self.memory[self.index + 2] = self.registers[x] % 10;
            } else if (kk == 0x55) {
                var i: usize = 0;
                while (i <= x) : (i += 1) {
                    self.memory[self.index + i] = self.registers[i];
                }
            } else if (kk == 0x65) {
                var i: usize = 0;
                while (i <= x) : (i += 1) {
                    self.registers[i] = self.memory[self.index + i];
                }
            }
            self.increment_pc();
        },
        else => {},
    }

    if (self.delay_timer > 0) {
        self.delay_timer -= 1;
    }
    if (self.sound_timer > 0) {
        self.sound_timer -= 1;
    }
}
