const std = @import("std");
const stdin = std.io.getStdIn().reader();
const print = std.debug.print;
const allocator = std.heap.page_allocator;

pub fn main() !void {
    var buf: [27]u8 = undefined;
    const available = try askInput("Which letters are still available? ", &buf) orelse unreachable;
    var options: [5]usize = .{available.len} ** 5;

    var known: [5]u8 = undefined;
    for (0..5) |i| {
        const letter = try askLetter(i);
        if (letter != ' ') options[i] = 1;
        known[i] = letter;
    }

    var banned: [5][]const u8 = undefined;
    var bufs: [5][26]u8 = undefined;
    for (0..5) |i| {
        print("Which letters are banned in position {d}? ", .{i + 1});
        const to_ban = try askInput("", &bufs[i]) orelse unreachable;
        options[i] -= to_ban.len;
        banned[i] = to_ban;
    }

    var buf2: [27]u8 = undefined;
    const forced = try askInput("Which letters have to be used? ", &buf2) orelse unreachable;

    var total: usize = 1;
    for (options) |single| {
        total *= single;
    }

    var words = try allocator.alloc([5]u8, total);
    var next_word: usize = 0;
    for (available) |first| {
        var word: [5]u8 = undefined;
        if (banned[0].len > 0 and contains(banned[0], first)) continue;
        word[0] = if (known[0] == ' ') first else known[0];
        for (available) |second| {
            if (banned[1].len > 1 and contains(banned[1], second)) continue;
            word[1] = if (known[1] == ' ') second else known[1];
            for (available) |third| {
                if (banned[2].len > 2 and contains(banned[2], third)) continue;
                word[2] = if (known[2] == ' ') third else known[2];
                for (available) |fourth| {
                    if (banned[3].len > 3 and contains(banned[3], fourth)) continue;
                    word[3] = if (known[3] == ' ') fourth else known[3];
                    for (available) |fifth| {
                        if (banned[4].len > 4 and contains(banned[4], fifth)) continue;
                        word[4] = if (known[4] == ' ') fifth else known[4];
                        var legal = true;
                        for (forced) |l| {
                            if (!contains(&word, l)) legal = false;
                        }
                        if (legal and !contains_word(words, &word)) {
                            words[next_word] = word;
                            next_word += 1;
                        }
                    }
                }
            }
        }
    }

    for (words) |word| {
        if (word[0] == undefined) continue;
        print("{s}\n", .{word});
    }
}

fn askInput(question: []const u8, buf: []u8) !?[]const u8 {
    print("{s} ", .{question});
    return stdin.readUntilDelimiterOrEof(buf[0..], '\n');
}

fn askLetter(index: usize) !u8 {
    print("Type letter in position {d} if known, else hit enter: ", .{index + 1});
    var buf: [2]u8 = undefined;
    const input = try stdin.readUntilDelimiterOrEof(buf[0..], '\n') orelse " ";
    return if (input.len > 0) input[0] else ' ';
}

fn contains(word: []const u8, letter: u8) bool {
    for (word) |l| {
        if (letter == l) return true;
    }
    return false;
}

fn contains_word(words: [][5]u8, word: []const u8) bool {
    for (words) |*w| {
        if (std.mem.eql(u8, word, w)) return true;
    }
    return false;
}
