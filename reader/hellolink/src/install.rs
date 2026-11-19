//! `install-reader`: the reader installed outside any git checkout, as tools/install_reader.py
//! installs the Python reader (#117, docs/STRIP.md section 10). The folder holds this program
//! (`hellolink`), the capture tool's source and a VERSION file that names the commit. A program
//! that serves the game starts the reader from that folder by its full path, so a checkout or a
//! branch switch never changes the reader it runs next.
//!
//! Nothing changes, and Err says why, when:
//! - a file the program is built from differs from the commit, or the commit lacks it;
//! - one of those files is newer than this program (it was not built from them);
//! - the folder holds anything but an earlier install, Rust or Python;
//! - the reader or the assistant program runs from the folder.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

/// The checkout this program was built from.
pub const CHECKOUT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// What the program is built from, and the capture source it installs, in the checkout.
const SOURCES: [&str; 5] = [
    "reader/Cargo.toml",
    "reader/Cargo.lock",
    "reader/hellolink/Cargo.toml",
    "reader/hellolink/src",
    "tools/strip_capture.swift",
];
const CAPTURE: &str = "tools/strip_capture.swift";
/// What an install holds: this program, the capture source, VERSION.
const FILES: [&str; 2] = ["hellolink", "strip_capture.swift"];
/// What an earlier install of the Python reader holds besides those and its __pycache__.
const PYTHON: [&str; 5] = [
    "hellolink_strip.py",
    "strip1.py",
    "strip_api.py",
    "hellolink.py",
    "assistant.py",
];
/// The programs that run from an install: Rust, then Python.
const PROGRAMS: [&str; 3] = ["hellolink", "hellolink_strip.py", "assistant.py"];

/// The default folder: ~/Library/Application Support/HelloLink/reader.
pub fn default_folder() -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME").ok_or("no home folder (HOME is not set)")?;
    Ok(PathBuf::from(home).join("Library/Application Support/HelloLink/reader"))
}

fn plain(p: &Path) -> bool {
    fs::symlink_metadata(p).is_ok_and(|m| m.is_file())
}

/// True when `to` holds an earlier install (this one's, or the Python reader's) and nothing
/// else: each file plain, at most a __pycache__ folder of plain .pyc files, and VERSION and the
/// capture source, which both kinds hold.
fn is_install(to: &Path) -> bool {
    let Ok(m) = fs::symlink_metadata(to) else {
        return false;
    };
    let Ok(entries) = fs::read_dir(to) else {
        return false;
    };
    if !m.is_dir() {
        return false;
    }
    for entry in entries {
        let Ok(entry) = entry else { return false };
        let (path, name) = (entry.path(), entry.file_name());
        let name = name.to_string_lossy();
        let ok = if name == "VERSION" || FILES.contains(&&*name) || PYTHON.contains(&&*name) {
            plain(&path)
        } else if name == "__pycache__" {
            fs::symlink_metadata(&path).is_ok_and(|m| m.is_dir())
                && fs::read_dir(&path).is_ok_and(|inside| {
                    inside.into_iter().all(|q| {
                        q.is_ok_and(|q| {
                            plain(&q.path()) && q.path().extension().is_some_and(|x| x == "pyc")
                        })
                    })
                })
        } else {
            false
        };
        if !ok {
            return false;
        }
    }
    plain(&to.join("VERSION")) && plain(&to.join("strip_capture.swift"))
}

/// Why the install must not go into `to`, or None.
fn refusal(to: &Path) -> Option<String> {
    if to.exists() && !is_install(to) {
        return Some(format!(
            "{} is not an earlier reader install (it holds other things); give another --to",
            to.display()
        ));
    }
    let listed = Command::new("ps").args(["-axo", "pid=,args="]).output();
    let runs = match listed {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).into_owned(),
        Ok(out) => {
            return Some(format!(
                "cannot list the processes to see if a program runs from {} (ps: {})",
                to.display(),
                out.status
            ));
        }
        Err(e) => {
            return Some(format!(
                "cannot list the processes to see if a program runs from {} (ps: {e})",
                to.display()
            ));
        }
    };
    let me = std::process::id().to_string();
    let mine: Vec<&str> = runs
        .lines()
        .map(str::trim)
        .filter(|line| line.split_whitespace().next() != Some(me.as_str()))
        .filter(|line| {
            PROGRAMS
                .iter()
                .any(|p| line.contains(&*to.join(p).to_string_lossy()))
        })
        .collect();
    (!mine.is_empty()).then(|| {
        format!(
            "the reader or the assistant program runs from {}; stop it first:\n{}",
            to.display(),
            mine.join("\n")
        )
    })
}

