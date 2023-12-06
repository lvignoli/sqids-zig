const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const ArrayList = std.ArrayList;

const default_alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// Options control the configuration of the sqid encoder.
const Options = struct {
    alphabet: []const u8 = default_alphabet,
    min_length: u8 = 0,
    blocklist: []const []const u8 = &.{},
};

/// encode encodes a list of numbers into a sqids ID.
pub fn encode(allocator: mem.Allocator, numbers: []const u64, options: Options) ![]const u8 {
    if (numbers.len == 0) {
        return "";
    }

    const increment: u64 = 0;

    const alphabet = try allocator.dupe(u8, options.alphabet);
    defer allocator.free(alphabet);
    shuffle(alphabet);

    // Clean up blocklist:
    // 1. all blocklist words should be lowercase,
    // 2. no words less than 3 chars,
    // 3. if some words contain chars that are not in the alphabet, remove those.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var filtered_blocklist = ArrayList([]const u8).init(allocator);
    for (options.blocklist) |word| {
        if (word.len < 3) {
            continue;
        }
        const lowercased_word = try std.ascii.allocLowerString(arena_allocator, word);
        if (!validInAlphabet(lowercased_word, alphabet)) {
            continue;
        }
        try filtered_blocklist.append(lowercased_word);
    }

    const blocklist = try filtered_blocklist.toOwnedSlice();
    defer allocator.free(blocklist);

    return try encodeNumbers(allocator, numbers, alphabet, increment, options.min_length, blocklist);
}

inline fn validInAlphabet(word: []const u8, alphabet: []const u8) bool {
    for (word) |c| {
        if (mem.indexOf(u8, alphabet, &.{c}) == null) {
            return false;
        }
    }
    return true;
}

/// encodeNumbers performs the actual encoding processing.
fn encodeNumbers(allocator: mem.Allocator, numbers: []const u64, original_alphabet: []const u8, increment: u64, min_length: u64, blocklist: []const []const u8) ![]u8 {
    var alphabet = try allocator.dupe(u8, original_alphabet);
    defer allocator.free(alphabet);

    if (increment > alphabet.len) {
        return error.ReachedMaxAttempts;
    }

    // Get semi-random offset.
    var offset: u64 = numbers.len;
    for (numbers, 0..) |n, i| {
        offset += i;
        offset += alphabet[n % alphabet.len];
    }
    offset %= alphabet.len;
    offset = (offset + increment) % alphabet.len;

    // Prefix and alphabet.
    mem.rotate(u8, alphabet, offset);
    const prefix = alphabet[0];
    mem.reverse(u8, alphabet);

    // Build the ID.
    var ret = ArrayList(u8).init(allocator);
    defer ret.deinit();

    try ret.append(prefix);

    for (numbers, 0..) |n, i| {
        const x = try toID(allocator, n, alphabet[1..]);
        defer allocator.free(x);
        try ret.appendSlice(x);

        if (i < numbers.len - 1) {
            try ret.append(alphabet[0]);
            shuffle(alphabet);
        }
    }

    // Handle min_length requirements.
    if (min_length > ret.items.len) {
        try ret.append(alphabet[0]);
        while (min_length > ret.items.len) {
            shuffle(alphabet);
            const n = @min(min_length - ret.items.len, alphabet.len);
            try ret.appendSlice(alphabet[0..n]);
        }
    }

    var ID = try ret.toOwnedSlice();

    // Handle blocklist.
    const blocked = try isBlockedID(allocator, blocklist, ID);
    if (blocked) {
        allocator.free(ID); // Freeing the old ID string.
        ID = try encodeNumbers(allocator, numbers, original_alphabet, increment + 1, min_length, blocklist);
    }
    return ID;
}

/// isBlockedID returns true if id collides with the blocklist.
fn isBlockedID(allocator: mem.Allocator, blocklist: []const []const u8, id: []const u8) !bool {
    const lower_id = try std.ascii.allocLowerString(allocator, id);
    defer allocator.free(lower_id);

    for (blocklist) |word| {
        if (word.len > lower_id.len) {
            continue;
        }
        if (lower_id.len <= 3 or word.len <= 3) {
            if (mem.eql(u8, id, word)) {
                return true;
            }
        } else if (containsNumber(word)) {
            if (mem.startsWith(u8, lower_id, word) or mem.endsWith(u8, lower_id, word)) {
                return true;
            }
        } else if (mem.indexOf(u8, lower_id, word)) |_| {
            return true;
        }
    }

    return false;
}

inline fn containsNumber(s: []const u8) bool {
    for (s) |c| {
        if (std.ascii.isDigit(c)) {
            return true;
        }
    }
    return false;
}

