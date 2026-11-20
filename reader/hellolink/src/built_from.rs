//! What a build is made from, as one number: FNV-1a (64 bits) over each input file's path (from
//! reader/), a 0 byte, its length and its bytes, in path order. build.rs writes it into the
//! program (`HELLOLINK_BUILT_FROM`); `install-reader` works it out from a commit's files, so it
//! installs only a program built from that commit. The inputs: reader/Cargo.toml,
//! reader/Cargo.lock, hellolink/Cargo.toml, hellolink/build.rs and every .rs file under
//! hellolink/src but src/bin (the tests' own programs).
//! Not a defence against an attacker: it tells two builds apart.

/// True when `path` (from reader/) is an input of the build.
pub fn is_input(path: &str) -> bool {
    matches!(
        path,
        "Cargo.toml" | "Cargo.lock" | "hellolink/Cargo.toml" | "hellolink/build.rs"
    ) || (path.starts_with("hellolink/src/")
        && !path.starts_with("hellolink/src/bin/")
        && path.ends_with(".rs"))
}

/// FNV-1a, 64 bits, carried on from `hash` (start with FNV_START).
pub fn fnv(mut hash: u64, bytes: &[u8]) -> u64 {
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

pub const FNV_START: u64 = 0xcbf2_9ce4_8422_2325;

/// The digest of (path, bytes) pairs, sorted by path here, as 16 hex digits.
pub fn digest(mut files: Vec<(String, Vec<u8>)>) -> String {
    files.sort();
    let mut hash = FNV_START;
    for (path, bytes) in &files {
        hash = fnv(hash, path.as_bytes());
        hash = fnv(hash, &[0]);
        hash = fnv(hash, &(bytes.len() as u64).to_le_bytes());
        hash = fnv(hash, bytes);
    }
    format!("{hash:016x}")
}
