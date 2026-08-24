-module(functional_soak_entry).

-export([start/0]).

start() ->
    timer:sleep(3000),
    io:format("AVM_CBOR_FUNCTIONAL_SOAK_BEGIN~n", []),
    ok = avm_cbor_atomvm:start(),
    io:format("AVM_CBOR_FUNCTIONAL_TESTS_OK~n", []),
    ok = avm_cbor_hardware_soak:start(),
    io:format("AVM_CBOR_FUNCTIONAL_SOAK_OK~n", []),
    io:format("AVM_CBOR_FUNCTIONAL_SOAK_RUN_OK~n", []),
    ok.
