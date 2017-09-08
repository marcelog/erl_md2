% http://www.umich.edu/~x509/ssleay/rfc1319.html
% http://www.rfc-editor.org/errata/rfc1319
-module(erl_md2_new).

-export([ctx_init/0, ctx_update/2, ctx_final/1]).
-export([full_test/0]).
-define(BINTABLE, "0123456789abcdef").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public functions.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ctx_init() ->
  #{
    buffer => <<>>,
    checksum => mapbuf_init(16),
    state => mapbuf_init(48),
    s_table => s_table_gen(),
    length => 0,
    checksum_L => 0
  }.

ctx_update(Ctx, Data) ->
  Buffer = ctx_get(Ctx, buffer),
  NewCtx = ctx_put(Ctx, buffer, <<>>),
  NewBuffer = <<Buffer/binary, Data/binary>>,
  ctx_transform(NewCtx, NewBuffer).

ctx_final(Ctx) ->
  RestData = pad(ctx_get(Ctx, buffer)),
  NewCtx = ctx_put(Ctx, buffer, <<>>),

  NewCtx2 = ctx_update(NewCtx, RestData),

  Checksum = mapbuf_2bin(ctx_get(NewCtx2, checksum)),
  NewCtx3 = ctx_update(NewCtx2, Checksum),

  State = ctx_get(NewCtx3, state),

  Hash = lists:foldl(
    fun(Index, Acc) -> <<Acc/binary, (mapbuf_at(State, Index))/integer>> end,
    <<>>,
    lists:seq(0, 15)
  ),
  bin2ascii(Hash).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private functions.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MD2 Core
ctx_transform(Ctx, <<Block:16/binary, Rest/binary>>) ->
  NewCtx = checksum(Ctx, Block),
  NewCtx2 = compute(NewCtx, Block),
  Length = ctx_get(NewCtx2, length),
  NewCtx3 = ctx_put(NewCtx2, length, Length + 16),
  ctx_transform(NewCtx3, Rest);

ctx_transform(Ctx, Data) ->
  ctx_put(Ctx, buffer, Data).

compute(Ctx, Block) ->
  % Set t to 0.
  %
  % /* Do 18 rounds. */
  % For j = 0 to 17 do
  %
  %   /* Round j. */
  %   For k = 0 to 47 do
  %       Set t and X[k] to (X[k] xor S[t]).
  %   end /* of loop on k */
  %
  %   Set t to (t+j) modulo 256.
  %
  % end /* of loop on j */

  NewCtx = copy_block(Ctx, Block),
  NewCtx2 = do_rounds(NewCtx),
  NewCtx2.

do_rounds(Ctx) ->
  T = 0,
  next_round(Ctx, T, 0).

next_round(Ctx, _T, 18) ->
  Ctx;

next_round(Ctx, T, RoundN) ->
  {NewCtx, NewT} = round(Ctx, T, RoundN, 0),
  next_round(NewCtx, NewT, RoundN + 1).

round(Ctx, T, RoundN, 48) ->
  NewT = (T + RoundN) rem 256,
  {Ctx, NewT};

round(Ctx, T, RoundN, IterationN) ->
  STable = ctx_get(Ctx, s_table),
  State = ctx_get(Ctx, state),
  SValue = mapbuf_at(STable, T),
  StateValue = mapbuf_at(State, IterationN),
  NewT = StateValue bxor SValue,
  NewState = mapbuf_set(State, IterationN, NewT),
  NewCtx = ctx_put(Ctx, state, NewState),
  round(NewCtx, NewT, RoundN, IterationN + 1).

copy_block(Ctx, Block) ->
  % /* Copy block i into X. */
  % For j = 0 to 15 do
  %   Set X[16+j] to M[i*16+j].
  %   Set X[32+j] to (X[16+j] xor X[j]).
  %  end /* of loop on j */
  <<
    B1, B2, B3, B4, B5, B6, B7, B8,
    B9, B10, B11, B12, B13, B14, B15, B16
  >> = Block,
  Bytes = [
    B1, B2, B3, B4, B5, B6, B7, B8,
    B9, B10, B11, B12, B13, B14, B15, B16
  ],
  {_, NewContext} = lists:foldl(
    fun(Byte, {AccIndex, AccContext}) ->
      State = ctx_get(AccContext, state),
      NewState = mapbuf_set(State, AccIndex + 16, Byte),

      StateValue = mapbuf_at(NewState, AccIndex),
      XorValue = Byte bxor StateValue,
      NewState2 = mapbuf_set(NewState, AccIndex + 32, XorValue),

      NewAccContext = ctx_put(AccContext, state, NewState2),
      {AccIndex + 1, NewAccContext}
    end,
    {0, Ctx},
    Bytes
  ),
  NewContext.

% Checksum Routines
checksum(Ctx, Block) ->
  % For j = 0 to 15 do
  %   Set c to M[i*16+j].
  %   Set C[j] to S[c xor L].
  %   Set L to C[j].
  % end
  <<
    B1, B2, B3, B4, B5, B6, B7, B8,
    B9, B10, B11, B12, B13, B14, B15, B16
  >> = Block,
  Bytes = [
    B1, B2, B3, B4, B5, B6, B7, B8,
    B9, B10, B11, B12, B13, B14, B15, B16
  ],
  STable = ctx_get(Ctx, s_table),
  {_, NewContext} = lists:foldl(
    fun(Byte, {AccIndex, AccContext}) ->
      L = ctx_get(AccContext, checksum_L),
      XorValue = Byte bxor L,
      SValue = mapbuf_at(STable, XorValue),

      Checksum = ctx_get(AccContext, checksum),
      ChecksumValue = mapbuf_at(Checksum, AccIndex),
      ChecksumXorValue = ChecksumValue bxor SValue,

      NewChecksum = mapbuf_set(Checksum, AccIndex, ChecksumXorValue),
      NewAccContext = ctx_put(AccContext, checksum, NewChecksum),

      NewL = ChecksumXorValue,
      NewAccContext2 = ctx_put(NewAccContext, checksum_L, NewL),

      {AccIndex + 1, NewAccContext2}
    end,
    {0, Ctx},
    Bytes
  ),
  NewContext.

