# Stage 1: Build the static binary using OCaml with musl libc
FROM ocaml/opam:alpine-ocaml-5.2 AS builder

# Switch to root to configure working directory permissions
USER root
WORKDIR /home/opam/app
RUN chown -R opam:opam /home/opam/app

# Switch back to the unprivileged opam user
USER opam

# Install Dune build system
RUN opam install -y dune

# Install project build dependencies and project definition
COPY --chown=opam:opam dune-project ./
COPY --chown=opam:opam lib/ ./lib/
COPY --chown=opam:opam bin/ ./bin/
COPY --chown=opam:opam test/ ./test/

# Build project and run validation test harness
RUN eval $(opam env) && \
    dune build && \
    dune runtest && \
    dune build --profile release bin/main.exe

# Strip unneeded debug symbols from the static binary
USER root
RUN strip /home/opam/app/_build/default/bin/main.exe -o /ocaml-event-engine

# Verify the binary is truly static (exits with error if dynamic links exist)
RUN ldd /ocaml-event-engine 2>&1 | grep -q "Not a valid dynamic program"

# Stage 2: Final zero-dependency scratch image
FROM scratch

# Copy only the compiled static executable
COPY --from=builder /ocaml-event-engine /ocaml-event-engine

# Expose Prometheus HTTP metrics port
EXPOSE 9100

# Expose standard execution entrypoint
ENTRYPOINT ["/ocaml-event-engine"]