test "encode" {
    const allocator = testing.allocator;

    const TestCase = struct {
        numbers: []const u64,
        alphabet: []const u8,
        expected: []const u8,
    };

    const cases = [_]TestCase{
        .{
            .numbers = &[_]u64{ 1, 2, 3 },
            .alphabet = "0123456789abcdef",
            .expected = "489158",
        },
        .{
            .numbers = &[_]u64{ 1, 2, 3 },
            .alphabet = default_alphabet,
            .expected = "86Rf07",
        },
    };

    for (cases) |case| {
        const id = try encode(allocator, case.numbers, .{ .alphabet = case.alphabet });
        defer allocator.free(id);
        try testing.expectEqualStrings(case.expected, id);
    }
}

test "encode incremental numbers" {
    const allocator = testing.allocator;
    var ids = std.StringHashMap([]const u64).init(allocator);
    defer ids.deinit();

    // Incremental numbers.
    try ids.put("bM", &.{0});
    try ids.put("Uk", &.{1});
    try ids.put("gb", &.{2});
    try ids.put("Ef", &.{3});
    try ids.put("Vq", &.{4});
    try ids.put("uw", &.{5});
    try ids.put("OI", &.{6});
    try ids.put("AX", &.{7});
    try ids.put("p6", &.{8});
    try ids.put("nJ", &.{9});

    // Incremental number, same index zero.
    try ids.put("SvIz", &.{ 0, 0 });
    try ids.put("n3qa", &.{ 0, 1 });
    try ids.put("tryF", &.{ 0, 2 });
    try ids.put("eg6q", &.{ 0, 3 });
    try ids.put("rSCF", &.{ 0, 4 });
    try ids.put("sR8x", &.{ 0, 5 });
    try ids.put("uY2M", &.{ 0, 6 });
    try ids.put("74dI", &.{ 0, 7 });
    try ids.put("30WX", &.{ 0, 8 });
    try ids.put("moxr", &.{ 0, 9 });

    var iterator = ids.keyIterator();
    while (iterator.next()) |k| {
        const got = try encode(allocator, ids.get(k.*).?, .{ .alphabet = default_alphabet });
        defer allocator.free(got);
        try testing.expectEqualStrings(k.*, got);

        const got_numbers = try decode(allocator, k.*, default_alphabet);
        defer allocator.free(got_numbers);
        try testing.expectEqualSlices(u64, ids.get(k.*).?, got_numbers);
    }
}

test "min length: incremental numbers" {
    const numbers = [_]u64{ 1, 2, 3 };

    const allocator = testing.allocator;
    var ids = std.AutoHashMap(u8, []const u8).init(allocator);
    defer ids.deinit();

    // Simple.
    try ids.put(default_alphabet.len, "86Rf07xd4zBmiJXQG6otHEbew02c3PWsUOLZxADhCpKj7aVFv9I8RquYrNlSTM");
    // Incremental.
    try ids.put(6, "86Rf07");
    try ids.put(7, "86Rf07x");
    try ids.put(8, "86Rf07xd");
    try ids.put(9, "86Rf07xd4");
    try ids.put(10, "86Rf07xd4z");
    try ids.put(11, "86Rf07xd4zB");
    try ids.put(12, "86Rf07xd4zBm");
    try ids.put(13, "86Rf07xd4zBmi");

    var it = ids.iterator();
    while (it.next()) |entry| {
        const k = entry.key_ptr.*;
        const v = entry.value_ptr.*;

        const got = try encode(allocator, &numbers, .{ .alphabet = default_alphabet, .min_length = k });
        defer allocator.free(got);
        try testing.expectEqualStrings(v, got);
        try testing.expect(got.len >= k);

        const decoded = try decode(allocator, got, default_alphabet);
        defer allocator.free(decoded);
        try testing.expectEqualSlices(u64, &numbers, decoded);
    }
}

test "non-empty blocklist" {
    const blocklist: []const []const u8 = &.{"ArUO"};
    const allocator = testing.allocator;

    const got_numbers = try decode(allocator, "ArUO", default_alphabet);
    defer allocator.free(got_numbers);
    try testing.expectEqualSlices(u64, &.{100000}, got_numbers);

    const got_id = try encode(allocator, &.{100000}, .{ .alphabet = default_alphabet, .blocklist = blocklist });
    defer allocator.free(got_id);
    try testing.expectEqualStrings("QyG4", got_id);
}

