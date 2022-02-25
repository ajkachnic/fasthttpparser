# fasthttpparser

*Note: this is unstable and the API is likely to change; use at your own risk*

A HTTP 1.1 parser written in Zig. Currently competes with [`httparse`](https://https://github.com/seanmonstar/httparse) and is beaten by [`picohttpparser`](https://github.com/h20/picohttpparser)

## Benchmarks

| parser         | one-long | one-short  | smaller    | bigger     |
|----------------|----------|------------|------------|------------|
| fasthttpparser | 1.08gb/s | 987.54mb/s | 986.80mb/s | 984.49mb/s |
| picohttpparser | 3.04gb/s | 2.99gb/s   | 3.06gb/s   | 3.06gb/s   |

You can run these yourself with `zig build bench`. I'll eventually extend the benchmark suite to include httparse, but I don't feel like dealing with Rust-Zig interop (test harness is written in Zig) at the moment.

## Installation

Since the parser ships as a single file (`fasthttpparser.zig`), you can just drop that into your project.

Then, you could add it to your `build.zig` file as a package, or just import it directly.
