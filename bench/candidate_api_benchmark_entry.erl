-module(candidate_api_benchmark_entry).

-export([start/0]).

start() ->
    cbor_candidate_api_benchmark:start().
