const std = @import("std");

const UnitDescription = struct {
    factor: f64,
    name: []const u8,
    base: bool = false,
};

pub fn Ratio(comptime N: type, comptime D: type) type {
    return struct {
        const Self = @This();
        num: N,
        denom: D,

        pub fn init(numerator: N, denominator: D) Self {
            return normalize(Self{ .num = numerator, .denom = denominator });
        }

        pub fn normalize(self: Self) Self {
            var num = N{
                .value = self.num.value / self.denom.value,
                .tag = self.num.tag,
            };
            return .{
                .num = num.convertReasonable(),
                .denom = .{ .value = 1, .tag = self.denom.tag },
            };
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            try writer.print("{}/{s}", .{ self.num, self.denom.name() });
        }
    };
}

pub fn Unit(comptime Variant: type, comptime rules: anytype) type {
    const arr = std.enums.directEnumArray(Variant, UnitDescription, 0, rules);
    return struct {
        pub const V = Variant;
        const Self = @This();

        pub const U = struct {
            value: f64,
            tag: Variant,

            pub fn name(self: U) []const u8 {
                return arr[@enumToInt(self.tag)].name;
            }
            pub fn format(
                self: U,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;

                try writer.print("{d:.2}{s}", .{ self.value, self.name() });
            }

            pub fn convert(from: U, to: Variant) U {
                return Self.convert(from, to);
            }
            pub fn convertReasonable(from: U) U {
                return Self.convertReasonable(from);
            }
        };

        pub fn convert(from: U, to: Variant) U {
            var move = @intCast(isize, @enumToInt(to)) - @intCast(isize, @enumToInt(from.tag));

            var tmp = from.value;
            // std.log.warn("move: {}", .{move});
            if (move > 0) {
                var i: usize = 0;
                while (i < move) : (i += 1) {
                    tmp /= arr[@intCast(usize, @enumToInt(from.tag)) + i + 1].factor;
                }
            } else {
                var i: isize = move;
                while (i < 0) : (i += 1) {
                    tmp *= arr[@intCast(usize, @enumToInt(from.tag) + i + 1)].factor;
                }
            }

            return .{
                .value = tmp,
                .tag = to,
            };
        }

        pub fn convertReasonable(from: U) U {
            var current = from;
            const num_fields = @typeInfo(Variant).Enum.fields.len - 1;
            while (true) {
                // std.log.warn("current: {}", .{current});
                if (@enumToInt(current.tag) < num_fields) {
                    var next = arr[@intCast(usize, @enumToInt(current.tag)) + 1].factor;
                    if (current.value > next) {
                        current = convert(current, @intToEnum(Variant, @enumToInt(current.tag) + 1));
                        continue;
                    }
                }
                if (@enumToInt(current.tag) > 0) {
                    // std.log.warn(
                    // "current: {} prev: {} t: {}",
                    // .{ current.value, prev, current.value < prev },
                    // );
                    if (current.value < 1) {
                        current = convert(current, @intToEnum(Variant, @enumToInt(current.tag) - 1));
                        continue;
                    }
                }
                break;
            }
            return current;
        }
    };
}

test "conversion tests" {
    var seconds = Second.U{ .tag = .seconds, .value = 100 };
    var millis = Second.convert(seconds, .milliseconds);
    var micros = Second.convert(seconds, .microseconds);
    var nanos = Second.convert(seconds, .nanoseconds);

    try std.testing.expectEqual(@floatCast(f64, 1e5), millis.value);
    try std.testing.expectEqual(@floatCast(f64, 1e8), micros.value);
    try std.testing.expectEqual(@floatCast(f64, 1e11), nanos.value);
    try std.testing.expectEqual(
        @floatCast(f64, 100),
        Second.convert(micros, .seconds).value,
    );

    nanos = Second.U{ .tag = .nanoseconds, .value = 1.45e9 };
    micros = Second.convert(nanos, .microseconds);
    try std.testing.expectEqual(@floatCast(f64, 1.45e6), micros.value);
}

test "convert reasonable" {
    var millis = Second.U{ .tag = .milliseconds, .value = 1.9e6 };
    var conv = Second.convertReasonable(millis);

    try std.testing.expectEqual(@floatCast(f64, 1.9e3), conv.value);
    try std.testing.expectEqual(Second.V.seconds, conv.tag);

    var gbs = Byte.U{ .tag = .gigabyte, .value = 7.03e1 };
    var conv2 = Byte.convertReasonable(gbs);

    try std.testing.expectEqual(@floatCast(f64, 7.03e1), conv2.value);
    try std.testing.expectEqual(Byte.V.gigabyte, conv2.tag);
}

pub const Second = Unit(enum {
    nanoseconds,
    microseconds,
    milliseconds,
    seconds,
}, .{
    .nanoseconds = .{ .factor = 1, .name = "ns" },
    .microseconds = .{ .factor = 1000, .name = "μs" },
    .milliseconds = .{ .factor = 1000, .name = "ms" },
    .seconds = .{ .factor = 1000, .name = "s" },
});

pub const Byte = Unit(enum {
    byte,
    kilobyte,
    megabyte,
    gigabyte,
    terabyte,
}, .{
    .byte = .{ .factor = 1, .name = "b" },
    .kilobyte = .{ .factor = 1000, .name = "kb" },
    .megabyte = .{ .factor = 1000, .name = "mb" },
    .gigabyte = .{ .factor = 1000, .name = "gb" },
    .terabyte = .{ .factor = 1000, .name = "tb" },
});

pub const Harness = struct {
    pub const Case = struct {
        bytes: u64 = 0,
        nanoseconds: u64 = 0,
        name: []const u8,
    };

    pub const Helper = struct {
        case: *Case,

        pub fn addBytes(self: *Helper, b: u64) void {
            self.case.bytes += b;
        }
    };
    const Runner = fn (h: *Helper) anyerror!void;

    cases: std.ArrayList(Case),
    alloc: std.mem.Allocator,
    name: []const u8,

    pub fn init(alloc: std.mem.Allocator, name: []const u8) Harness {
        return .{
            .name = name,
            .alloc = alloc,
            .cases = std.ArrayList(Case).init(alloc),
        };
    }

    pub fn run(self: *Harness, name: []const u8, runner: Runner) anyerror!void {
        const ITER = 5_000_000;
        // var progress = std.Progress{};
        // const root_node = try progress.start("Running benchmark", ITER);
        // defer root_node.end();

        var case = Case{ .name = name };
        var run_count: usize = 0;
        var helper = Helper{
            .case = &case,
        };
        var timer = try std.time.Timer.start();
        while (run_count < ITER) : (run_count += 1) {
            timer.reset();
            try runner(&helper);
            case.nanoseconds += timer.read();
            // root_node.completeOne();
        }
        try self.cases.append(case);
    }

    pub fn printResults(self: *Harness) !void {
        var cases = self.cases.toOwnedSlice();
        defer self.alloc.free(cases);

        var stdout = std.io.getStdOut().writer();

        _ = try stdout.print("=== {s} ===\n", .{self.name});

        for (cases) |r| {
            var bytes = Byte.convertReasonable(.{
                .tag = .byte,
                .value = @intToFloat(f64, r.bytes),
            });
            var seconds = Second.convert(.{
                .tag = .nanoseconds,
                .value = @intToFloat(f64, r.nanoseconds),
            }, .seconds);
            var ratio = Ratio(Byte.U, Second.U).init(bytes, seconds);
            _ = try stdout.print(
                "|   \x1b[90m{}\x1b[0m \x1b[36m{s}\x1b[0m\n",
                .{ ratio, r.name },
            );
        }
    }
};
