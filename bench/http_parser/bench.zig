const bencher = @import("bencher");
const std = @import("std");
const c = @cImport({
    @cInclude("http_parser.h");
});

const SHORT_REQ = "GET / HTTP/1.1\r\n" ++
    "Host: www.reddit.com\r\n" ++
    "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:15.0) Gecko/20100101 Firefox/15.0.1\r\n" ++
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
    "Accept-Language: en-us,en;q=0.5\r\n" ++
    "Accept-Encoding: gzip, deflate\r\n" ++
    "Connection: keep-alive\r\n";
const LONG_REQ =
    "GET /wp-content/uploads/2010/03/hello-kitty-darth-vader-pink.jpg HTTP/1.1\r\n" ++
    "Host: www.kittyhell.com\r\n" ++
    "User-Agent: Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; ja-JP-mac; rv:1.9.2.3) Gecko/20100401 Firefox/3.6.3 " ++
    "Pathtraq/0.9\r\n" ++
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ++
    "Accept-Language: ja,en-us;q=0.7,en;q=0.3\r\n" ++
    "Accept-Encoding: gzip,deflate\r\n" ++
    "Accept-Charset: Shift_JIS,utf-8;q=0.7,*;q=0.7\r\n" ++
    "Keep-Alive: 115\r\n" ++
    "Connection: keep-alive\r\n" ++
    "Cookie: wp_ozh_wsa_visits=2; wp_ozh_wsa_visit_lasttime=xxxxxxxxxx; " ++
    "__utma=xxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.xxxxxxxxxx.x; " ++
    "__utmz=xxxxxxxxx.xxxxxxxxxx.x.x.utmccn=(referral)|utmcsr=reader.livedoor.com|utmcct=/reader/|utmcmd=referral\r\n" ++
    "\r\n";

const SMALLER = @embedFile("../http-requests.txt");
const BIGGER = @embedFile("../bigger.txt");

fn longBench(h: *bencher.Harness.Helper) anyerror!void {
    // var headers: [32]Header = undefined;
    var parser: c.http_parser = undefined;
    var settings: c.http_parser_settings = undefined;

    c.http_parser_init(&parser, c.HTTP_REQUEST);
    c.http_parser_settings_init(&settings);

    c.http_parser_execute(&parser, &settings, LONG_REQ, LONG_REQ.len);

    h.addBytes(LONG_REQ.len);
}

fn shortBench(h: *bencher.Harness.Helper) anyerror!void {
    // var headers: [32]Header = undefined;
    // _ = try Request.parse(LONG_REQ, &headers);
    var parser: c.http_parser = undefined;
    var settings: c.http_parser_settings = undefined;

    c.http_parser_init(&parser, c.HTTP_REQUEST);
    c.http_parser_settings_init(&settings);

    c.http_parser_execute(&parser, &settings, SHORT_REQ, SHORT_REQ.len);

    h.addBytes(SHORT_REQ.len);
}

fn smallerBench(h: *bencher.Harness.Helper) anyerror!void {
    var iter = std.mem.split(u8, SMALLER, "\n\n");

    var parser: c.http_parser = undefined;
    var settings: c.http_parser_settings = undefined;

    c.http_parser_init(&parser, c.HTTP_REQUEST);
    c.http_parser_settings_init(&settings);

    while (iter.next()) |req| {
        c.http_parser_execute(&parser, &settings, req, req.len);
    }

    h.addBytes(SMALLER.len);
}
fn biggerBench(h: *bencher.Harness.Helper) anyerror!void {
    var iter = std.mem.split(u8, BIGGER, "\n\n");

    var parser: c.http_parser = undefined;
    var settings: c.http_parser_settings = undefined;

    c.http_parser_init(&parser, c.HTTP_REQUEST);
    c.http_parser_settings_init(&settings);

    while (iter.next()) |req| {
        c.http_parser_execute(&parser, &settings, req, req.len);
    }

    h.addBytes(BIGGER.len);
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var harness = bencher.Harness.init(gpa.allocator(), "picohttpparser");
    try harness.run("one-long", longBench);
    try harness.run("one-short", shortBench);
    try harness.run("smaller", shortBench);
    try harness.run("bigger", shortBench);
    try harness.printResults();
}
