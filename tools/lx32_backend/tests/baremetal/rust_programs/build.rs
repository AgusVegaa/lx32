// build.rs — runs on the HOST to inject linker arguments.
//
// Adds two things that can't be put in config.toml as relative paths:
//   1. The baremetal linker script (link.ld).
//   2. The startup object (crt0.o) — provides _start, which calls main().
//
// crt0.o is assembled from crt0.S by `run_rust_firmware.sh` before this
// build runs.  The Makefile's `test-rust-firmware` target orchestrates both.

use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let baremetal = manifest.parent().expect("rust_programs has no parent");

    let link_ld = baremetal.join("link.ld");
    let crt0_o  = baremetal.join("crt0.o");

    println!("cargo:rustc-link-arg=-T{}", link_ld.display());
    println!("cargo:rustc-link-arg={}", crt0_o.display());

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed={}", crt0_o.display());
    println!("cargo:rerun-if-changed={}", link_ld.display());
}