% Context Management
ctx_put(Ctx, Key, Value) ->
  maps:put(Key, Value, Ctx).

ctx_get(Ctx, Key) ->
  maps:get(Key, Ctx).

pad(Data) ->
  ByteSize = size(Data),
  Rem = ByteSize rem 16,
  PadBlockSize = 16 - Rem,
  PadString = pad_string(PadBlockSize),
  <<Data/binary, PadString/binary>>.

pad_string(0) -> <<>>;
pad_string(Size) ->
  lists:foldl(
    fun(_, Acc) -> <<Acc/binary, Size:8/integer>> end,
    <<>>,
    lists:seq(0, Size - 1)
  ).

s_table_gen() ->
  List = [
    41, 46, 67, 201, 162, 216, 124, 1, 61, 54, 84, 161, 236, 240, 6,
    19, 98, 167, 5, 243, 192, 199, 115, 140, 152, 147, 43, 217, 188,
    76, 130, 202, 30, 155, 87, 60, 253, 212, 224, 22, 103, 66, 111, 24,
    138, 23, 229, 18, 190, 78, 196, 214, 218, 158, 222, 73, 160, 251,
    245, 142, 187, 47, 238, 122, 169, 104, 121, 145, 21, 178, 7, 63,
    148, 194, 16, 137, 11, 34, 95, 33, 128, 127, 93, 154, 90, 144, 50,
    39, 53, 62, 204, 231, 191, 247, 151, 3, 255, 25, 48, 179, 72, 165,
    181, 209, 215, 94, 146, 42, 172, 86, 170, 198, 79, 184, 56, 210,
    150, 164, 125, 182, 118, 252, 107, 226, 156, 116, 4, 241, 69, 157,
    112, 89, 100, 113, 135, 32, 134, 91, 207, 101, 230, 45, 168, 2, 27,
    96, 37, 173, 174, 176, 185, 246, 28, 70, 97, 105, 52, 64, 126, 15,
    85, 71, 163, 35, 221, 81, 175, 58, 195, 92, 249, 206, 186, 197,
    234, 38, 44, 83, 13, 110, 133, 40, 132, 9, 211, 223, 205, 244, 65,
    129, 77, 82, 106, 220, 55, 200, 108, 193, 171, 250, 36, 225, 123,
    8, 12, 189, 177, 74, 120, 136, 149, 139, 227, 99, 232, 109, 233,
    203, 213, 254, 59, 0, 29, 57, 242, 239, 183, 14, 102, 88, 208, 228,
    166, 119, 114, 248, 235, 117, 75, 10, 49, 68, 80, 180, 143, 237,
    31, 26, 219, 153, 141, 51, 159, 17, 131, 20
  ],
  {_, Map} = lists:foldl(
    fun(V, {K, Map}) -> {K + 1, maps:put(K, V, Map)} end,
    {0, #{}},
    List
  ),
  Map.

mapbuf_init(Size) ->
  lists:foldl(
    fun(Index, Map) -> maps:put(Index, 0, Map) end,
    #{},
    lists:seq(0, Size - 1)
  ).

mapbuf_at(Map, Index) ->
  maps:get(Index, Map).

mapbuf_set(Map, Index, Value) ->
  maps:put(Index, Value, Map).

mapbuf_2bin(Map) ->
  Size = maps:size(Map) - 1,
  BinList = [maps:get(Index, Map) || Index <- lists:seq(0, Size)],
  lists:foldl(
    fun(B, Acc) -> <<Acc/binary, B/integer>> end,
    <<>>,
    BinList
  ).

bin2ascii(Data) ->
  bin2ascii(Data, []).

bin2ascii(<<>>, Acc) ->
  lists:reverse(Acc);

bin2ascii(<<A:4/integer, B:4/integer, Rest/binary>>, Acc) ->
  L = lists:nth(A + 1, ?BINTABLE),
  H = lists:nth(B + 1, ?BINTABLE),
  bin2ascii(Rest, [H, L|Acc]).

full_test() ->
  Suite = [
    {<<>>, "8350e5a3e24c153df2275c9f80692773"},
    {<<"a">>, "32ec01ec4a6dac72c0ab96fb34c0b5d1"},
    {<<"abc">>, "da853b0d3f88d99b30283a69e6ded6bb"},
    {<<"message digest">>, "ab4f496bfb2a530b219ff33031fe06b0"},
    {<<"abcdefghijklmnopqrstuvwxyz">>, "4e8ddff3650292ab5a4108c3aa47940b"},
    {
      <<"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789">>,
      "da33def2a42df13975352846c30338cd"
    },
    {
      <<"12345678901234567890123456789012345678901234567890123456789012345678901234567890">>,
      "d5976f79d83d3a0dc9806c3c66f3efd8"
    }
  ],
  [
    begin
      Ctx = ctx_init(),
      NewCtx = ctx_update(Ctx, Data),
      Hash = ctx_final(NewCtx)
    end
    || {Data, Hash} <- Suite
  ].
