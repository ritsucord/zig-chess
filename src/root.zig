const std = @import("std");

pub const size_x = 8;
pub const size_y = 8;

pub const Coord = struct {
    x: u8,
    y: u8,

    pub fn init(x: u8, y: u8) ?Coord {
        if (x < 0 or x >= size_x or y < 0 or y >= size_y)
            return null;
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Coord, dx: i8, dy: i8) ?Coord {
        const x = @as(i8, @intCast(self.x)) + dx;
        const y = @as(i8, @intCast(self.y)) + dy;
        if (x < 0 or x >= size_x or y < 0 or y >= size_y)
            return null;
        return .{ .x = @as(u8, @intCast(x)), .y = @as(u8, @intCast(y)) };
    }

    pub fn dist(self: Coord, from: Coord) [2]i8 {
        return .{
            @as(i8, @intCast(self.x)) - @as(i8, @intCast(from.x)),
            @as(i8, @intCast(self.y)) - @as(i8, @intCast(from.y)),
        };
    }

    pub fn abs_to_rel(coord: Coord, team: TeamType) Coord {
        return Coord{
            .x = if (team == .white) coord.x else size_x - coord.x - 1,
            .y = if (team == .white) coord.y else size_y - coord.y - 1,
        };
    }

    pub fn rel_to_abs(coord: Coord, team: TeamType) Coord {
        return Coord{
            .x = if (team == .white) coord.x else size_x - coord.x - 1,
            .y = if (team == .white) coord.y else size_y - coord.y - 1,
        };
    }
};

pub const PieceType = enum {
    pawn, rook, knight, bishop, queen, king
};

pub const TeamType = enum {
    white, black
};

pub const RelTeamType = enum {
    us, enemy
};

pub const Piece = struct {
    ptype: PieceType,
    team: TeamType,
};

pub const RelPiece = struct {
    ptype: PieceType,
    team: RelTeamType,
};

pub const Flag = enum {
    none, moved, pawn_en_passant_ready
};

pub const Event = enum {
    none, promotion
};

pub const EventData = union(Event) {
    none: void,
    promotion: union(enum) { rook: void, knight: void, bishop: void, queen: void },
};

pub const Tile = struct {
    piece: ?Piece,
    flag: Flag
};

pub const RelTile = struct {
    piece: ?RelPiece,
    flag: Flag
};

pub const MoveSet = struct {
    coords: [size_x*size_y]Coord = undefined,
    len: u8 = 0,

    pub fn push(self: *MoveSet, coord: Coord) void {
        self.coords[self.len] = coord;
        self.len += 1;
    }

    pub fn pop(self: *MoveSet) void {
        if (self.len > 0) self.len -= 1;
    }
};