/// decode decodes id into numbers using alphabet.
pub fn decode(allocator: mem.Allocator, to_decode_id: []const u8, decoding_alphabet: []const u8) ![]const u64 {
    var id = to_decode_id[0..];
    if (id.len == 0) {
        return &.{};
    }

    const alphabet = try allocator.dupe(u8, decoding_alphabet);
    defer allocator.free(alphabet);
    shuffle(alphabet);

    // If a character is not in the alphabet, return an empty array.
    // TODO(lvignoli): here we could return an informative error. Check if fine with specs.
    for (id) |c| {
        if (mem.indexOfScalar(u8, id, c) == null) {
            return &.{};
        }
    }

    const prefix = id[0];
    id = id[1..];

    const offset = mem.indexOfScalar(u8, alphabet, prefix).?;
    // NOTE(l.vignoli): We can unwrap safely since all characters are in alphabet.
    mem.rotate(u8, alphabet, offset);
    mem.reverse(u8, alphabet);

    var ret = ArrayList(u64).init(allocator);
    defer ret.deinit();

    while (id.len > 0) {
        const separator = alphabet[0];

        // We need the first part to the left of the separator to decode the number.
        // If there is no separator, we take the whole string.
        const i = mem.indexOfScalar(u8, id, separator) orelse id.len; // TODO: refactor.
        const left = id[0..i];
        const right = if (i == id.len) "" else id[i + 1 ..];

        // If empty, we are done (the rest is junk characters).
        if (left.len == 0) {
            return try ret.toOwnedSlice();
        }

        try ret.append(toNumber(left, alphabet[1..]));

        // If there is still numbers to decode from the ID, shuffle the alphabet.
        if (right.len > 0) {
            shuffle(alphabet);
        }

        // Keep the part to the right of the first separator for the next iteration.
        id = right;
    }

    return try ret.toOwnedSlice();
}

test "decode" {
    const allocator = testing.allocator;
    const numbers = try decode(allocator, "489158", "0123456789abcdef");
    defer allocator.free(numbers);
    try testing.expectEqualSlices(u64, &.{ 1, 2, 3 }, numbers);
}

// toID generates a new ID string for number using alphabet.
fn toID(allocator: mem.Allocator, number: u64, alphabet: []const u8) ![]const u8 {
    var result: u64 = number;

    var id = std.ArrayList(u8).init(allocator);

    while (true) {
        try id.append(alphabet[result % alphabet.len]);
        result = result / alphabet.len;
        if (result == 0) break;
    }

    const value: []u8 = try id.toOwnedSlice();

    // In the reference implementation, the letters are inserted at index 0.
    // Here we append them for efficiency, so we reverse the ID at the end.
    mem.reverse(u8, value);

    return value;
}

fn toNumber(s: []const u8, alphabet: []const u8) u64 {
    var num: u64 = 0;
    for (s) |c| {
        if (mem.indexOfScalar(u8, alphabet, c)) |i| {
            num = num * alphabet.len + i;
        }
    }
    return num;
}

test "toNumber" {
    const alphabet = [_]u8{ 'a', 'b', 'c' };
    const n = toNumber("cb", &alphabet);
    _ = n;
}

/// Shuffle shuffles inplace the given alphabet. It's consistent (produces the
/// same result given the input).
fn shuffle(alphabet: []u8) void {
    const n = alphabet.len;

    var i: usize = 0;
    var j = alphabet.len - 1;

    while (j > 0) {
        const r = (i * j + alphabet[i] + alphabet[j]) % n;
        mem.swap(u8, &alphabet[i], &alphabet[r]);
        i += 1;
        j -= 1;
    }
}

test "shuffle" {
    const allocator = testing.allocator;

    const TestCase = struct {
        input: []const u8,
        want: []const u8,
    };

    const cases = [_]TestCase{
        // Default shuffle, checking for randomness.
        // Default shuffle, checking for randomness.
        .{
            .input = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            .want = "fwjBhEY2uczNPDiloxmvISCrytaJO4d71T0W3qnMZbXVHg6eR8sAQ5KkpLUGF9",
        },
        // Numbers in the front, another check for randomness.
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ec38UaynYXvoxSK7RV9uZ1D2HEPw6isrdzAmBNGT5OCJLk0jlFbtqWQ4hIpMgf",
        },
        // Swapping front 2 characters.
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ec38UaynYXvoxSK7RV9uZ1D2HEPw6isrdzAmBNGT5OCJLk0jlFbtqWQ4hIpMgf",
        },
        .{
            .input = "1023456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "xI3RUayk1MSolQK7e09zYmFpVXPwHiNrdfBJ6ZAT5uCWbntgcDsEqjv4hLG28O",
        },
        // Swapping last 2 characters.
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ec38UaynYXvoxSK7RV9uZ1D2HEPw6isrdzAmBNGT5OCJLk0jlFbtqWQ4hIpMgf",
        },
        .{
            .input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXZY",
            .want = "x038UaykZMSolIK7RzcbYmFpgXEPHiNr1d2VfGAT5uJWQetjvDswqn94hLC6BO",
        },
        // Short alphabet.
        .{
            .input = "0123456789",
            .want = "4086517392",
        },
        // Really short alphabet.
        .{
            .input = "12345",
            .want = "24135",
        },
        // Lowercase alphabet.
        .{
            .input = "abcdefghijklmnopqrstuvwxyz",
            .want = "lbfziqvscptmyxrekguohwjand",
        },
        .{
            .input = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            .want = "ZXBNSIJQEDMCTKOHVWFYUPLRGA",
        },
    };

    for (cases) |case| {
        const alphabet = try allocator.dupe(u8, case.input);
        defer allocator.free(alphabet);
        shuffle(alphabet);

        try testing.expectEqualSlices(u8, case.want, alphabet);
    }
}
