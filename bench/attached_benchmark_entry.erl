-module(attached_benchmark_entry).
-export([start/0]).

start() ->
    %% Give the host time to reopen the serial port after flashing/resetting.
    timer:sleep(3000),
    cbor_release_benchmark:start().
