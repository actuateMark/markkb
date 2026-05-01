---
title: "Adpro Puller"
type: entity
topic: vms-connector
tags: [rust, ffi, adpro, video-streaming, rtsp, cross-compilation, wine]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/integrations/adpro/_summary.md
  - topics/integrations/adpro/notes/entities/adpro-components.md
incoming_updated: 2026-05-01
---

# Adpro Puller

Rust workspace that pulls video streams from Adpro XO video transmitters and re-serves them as [[rtsp-deep-dive|RTSP]]. The Adpro XO SDK is a proprietary C/C++ library; this project wraps it via Rust FFI bindings so the puller application itself is written in safe, idiomatic Rust.

Repository: `adpro_puller`

## Workspace Crates

| Crate | Type | Purpose |
|-------|------|---------|
| `adpro_puller` | binary | Main stream-puller application. Reads `settings.json` for server IP, credentials, and camera channels, then connects and pulls streams. |
| `adpro_api` | binary | HTTP API for interacting with the Adpro SDK at runtime (handlers in `src/handler/`). |
| `adpro_lib` | library | Streaming and control logic -- callbacks, camera management, connection lifecycle, and state tracking. |
| `adpro_sdk` | library | Low-level FFI bindings to the C/C++ Adpro XO SDK, plus safe Rust wrappers and error types. Modules: `bindings`, `callbacks`, `cameras`, `errors`, `instances`, `sdk`, `types`. |
| `actuate_rtsp_server` | library | GStreamer-based [[rtsp-deep-dive|RTSP]] server that re-publishes the pulled streams. |

## FFI Design

The SDK bindings are generated or manually written in `adpro_sdk`. Callbacks from C into Rust require careful lifetime management: data passed to C callbacks is heap-allocated via `Box::into_raw` to outlive the Rust stack frame, and all callback bodies are wrapped in `catch_unwind` to prevent Rust panics from unwinding into C code (which would be undefined behavior). The workspace uses `unsafe extern "C"` function signatures and `Option<unsafe extern "C" fn ...>` patterns from bindgen.

## Cross-Compilation and Runtime

The build system uses `cargo-xwin` to cross-compile for `x86_64-pc-windows-msvc` from Linux. A dedicated compiler Docker image (pushed to ECR at `388576304176.dkr.ecr.us-west-2.amazonaws.com/adpro-compiler`) contains Wine, Rust, and cargo-xwin. The compiled Windows binary runs on Linux inside a Wine container, trading a small performance penalty for a portable runtime.

Release builds enable LTO and single codegen unit (`Cargo.toml` profile).

## Build and Deploy

`just` is the task runner. Key targets:

- `build` / `build-ci` -- debug and release builds for both puller and API.
- `cargo-build` -- delegates to cargo-xwin inside the compiler image (or directly if `ADPRO_COMPILER=true`).
- `ecr-push-puller` / `ecr-push-api` -- push release images to ECR.
- `run-puller <deployment_id>` -- local Docker run with AWS credentials.

Deployment is managed via [[argocd|ArgoCD]] (`argocd/application.yaml` and `argocd/deployments/`). Images are pushed to the `us-west-2` ECR registry.

## Configuration

`settings.json` specifies the Adpro server connection (IP, port, credentials) and per-camera channel mappings with [[rtsp-deep-dive|RTSP]] base URLs. The puller reads a `DEPLOYMENT_ID` environment variable at runtime.

## Development

Development uses a VSCode Dev Container with all required tooling pre-installed. The `rust-toolchain.toml` pins the Rust version for reproducibility.