fn git(checkout: &Path, args: &[&str]) -> Result<Vec<u8>, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(checkout)
        .args(args)
        .output()
        .map_err(|e| format!("git: {e}"))?;
    if out.status.success() {
        Ok(out.stdout)
    } else {
        Err(format!(
            "git {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ))
    }
}

/// The commit, when every file the program is built from equals it and none is newer than
/// the program `exe`; else Err.
fn commit_of(checkout: &Path, exe: &Path) -> Result<String, String> {
    let commit = String::from_utf8_lossy(&git(checkout, &["rev-parse", "HEAD"])?)
        .trim()
        .to_string();
    let short = &commit[..7.min(commit.len())];
    let mut args = vec!["ls-tree", "-r", "--name-only", &commit, "--"];
    args.extend(SOURCES);
    let listed = String::from_utf8_lossy(&git(checkout, &args)?).into_owned();
    let names: Vec<&str> = listed.lines().collect();
    if !names.contains(&CAPTURE) {
        return Err(format!(
            "{short} lacks {CAPTURE}; commit or restore it first"
        ));
    }
    let built = fs::metadata(exe)
        .and_then(|m| m.modified())
        .map_err(|e| format!("{}: {e}", exe.display()))?;
    for name in names {
        let path = checkout.join(name);
        let committed = git(checkout, &["show", &format!("{commit}:./{name}")])?;
        if fs::read(&path).ok().as_deref() != Some(&committed[..]) {
            return Err(format!(
                "{name} differs from {short}, or it is missing; commit or restore it first"
            ));
        }
        let changed = fs::metadata(&path)
            .and_then(|m| m.modified())
            .map_err(|e| format!("{name}: {e}"))?;
        if changed > built {
            return Err(format!(
                "{name} is newer than {}: build it first (cargo build --release)",
                exe.display()
            ));
        }
    }
    Ok(commit)
}

/// A new, empty folder `<parent>/.reader-<what>-<pid>-<n>`.
fn new_folder(parent: &Path, what: &str) -> Result<PathBuf, String> {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    loop {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let dir = parent.join(format!(".reader-{what}-{}-{n}", std::process::id()));
        match fs::create_dir(&dir) {
            Ok(()) => return Ok(dir),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("{}: {e}", dir.display())),
        }
    }
}

/// `to` made absolute, its links resolved as far as it exists (Python's resolve()).
fn resolved(to: &Path) -> Result<PathBuf, String> {
    let to = std::path::absolute(to).map_err(|e| format!("{}: {e}", to.display()))?;
    let mut tail = Vec::new();
    let mut head = to.as_path();
    loop {
        if let Ok(real) = fs::canonicalize(head) {
            return Ok(tail.iter().rev().fold(real, |p, part| p.join(part)));
        }
        match (head.parent(), head.file_name()) {
            (Some(up), Some(name)) => {
                tail.push(name.to_owned());
                head = up;
            }
            _ => return Ok(to),
        }
    }
}

/// Installs this program (`exe`) and the capture source of `checkout` into `to`. Ok is the
/// line to print.
pub fn install_reader(to: &Path, checkout: &Path, exe: &Path) -> Result<String, String> {
    let to = resolved(to)?;
    if let Some(why) = refusal(&to) {
        return Err(why);
    }
    let commit = commit_of(checkout, exe)?;
    let parent = to.parent().ok_or("--to has no parent folder")?;
    fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    let new = new_folder(parent, "new")?;
    let filled = (|| {
        let at = |p: &Path| format!("{}", p.display());
        fs::copy(exe, new.join("hellolink")).map_err(|e| format!("{}: {e}", at(exe)))?;
        // A new file, so a new time: the reader then rebuilds the capture tool from it.
        let source = fs::read(checkout.join(CAPTURE)).map_err(|e| format!("{CAPTURE}: {e}"))?;
        fs::write(new.join("strip_capture.swift"), source).map_err(|e| e.to_string())?;
        fs::write(new.join("VERSION"), format!("{commit}\n")).map_err(|e| e.to_string())?;
        if to.exists() {
            let old = new_folder(parent, "old")?;
            if let Err(e) = fs::rename(&to, old.join("reader")) {
                let _ = fs::remove_dir(&old);
                return Err(format!("{}: {e}", to.display()));
            }
            if let Err(e) = fs::rename(&new, &to) {
                let _ = fs::rename(old.join("reader"), &to);
                return Err(format!("{}: {e}", to.display()));
            }
            let _ = fs::remove_dir_all(&old);
        } else {
            fs::rename(&new, &to).map_err(|e| format!("{}: {e}", to.display()))?;
        }
        Ok(())
    })();
    if new.exists() {
        let _ = fs::remove_dir_all(&new);
    }
    filled?;
    Ok(format!(
        "{} installed in {}; start the reader from there",
        &commit[..7.min(commit.len())],
        to.display()
    ))
}
