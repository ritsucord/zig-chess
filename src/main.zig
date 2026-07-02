const std = @import("std");
const lib = @import("zig_lib");

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    var board = lib.Board.init();
    board.setup();
    var buffer: [50]u8 = undefined;
    var state: u8 = 0;
    var selected: ?lib.Coord = null;
    var moves = lib.MoveSet{};
    var next_move: lib.Coord = undefined;
    var turn = lib.TeamType.white;
    while (true) {
        std.debug.print("\n\n", .{});
        if (state == 1) std.debug.print("Selected('c' to cancel)\n", .{});
        if (state == 2) std.debug.print("Promotion(r/n/b/q): ", .{});
        if (state != 2) board.debug_print(moves, selected);
        const input: []const u8 =
            if (try stdin.readUntilDelimiterOrEof(&buffer, '\n'))
                |line| (std.mem.trim(u8, line, "\r "))
            else return;
        std.debug.print("\n", .{});
        if (state == 0) {
            if (
                input.len != 2 or
                input[0] < 'a' or input[0] > 'h' or
                input[1] < '1' or input[1] > '8'
            ) continue;
            const x: u8 = input[0] - 'a';
            const y: u8 = input[1] - '1';
            const piece = board.grid[y][x];
            if (piece) |p| {
                if (p.team != turn) continue;
                selected = lib.Coord{ .x = x, .y = y };
                state = 1;
                moves = board.get_legal(selected.?, board.get_reachable(selected.?));
            }
        } else if (state == 1) {
            if (input.len == 1 and input[0] == 'c') {
                state = 0;
                selected = null;
                moves.len = 0;
                continue;
            }
            if (
                input.len != 2 or
                input[0] < 'a' or input[0] > 'h' or
                input[1] < '1' or input[1] > '8'
            ) continue;
            const x: u8 = input[0] - 'a';
            const y: u8 = input[1] - '1';
            for (0..moves.len) |i| {
                const move = moves.coords[i];
                if (move.x == x and move.y == y) {
                    const ev = board.test_move(selected.?, move);
                    switch (ev) {
                        .none => {
                            board.confirm_move(selected.?, move, .none);
                            turn = if (turn == .white) .black else .white;
                        },
                        .promotion => {
                            next_move = move;
                            state = 2;
                            continue;
                        }
                    }
                    break;
                }
            } else continue;
            state = 0;
            selected = null;
            moves.len = 0;
        } else if (state == 2) {
            if (
                input.len != 1 or
                input[0] != 'r' and
                input[0] != 'n' and
                input[0] != 'b' and
                input[0] != 'q'
            ) continue;
            const data: lib.EventData = .{
                .promotion = switch (input[0]) {
                    'r' => .{ .rook = {}, },
                    'n' => .{ .knight = {}, },
                    'b' => .{ .bishop = {}, },
                    'q' => .{ .queen = {}, },
                    else => unreachable
                }
            };
            board.confirm_move(selected.?, next_move, data);
            state = 0;
            selected = null;
            moves.len = 0;
            turn = if (turn == .white) .black else .white;
        }
    }
}