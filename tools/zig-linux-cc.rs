use std::{env, ffi::OsStr, process::{Command, exit}};

fn main() {
    let zig = env::var_os("KYBER_ZIG_EXE").expect("KYBER_ZIG_EXE must point to zig.exe");
    let repo = env::var("KYBER_REPO_REAL").expect("KYBER_REPO_REAL is required");
    let alias = env::var("KYBER_REPO_ALIAS").expect("KYBER_REPO_ALIAS is required");
    let mut command = Command::new(zig);
    command.args(["cc", "-target", "x86_64-linux-gnu"]);
    for arg in env::args_os().skip(1) {
        // Cargo's cc crate emits the Rust target triple. Zig expects the
        // equivalent shorter spelling and already receives it above.
        if arg != OsStr::new("--target=x86_64-unknown-linux-gnu") {
            // rustc resolves some archive paths to the real workspace under
            // Program Files (x86). Zig's Windows linker loses the spaces there.
            // K: is a verified subst mapping to that same checkout.
            let value = arg.to_string_lossy().replace(&repo, &alias);
            command.arg(value);
        }
    }
    match command.status() {
        Ok(status) => exit(status.code().unwrap_or(1)),
        Err(error) => {
            eprintln!("Failed to run Zig: {error}");
            exit(1);
        }
    }
}
