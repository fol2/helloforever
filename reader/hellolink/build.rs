//! Writes into the program what it is built from (src/built_from.rs), for `install-reader`.

#[path = "src/built_from.rs"]
mod built_from;

use std::fs;
use std::path::{Path, PathBuf};

/// Every file under `dir`, as `<prefix>/<path from dir>`.
fn walk(dir: &Path, prefix: &str, out: &mut Vec<(String, PathBuf)>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let (path, name) = (entry.path(), entry.file_name());
        let name = format!("{prefix}/{}", name.to_string_lossy());
        if path.is_dir() {
            walk(&path, &name, out);
        } else {
            out.push((name, path));
        }
    }
}

fn main() {
    let krate = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap_or_default());
    let reader = krate.join("..");
    let mut paths = vec![
        ("Cargo.toml".to_string(), reader.join("Cargo.toml")),
        ("Cargo.lock".to_string(), reader.join("Cargo.lock")),
        ("hellolink/Cargo.toml".to_string(), krate.join("Cargo.toml")),
    ];
    walk(&krate.join("src"), "hellolink/src", &mut paths);
    let mut files = Vec::new();
    for (name, path) in paths {
        if built_from::is_input(&name) {
            println!("cargo:rerun-if-changed={}", path.display());
            if let Ok(bytes) = fs::read(&path) {
                files.push((name, bytes));
            }
        }
    }
    // a new file under src/ runs this again too
    println!("cargo:rerun-if-changed={}", krate.join("src").display());
    println!(
        "cargo:rustc-env=HELLOLINK_BUILT_FROM={}",
        built_from::digest(files)
    );
}
