# AtomVM memory mechanics used by `avm_cbor`

This note is pinned to AtomVM commit
[`ff993a80963298b532c1e573f883951ecaac9fef`](https://github.com/atomvm/AtomVM/tree/ff993a80963298b532c1e573f883951ecaac9fef).
Every numeric statement below comes from that revision. It is not a promise
about another AtomVM release or a different `TERM_BYTES` build.

## Binary representation thresholds and descriptors

- On a 32-bit term build, binaries smaller than 32 bytes are heap binaries;
  size 32 and above selects the reference-counted representation. On a 64-bit
  term build the boundary is 64 bytes. The constants are defined at
  [`src/libAtomVM/term.h:69-81`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.h#L69-L81),
  and the strict `< REFC_BINARY_MIN` decision is implemented at
  [`src/libAtomVM/term.h:921-931`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.h#L921-L931).
- The process-heap descriptor is six words for a refc binary, four words for a
  sub-binary, and four base words plus one word per saved slot for a binary
  match state. The constants are at
  [`src/libAtomVM/term.h:69-72`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.h#L69-L72),
  while match-state allocation is the literal `base + slots` operation at
  [`src/libAtomVM/term.h:1628-1649`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.h#L1628-L1649).
- A sub-binary is considered only when its source is already refc/sub-binary
  and its length is at least 8 bytes on 32-bit terms or 16 bytes on 64-bit
  terms. Otherwise AtomVM creates a new binary. The size calculation and
  selection are at
  [`src/libAtomVM/term.h:1065-1106`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.h#L1065-L1106).
  The four descriptor fields are header, length, offset, and underlying binary,
  as initialized at
  [`src/libAtomVM/term.c:723-733`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.c#L723-L733).
- A non-constant refc binary owns a separately allocated `RefcBinary`; allocation
  failure currently aborts AtomVM. The six-word descriptor, initial reference
  count, MSO-list insertion, and abort path are visible at
  [`src/libAtomVM/term.c:683-707`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.c#L683-L707).
  Consequently, a configured CBOR byte limit is an admission ceiling, not proof
  that every target has enough physical memory to construct a binary of that
  size.

## Tuple, list, heap, and stack word costs

- An `N`-element tuple occupies `N + 1` words, including its header. A cons
  cell occupies two words. These are the exact `TUPLE_SIZE` and `CONS_SIZE`
  macros at
  [`src/libAtomVM/term.h:83-95`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/term.h#L83-L95).
- `Heap` stores `heap_start`, upward-growing `heap_ptr`, and `heap_end` beside
  its root fragment at
  [`src/libAtomVM/memory.h:68-88`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/memory.h#L68-L88).
  A new process starts with eight term words and places the stack pointer `e`
  at `heap_end`, so heap and stack initially grow toward one another in the
  same fragment:
  [`src/libAtomVM/context.c:52-72`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/context.c#L52-L72).
  Available terms are therefore computed from the gap between `heap_ptr` and
  `e` when the stack is in the current fragment:
  [`src/libAtomVM/context.h:298-325`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/context.h#L298-L325).
- There is no universal numeric process-heap cap in this source. Each context
  carries optional `min_heap_size` and `max_heap_size` fields and flags at
  [`src/libAtomVM/context.h:83-124`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/context.h#L83-L124).
  When the maximum flag is set, a GC growth target above that value is denied
  at
  [`src/libAtomVM/memory.c:179-209`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/memory.c#L179-L209).
  Otherwise the practical ceiling is successful platform allocation, so this
  document intentionally does not invent a fixed heap limit.
- `process_info/2` reports `heap_size` and `total_heap_size` in words,
  `stack_size` in words, and process `memory` in bytes. The exact calculations
  are at
  [`src/libAtomVM/context.c:397-475`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/context.c#L397-L475).
  Those are the counters emitted by the hardware stress harness; sampled stack
  values are observable checkpoints, not an interrupt-time stack profiler.

## Copying garbage collection

- `memory_ensure_free_with_roots` requests GC when space is insufficient,
  forced shrink is requested, or heap fragments exist. It calculates the next
  target using the selected heap-growth strategy and enforces an optional
  maximum at
  [`src/libAtomVM/memory.c:150-210`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/memory.c#L150-L210).
- The collector allocates a new heap, copies the stack, process dictionary,
  extended registers, exit reason, and explicit roots, then repeatedly scans
  and copies newly reached terms:
  [`src/libAtomVM/memory.c:257-316`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/memory.c#L257-L316).
  It finally sweeps the old MSO list and destroys the old fragment at
  [`src/libAtomVM/memory.c:318-323`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/memory.c#L318-L323).
- This pinned AtomVM exposes explicit `garbage_collect` but no automatic-GC
  count or pause-time process-info item: the supported keys are enumerated at
  [`src/libAtomVM/context.c:397-428`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/context.c#L397-L428),
  and the explicit-GC NIF forces shrink at
  [`src/libAtomVM/nifs.c:3370-3402`](https://github.com/atomvm/AtomVM/blob/ff993a80963298b532c1e573f883951ecaac9fef/src/libAtomVM/nifs.c#L3370-L3402).
  Hardware evidence therefore labels its count and maximum pause as
  `explicit_gc_count` and `explicit_gc_pause_max_us`; it does not mislabel
  them as unobservable automatic-GC totals.

## Consequences for the continuation API

`decode_continue/2` bounds interpreter-visible parsing work and keeps parser
frames as data between calls. It cannot change the fact that its
`decode_start(Binary, Options)` argument already exists as a complete Erlang
binary. In particular, the 1 MiB default `max_bytes` value is a rejection
boundary, not a guarantee that a 264 KiB-RAM RP2040 can materialize a 1 MiB
binary. A clean physical proof must distinguish scheduler progress from input
storage capacity rather than using PSRAM or a watchdog change to hide either
constraint.

