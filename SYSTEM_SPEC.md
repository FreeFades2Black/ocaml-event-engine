# Specification: Idempotent Event Ingestion Engine

## Target Environment
- Language: OCaml 5.x
- Build System: Dune
- Dependencies: Standard library only (or minimal ppx_deriving if available)

## 1. State Machine
An incoming transaction event moves through strictly four states:
1. `Received`: Initial state containing Event ID (string), Timestamp (int), and Payload (string).
2. `Duplicate`: If the Event ID already exists in the seen set, transition here and discard.
3. `Processed`: If the Event ID is new and Payload is non-empty, record it as seen and transition here.
4. `Invalid`: If the Payload is empty or Event ID is blank, transition here with an error description.

## 2. Invariants
- No duplicate event IDs may enter the `Processed` state.
- Empty payloads must never reach `Processed`.
- Transitions must return an explicit `Result` or domain variant. No exceptions.

## 3. Required Deliverables
1. `lib/event_engine.mli`: Public interface with exact type definitions and signatures.
2. `lib/event_engine.ml`: Implementation satisfying all invariants.
3. `test/test_event_engine.ml`: Test harness covering valid transitions, duplicate detection, and empty payload rejection.
4. `dune-project` and `dune` configuration files configured to compile and run tests.
