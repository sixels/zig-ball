const std = @import("std");
const za = @import("zalgebra");

const mem = std.mem;
const print = std.debug.print;
const Vec2 = za.Vec2;

const WIDTH: f32 = 80.0;
const HEIGHT: f32 = 22.0;

const Pixel = enum {
    bg,
    fg,
};

const Ball = struct {
    center: Vec2,
    radius: f32,
    velocity: Vec2,

    pub fn new(center: Vec2, radius: f32, velocity: Vec2) Ball {
        return .{
            .center = center,
            .radius = radius,
            .velocity = velocity,
        };
    }

    pub fn draw(self: Ball) void {
        // find our circle's boundaries
        const radius_vec = Vec2.new(self.radius, self.radius);
        const top_l = self.center.sub(radius_vec);
        const bot_r = self.center.add(radius_vec);

        var y: f32 = @floor(top_l.y);
        while (y < @ceil(bot_r.y)) : (y += 1) {
            if (y < 0 or y > HEIGHT) continue;

            var x: f32 = @floor(top_l.x);
            while (x < @ceil(bot_r.x)) : (x += 1) {
                if (x < 0 or x >= WIDTH) continue;
                // calc the distance between the center and the position
                const pos = Vec2.new(x + 0.5, y + 0.5);
                const d = self.center.sub(pos);
                // check if the distance is inside the circle
                // x^2 + y^2 <= r^2
                if (d.x * d.x + d.y * d.y <= self.radius * self.radius) {
                    screen[@floatToInt(usize, y * WIDTH + x)] = Pixel.fg;
                }
            }
        }
    }
};

const Line = struct {
    start: Vec2,
    end: Vec2,

    angle: f32,
    slope: f32,
    y_intercept: f32,

    pub fn new(start: Vec2, end: Vec2) Line {
        // m = (y-y0)/(x-x0)
        const slope = (end.y - start.y) / (end.x - start.x);
        const angle = std.math.atan(slope);

        // y = m(x-x0) + y0
        const y_intercept = slope * (0 - start.x) + start.y;

        return .{
            .start = start,
            .end = end,
            .slope = slope,
            .angle = angle,
            .y_intercept = y_intercept,
        };
    }

    /// f(x)
    pub fn fx(self: Line, x: f32) ?f32 {
        const leftx = std.math.min(self.end.x, self.start.x);
        const rightx = std.math.max(self.end.x, self.start.x);

        return if (x >= leftx or x <= rightx) self.slope * x + self.y_intercept else undefined;
    }

    pub fn draw(self: Line) void {
        const top_l = Vec2.new(std.math.min(self.end.x, self.start.x), std.math.min(self.end.y, self.start.y));
        const bot_r = Vec2.new(std.math.max(self.end.x, self.start.x), std.math.max(self.end.y, self.start.y));

        const bar_width = 2;

        var y: f32 = @floor(top_l.y);
        while (y < @ceil(bot_r.y)) : (y += 1) {
            if (y < 0 or y >= HEIGHT) continue;

            var x: f32 = @floor(top_l.x);
            while (x < @ceil(bot_r.x)) : (x += 1) {
                if (x < 0 or x >= WIDTH) continue;

                const maybe_fx = self.fx(x);
                if (maybe_fx) |yx| {
                    const pos = yx - y;
                    if (pos >= -bar_width and pos <= 0) {
                        screen[@floatToInt(usize, y * WIDTH + x)] = Pixel.fg;
                    }
                }
            }
        }
    }
};

var screen = comptime mem.zeroes([WIDTH * HEIGHT]Pixel);

/// fills the screen with the given character
pub fn fill(pixel: Pixel) void {
    mem.set(Pixel, &screen, pixel);
}

/// fg the screen state compressing each two rows into a single row
/// as follow:
///
/// | first row | second row | results in |
/// | :-------: | :--------: | :--------: |
/// |     .     |     .      |   <SPACE>  |
/// |     *     |     .      |      ^     |
/// |     .     |     *      |      _     |
/// |     *     |     *      |      S     |
///
///  For instance, if we have
///
/// *.***....*.*
/// .****...*.**
///
///  then, it becomes
///
/// ^_SSS   _^_^
pub fn render() void {
    const char_table = " _^S";

    var y: usize = 0;
    while (y < HEIGHT) : (y += 2) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const top: usize = @enumToInt(screen[(y + 0) * @floatToInt(usize, WIDTH) + x]);
            const bot: usize = @enumToInt(screen[(y + 1) * @floatToInt(usize, WIDTH) + x]);
            // we can safely trust that `top` and `bot` will be either 0 or 1
            const char = char_table[top * 2 + bot];
            print("{c}", .{char});
        }
        print("\n", .{});
    }
}

/// Move the cursor to the start of our screen
pub fn reset_cursor() void {
    print("\x1b[{d}D\x1b[{d}A", .{ WIDTH, HEIGHT / 2 });
}

pub fn terminate() callconv(.C) void {
    print("\x1b[?25h", .{});
}

pub fn main() !void {
    const fps = 30;
    const gravity = Vec2.new(0, 120.0);
    const dt = 1.0 / @intToFloat(f32, fps);

    const radius = HEIGHT / 4;
    const circle_pos = Vec2.new(radius, 0);

    const lb_start = Vec2.new(-radius, radius + 2);
    const lb_end = Vec2.new(WIDTH / 2, HEIGHT);

    const lbar = Line.new(lb_start, lb_end);
    var ball = Ball.new(circle_pos, radius, Vec2.new(0, 0));

    // hide the cursor
    print("\x1b[?25l", .{});
    defer {
        // bring the cursor back
        print("\x1b[?25h", .{});
    }

    std.log.debug("left bar slope: {}", .{lbar.slope});
    while (true) {

        // render the current frame
        fill(Pixel.bg);

        ball.draw();
        lbar.draw();

        render();
        reset_cursor();

        // update the variables
        // V = V0 + g*Δt
        ball.velocity = Vec2.add(ball.velocity, Vec2.scale(gravity, dt));
        // S = S0 + V*Δt
        ball.center = Vec2.add(ball.center, ball.velocity.scale(dt));
        // collide with the ground
        if (ball.center.y >= HEIGHT - ball.radius) {
            ball.center.y = HEIGHT - ball.radius;
            ball.velocity.y *= -0.8;
            ball.velocity.x *= 0.98;
        }

        // collide with the left slope
        {
            const maybe_fx = lbar.fx(ball.center.x);
            if (maybe_fx) |fx| {
                if (ball.center.y >= fx - ball.radius) {
                    ball.center.y = fx - ball.radius;

                    const vx = @sin(lbar.angle) * ball.velocity.y;
                    const vy = -@cos(lbar.angle) * ball.velocity.y * 0.5;
                    ball.velocity = ball.velocity.add(Vec2.new(vx, vy));
                    ball.velocity.x *= 0.99;
                }
            }
        }

        // wait for the next frame
        std.time.sleep(comptime (std.time.ns_per_ms * 1_000 / fps));

        if (ball.center.x > WIDTH + ball.radius + 2) {
            // wait 500 ms to release next ball
            std.time.sleep(comptime (std.time.ns_per_ms * 500));
            ball.center = Vec2.new(ball.radius, 0);
            ball.velocity = Vec2.new(0, 0);
        }
    }
}
