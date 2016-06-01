import vibe.data.json;


void main()
{
    auto data =
`[
   [1],
   [2]
]
`;

   Json j = data.parseJson;

   import std.array : appender;
   auto a = appender!(int[]);
   foreach (i; 0 .. 1_000) a ~= i;

   import std.stdio;
   write(j[0][0] == 1 ? "PASS" : "FAIL");
   write(j[1][0] == 2 ? "PASS" : "FAIL");
}
