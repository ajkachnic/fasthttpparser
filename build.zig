const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("fasthttpparser", "fasthttpparser.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("fasthttpparser.zig");
    main_tests.setBuildMode(mode);

    const bencher_tests = b.addTest("bench/bencher.zig");
    bencher_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&bencher_tests.step);

    const fasthttp_bench = b.addExecutable("fasthttp_bench", "bench/fasthttp/bench.zig");
    fasthttp_bench.setBuildMode(mode);
    fasthttp_bench.addPackagePath("fasthttpparser", "fasthttpparser.zig");
    fasthttp_bench.addPackagePath("bencher", "bench/bencher.zig");

    const fasthttp_bench_run = fasthttp_bench.run();

    const picohttp_bench = b.addExecutable("picohttp_bench", "bench/picohttp/bench.zig");
    picohttp_bench.linkLibC();
    picohttp_bench.setBuildMode(mode);
    picohttp_bench.addCSourceFile("bench/picohttp/picohttpparser.c", &.{});
    picohttp_bench.addPackagePath("bencher", "bench/bencher.zig");

    const picohttp_bench_run = picohttp_bench.run();

    // const http_parser_bench = b.addExecutable("http_parser_bench", "bench/http_parser/bench.zig");
    // http_parser_bench.linkLibC();
    // http_parser_bench.setBuildMode(mode);
    // http_parser_bench.addCSourceFile("bench/http_parser/http_parser.c", &.{});
    // http_parser_bench.addIncludeDir("bench/http_parser");
    // http_parser_bench.addPackagePath("bencher", "bench/bencher.zig");

    // const http_parser_bench_run = http_parser_bench.run();

    const bench_step = b.step("bench", "Run benchmarks");

    bench_step.dependOn(&fasthttp_bench_run.step);
    bench_step.dependOn(&picohttp_bench_run.step);
    // bench_step.dependOn(&http_parser_bench_run.step);
}