pub const Board = struct {
    grid: [size_y][size_x]?Piece = @splat(@as([size_x]?Piece, @splat(null))),
    flags: [size_y][size_x]Flag = @splat(@as([size_x]Flag, @splat(.none))),

    const default_layout: [size_y][size_x]?Piece = blk: {
        var res: [size_y][size_x]?Piece = undefined;
        const line: [size_x]PieceType = .{
            .rook, .knight, .bishop, .queen,
            .king, .bishop, .knight, .rook
        };
        var y: u8 = 0;
        while (y < size_y): (y += 1) {
            const team =
                if (y < 2) TeamType.white
                else TeamType.black;
            var x: u8 = 0;
            while (x < size_x): (x += 1) {
                const piece: ?PieceType =
                    if (y == 1 or y == 6) PieceType.pawn
                    else if (y == 0 or y == 7) line[x]
                    else null;
                res[y][x] = if (piece) |p| .{
                    .team = team,
                    .ptype = p
                } else null;
            }
        }
        break :blk res;
    };

    pub fn init() Board {
        return .{};
    }

    pub fn setup(self: *Board) void {
        self.grid = default_layout;
    }

    pub fn get(self: *const Board, coord: Coord) Tile {
        return .{
            .piece = self.grid[coord.y][coord.x],
            .flag = self.flags[coord.y][coord.x],
        };
    }

    pub fn rel(self: *const Board, team: TeamType, rel_coord: Coord) RelTile {
        const coord = rel_coord.rel_to_abs(team);
        const piece = self.grid[coord.y][coord.x];
        return .{
            .piece = if (piece) |p| .{
                .ptype = p.ptype,
                .team = if (team == p.team) .us else .enemy,
            } else null,
            .flag = self.flags[coord.y][coord.x],
        };
    }

    pub fn get_reachable(board: *const Board, coord: Coord) MoveSet {
        var res = MoveSet{};
        const piece: Piece =
            if (board.get(coord).piece) |p| p
            else return res;
        const ptype = piece.ptype;
        const team = piece.team;
        const rel_coord = coord.abs_to_rel(team);
        switch (ptype) {
            .pawn => {
                if (rel_coord.add(-1, 1)) |left| {
                    res.push(left);
                    if (board.rel(team, left).piece) |p| {
                        if (p.team == .us) res.pop();
                    }
                }
                if (rel_coord.add(1, 1)) |right| {
                    res.push(right);
                    if (board.rel(team, right).piece) |p| {
                        if (p.team == .us) res.pop();
                    }
                }
                if (rel_coord.add(0, 1)) |fw| {
                    if (board.rel(team, fw).piece == null) {
                        res.push(fw);
                        if (board.rel(team, rel_coord).flag == .none) {
                            if (rel_coord.add(0, 2)) |fw2| {
                                if (board.rel(team, fw2).piece == null)
                                    res.push(fw2);
                            }
                        }
                    }
                }
            },
            .rook => {
                const dir: [4][2]i8 = .{
                               .{ 0,  1},
                    .{-1,  0},            .{ 1,  0},
                               .{ 0, -1},
                };
                for (dir) |d| {
                    var cur_coord = rel_coord;
                    while (cur_coord.add(d[0], d[1])) |nx_coord| {
                        res.push(nx_coord);
                        if (board.rel(team, nx_coord).piece) |p| {
                            if (p.team == .us) res.pop();
                            break;
                        }
                        cur_coord = nx_coord;
                    }
                }
            },
            .knight => {
                const dir: [8][2]i8 = .{
                               .{-1,  2}, .{ 1,  2},
                    .{-2,  1},                       .{ 2,  1},
                    .{-2, -1},                       .{ 2, -1},
                               .{-1, -2}, .{ 1, -2},
                };
                for (dir) |d| {
                    if (rel_coord.add(d[0], d[1])) |nx_coord| {
                        if (board.rel(team, nx_coord).piece) |p| {
                            if (p.team == .us) continue;
                        }
                        res.push(nx_coord);
                    }
                }
            },
            .bishop => {
                const dir: [4][2]i8 = .{
                    .{-1,  1}, .{ 1,  1},
                    .{-1, -1}, .{ 1, -1},
                };
                for (dir) |d| {
                    var cur_coord = rel_coord;
                    while (cur_coord.add(d[0], d[1])) |nx_coord| {
                        res.push(nx_coord);
                        if (board.rel(team, nx_coord).piece) |p| {
                            if (p.team == .us) res.pop();
                            break;
                        }
                        cur_coord = nx_coord;
                    }
                }
            },
            .queen => {
                const dir: [8][2]i8 = .{
                    .{-1,  1}, .{ 0,  1}, .{ 1,  1},
                    .{-1,  0},            .{ 1,  0},
                    .{-1, -1}, .{ 0, -1}, .{ 1, -1},
                };
                for (dir) |d| {
                    var cur_coord = rel_coord;
                    while (cur_coord.add(d[0], d[1])) |nx_coord| {
                        res.push(nx_coord);
                        if (board.rel(team, nx_coord).piece) |p| {
                            if (p.team == .us) res.pop();
                            break;
                        }
                        cur_coord = nx_coord;
                    }
                }
            },
            .king => {
                const dir: [8][2]i8 = .{
                    .{-1,  1}, .{ 0,  1}, .{ 1,  1},
                    .{-1,  0},            .{ 1,  0},
                    .{-1, -1}, .{ 0, -1}, .{ 1, -1},
                };
                for (dir) |d| {
                    if (rel_coord.add(d[0], d[1])) |nx_coord| {
                        if (board.rel(team, nx_coord).piece) |p| {
                            if (p.team == .us) continue;
                        }
                        res.push(nx_coord);
                    }
                }
                if (board.rel(team, rel_coord).flag == .none) {
                    const cas_coords: [2][2]Coord = .{.{
                        Coord{ .x = 0, .y = 0 },
                        Coord{ .x = rel_coord.x - 2, .y = 0 },
                    }, .{
                        Coord{ .x = 7, .y = 0 },
                        Coord{ .x = rel_coord.x + 2, .y = 0 },
                    }};
                    for (cas_coords) |cas_coord| {
                        const rook = cas_coord[0];
                        const king = cas_coord[1];
                        const tile = board.rel(team, rook);
                        if (tile.flag != .none) continue;
                        if (tile.piece) |p| {
                            if (p.ptype != .rook or p.team != .us) continue;
                            var x: u8 = @min(rook.x, rel_coord.x) + 1;
                            while (x < @max(rook.x, rel_coord.x)): (x += 1) {
                                if (board.rel(team, Coord{
                                    .x = x,
                                    .y = 0
                                }).piece != null) break;
                            } else res.push(king);
                        }
                    }
                }
            },
        }
        for (0..res.len) |i| {
            res.coords[i] = res.coords[i].rel_to_abs(team);
        }
        return res;
    }

    pub fn is_checked(board: *const Board, coord: Coord, team: TeamType) bool {
        var y: u8 = 0;
        while (y < size_y): (y += 1) {
            var x: u8 = 0;
            while (x < size_x): (x += 1) {
                if (board.get(.{ .x = x, .y = y }).piece) |p| {
                    if (p.team == team) continue;
                    const moves = board.get_reachable(.{ .x = x, .y = y });
                    for (0..moves.len) |i| {
                        if (std.meta.eql(moves.coords[i], coord)) return true;
                    }
                }
            }
        }
        return false;
    }

    pub fn get_legal(board: *const Board, coord: Coord, moves: MoveSet) MoveSet {
        var res = MoveSet{};
        const piece: Piece =
            if (board.get(coord).piece) |p| p
            else return res;
        const team = piece.team;
        const ptype = piece.ptype;
        const my_king = found: {
            var y: u8 = 0;
            while (y < size_y): (y += 1) {
                var x: u8 = 0;
                while (x < size_x): (x += 1) {
                    if (board.grid[y][x]) |p| {
                        if (p.ptype == .king and p.team == team)
                            break :found Coord{ .x = x, .y = y };
                    }
                }
            }
            unreachable;
        };
        thismove: for (0..moves.len) |i| {
            const move = moves.coords[i];
            if (ptype == .king) {
                const dist = move.dist(coord);
                if (@abs(dist[0]) == 2) {
                    var x: u8 = @min(coord.x, move.x);
                    while (x <= @max(coord.x, move.x)): (x += 1) {
                        if (board.is_checked(.{ .x = x, .y = move.y }, team))
                            continue :thismove;
                    }
                }
            }
            const is_en_passant =
                if (ptype == .pawn) ifb: {
                    const dist = move.dist(coord);
                    if (@abs(dist[0]) == 1) {
                        if (board.get(move).piece == null) {
                            const tile = board.get(Coord{ .x = move.x, .y = coord.y });
                            if (tile.piece) |p| {
                                if (
                                    p.ptype != .pawn or
                                    p.team == team or
                                    tile.flag != .pawn_en_passant_ready
                                ) continue :thismove;
                                break :ifb true;
                            } else continue :thismove;
                        } else break :ifb false;
                    } else break :ifb false;
                } else false;
            const tile = board.get(coord);
            var new_board = board.*;
            new_board.grid[move.y][move.x] = tile.piece;
            new_board.flags[move.y][move.x] =
                if (
                    ptype == .pawn and
                    @abs(move.dist(coord)[1]) == 2
                ) .pawn_en_passant_ready
                else .moved;
            new_board.grid[coord.y][coord.x] = null;
            new_board.flags[coord.y][coord.x] = .none;
            if (is_en_passant) {
                new_board.grid[coord.y][move.x] = null;
                new_board.flags[coord.y][move.x] = .none;
            }
            if (ptype == .king) {
                if (new_board.is_checked(move, team))
                    continue;
            } else {
                if (new_board.is_checked(my_king, team))
                    continue;
            }
            res.push(move);
        }
        return res;
    }

    pub fn test_move(board: *Board, coord: Coord, move: Coord) Event {
        const tile = board.get(coord);
        const piece = tile.piece.?;
        const team = piece.team;
        const ptype = piece.ptype;
        const rel_coord = move.abs_to_rel(team);
        return
            if (ptype == .pawn and rel_coord.y == size_y - 1) .promotion
            else .none;
    }

    pub fn confirm_move(board: *Board, coord: Coord, move: Coord, data: EventData) void {
        const tile = board.get(coord);
        const piece = tile.piece.?;
        const team = piece.team;
        const ptype = piece.ptype;
        const dist = move.dist(coord);
        var res_flag = Flag.moved;
        var res_ptype = ptype;
        var is_en_passant = false;
        var is_castling = false;
        if (ptype == .pawn and @abs(dist[1]) == 2) {
            res_flag = .pawn_en_passant_ready;
        }
        if (ptype == .pawn and @abs(dist[0]) == 1 and board.grid[move.y][move.x] == null) {
            is_en_passant = true;
        }
        if (ptype == .king and @abs(dist[0]) == 2) {
            is_castling = true;
        }
        if (ptype == .pawn and move.abs_to_rel(team).y == size_y - 1) {
            switch (data) {
                .promotion => |d| {
                    switch (d) {
                        .rook => {
                            res_ptype = PieceType.rook;
                        },
                        .knight => {
                            res_ptype = PieceType.knight;
                        },
                        .bishop => {
                            res_ptype = PieceType.bishop;
                        },
                        .queen => {
                            res_ptype = PieceType.queen;
                        }
                    }
                },
                else => unreachable
            }
        }
        var y: u8 = 0;
        while (y < size_y): (y += 1) {
            var x: u8 = 0;
            while (x < size_x): (x += 1) {
                if (board.flags[y][x] == .pawn_en_passant_ready)
                    board.flags[y][x] = .moved;
            }
        }
        board.grid[coord.y][coord.x] = null;
        board.flags[coord.y][coord.x] = .none;
        board.grid[move.y][move.x] = Piece{
            .team = team,
            .ptype = res_ptype,
        };
        board.flags[move.y][move.x] = res_flag;
        if (is_en_passant) {
            board.grid[coord.y][move.x] = null;
            board.flags[coord.y][move.x] = .none;
        }
        if (is_castling) {
            const rook_x: u8 = if (dist[0] < 0) 0 else size_x - 1;
            const new_rook_x: u8 = if (dist[0] < 0) move.x + 1 else move.x - 1;
            board.grid[move.y][new_rook_x] = board.grid[move.y][rook_x];
            board.flags[move.y][new_rook_x] = board.flags[move.y][rook_x];
            board.grid[move.y][rook_x] = null;
            board.flags[move.y][rook_x] = .none;
        }
    }

    pub fn debug_print(self: *const Board, moves: MoveSet, selected: ?Coord) void {
        var targeted: [size_y][size_x]bool = @splat(@as([size_x]bool, @splat(false)));
        var sel_x: u8 = undefined;
        var sel_y: u8 = undefined;
        var is_selected = false;
        if (selected) |s| {
            is_selected = true;
            sel_x = s.x;
            sel_y = s.y;
        }
        for (0..moves.len) |i| {
            const move = moves.coords[i];
            targeted[move.y][move.x] = true;
        }
        var _y: u8 = 8;
        while (_y > 0): (_y -= 1) {
            const y: u8 = _y - 1;
            var x: u8 = 0;
            while (x < size_x): (x += 1) {
                var symbol: []const u8 = " ";
                const piece = self.grid[y][x];
                if (piece) |p| {
                    const ptype = p.ptype;
                    const team = p.team;
                    symbol = switch (ptype) {
                        .pawn => if (team == .white) "♙" else "♟",
                        .rook => if (team == .white) "♖" else "♜",
                        .knight => if (team == .white) "♘" else "♞",
                        .bishop => if (team == .white) "♗" else "♝",
                        .queen => if (team == .white) "♕" else "♛",
                        .king => if (team == .white) "♔" else "♚"
                    };
                }
                if (targeted[y][x]) std.debug.print("[{s}]", .{ symbol })
                else if (is_selected and sel_x == x and sel_y == y) std.debug.print("<{s}>", .{ symbol })
                else std.debug.print(" {s} ", .{ symbol });
            }
            std.debug.print("\n\n", .{});
        }
    }
};