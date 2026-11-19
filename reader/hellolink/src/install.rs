//! `install-reader`: the reader installed outside any git checkout, as tools/install_reader.py
//! installs the Python reader (#117, docs/STRIP.md section 10). The folder holds this program
//! (`hellolink`), the capture tool's source and a VERSION file that names the commit. A program
//! that serves the game starts the reader from that folder by its full path, so a checkout or a
//! branch switch never changes the reader it runs next.
//!
//! VERSION is true by construction: the program is installed only when the files it was built
//! from (built_from.rs) are those of the commit, and the capture source is taken from the
//! commit, not from the working tree. Nothing changes, and Err says why, when:
//! - the program was not built from the commit, or the commit lacks an input or the source;
//! - the folder holds anything but a whole earlier install, Rust or Python;
//! - the reader or the assistant program runs from the folder (checked again just before the
//!   folder is replaced).

use crate::built_from;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

/// The checkout this program was built from.
pub const CHECKOUT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// What this program was built from (build.rs).
pub const BUILT_FROM: &str = env!("HELLOLINK_BUILT_FROM");
const CAPTURE: &str = "tools/strip_capture.swift";
/// A whole install of this program.
const RUST: [&str; 3] = ["hellolink", "strip_capture.swift", "VERSION"];
/// A whole install of the Python reader (#117); `assistant.py` came later (#133).
const PYTHON: [&str; 6] = [
    "hellolink_strip.py",
    "strip1.py",
    "strip_api.py",
    "hellolink.py",
    "strip_capture.swift",
    "VERSION",
];
const PYTHON_LATER: &str = "assistant.py";
/// The Python programs that run from an install, found by their path in `ps`.
const PYTHON_PROGRAMS: [&str; 2] = ["hellolink_strip.py", "assistant.py"];

/// The default folder: ~/Library/Application Support/HelloLink/reader.
pub fn default_folder() -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME").ok_or("no home folder (HOME is not set)")?;
    Ok(PathBuf::from(home).join("Library/Application Support/HelloLink/reader"))
}

fn plain(p: &Path) -> bool {
    fs::symlink_metadata(p).is_ok_and(|m| m.is_file())
}

/// True when `to` holds a whole earlier install (this one's, or the Python reader's) and
/// nothing else: each file plain, and for Python at most a __pycache__ folder of .pyc files.
fn is_install(to: &Path) -> bool {
    if !fs::symlink_metadata(to).is_ok_and(|m| m.is_dir()) {
        return false;
    }
    let Ok(entries) = fs::read_dir(to) else {
        return false;
    };
    let mut names = Vec::new();
    for entry in entries {
        let Ok(entry) = entry else { return false };
        let (path, name) = (
            entry.path(),
            entry.file_name().to_string_lossy().into_owned(),
        );
        let ok = if name == "__pycache__" {
            fs::symlink_metadata(&path).is_ok_and(|m| m.is_dir())
                && fs::read_dir(&path).is_ok_and(|inside| {
                    inside.into_iter().all(|q| {
                        q.is_ok_and(|q| {
                            plain(&q.path()) && q.path().extension().is_some_and(|x| x == "pyc")
                        })
                    })
                })
        } else {
            plain(&path)
        };
        if !ok {
            return false;
        }
        names.push(name);
    }
    let has = |want: &[&str]| want.iter().all(|w| names.iter().any(|n| n == w));
    let only = |allowed: &[&str]| names.iter().all(|n| allowed.contains(&n.as_str()));
    let rust = has(&RUST) && only(&RUST);
    let mut python_names = PYTHON.to_vec();
    python_names.extend([PYTHON_LATER, "__pycache__"]);
    let python = has(&PYTHON) && only(&python_names);
    rust || python
}

/// The processes that run a reader or the assistant from `to`, or Err when they cannot be
/// listed. This program is found by its file (`lsof`, which sees it however it was started);
/// the Python programs by their path in `ps`.
fn running(to: &Path) -> Result<Vec<String>, String> {
    let cannot = |what: &str, why: String| {
        format!(
            "cannot list the processes to see if a program runs from {} ({what}: {why})",
            to.display()
        )
    };
    let out = Command::new("ps")
        .args(["-axo", "pid=,args="])
        .output()
        .map_err(|e| cannot("ps", e.to_string()))?;
    if !out.status.success() {
        return Err(cannot("ps", out.status.to_string()));
    }
    let me = std::process::id().to_string();
    let listed = String::from_utf8_lossy(&out.stdout).into_owned();
    let mut found: Vec<String> = listed
        .lines()
        .map(str::trim)
        .filter(|line| line.split_whitespace().next() != Some(me.as_str()))
        .filter(|line| {
            PYTHON_PROGRAMS
                .iter()
                .chain(["hellolink"].iter())
                .any(|p| line.contains(&*to.join(p).to_string_lossy()))
        })
        .map(String::from)
        .collect();
    let program = to.join("hellolink");
    if program.exists() {
        let out = Command::new("lsof")
            .arg("-t")
            .arg(&program)
            .output()
            .map_err(|e| cannot("lsof", e.to_string()))?;
        // lsof: 0 with the pids, 1 when no process has the file open
        if !matches!(out.status.code(), Some(0 | 1)) {
            return Err(cannot("lsof", out.status.to_string()));
        }
        for pid in String::from_utf8_lossy(&out.stdout).split_whitespace() {
            if pid != me
                && !found
                    .iter()
                    .any(|l| l.split_whitespace().next() == Some(pid))
            {
                found.push(format!("{pid} {}", program.display()));
            }
        }
    }
    Ok(found)
}

/// Why the install must not go into `to` now, or None.
fn refusal(to: &Path) -> Option<String> {
    if to.exists() && !is_install(to) {
        return Some(format!(
            "{} is not an earlier reader install (it holds other things); give another --to",
            to.display()
        ));
    }
    match running(to) {
        Err(why) => Some(why),
        Ok(found) if found.is_empty() => None,
        Ok(found) => Some(format!(
            "the reader or the assistant program runs from {}; stop it first:\n{}",
            to.display(),
            found.join("\n")
        )),
    }
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

/// The checkout's commit and its capture source, when this program (built from `built`) was
/// built from the commit's files; else Err.
fn commit_and_source(checkout: &Path, built: &str) -> Result<(String, Vec<u8>), String> {
    let commit = String::from_utf8_lossy(&git(checkout, &["rev-parse", "HEAD"])?)
        .trim()
        .to_string();
    let short = &commit[..7.min(commit.len())];
    let listed = git(
        checkout,
        &["ls-tree", "-r", "--name-only", &commit, "--", "reader"],
    )?;
    let listed = String::from_utf8_lossy(&listed).into_owned();
    let inputs: Vec<&str> = listed
        .lines()
        .filter_map(|n| n.strip_prefix("reader/"))
        .filter(|n| built_from::is_input(n))
        .collect();
    let needed = [
        "Cargo.toml",
        "Cargo.lock",
        "hellolink/Cargo.toml",
        "hellolink/src/main.rs",
    ];
    if let Some(missing) = needed.iter().find(|n| !inputs.contains(n)) {
        return Err(format!("{short} lacks reader/{missing}"));
    }
    let mut files = Vec::new();
    for name in inputs {
        let bytes = git(checkout, &["show", &format!("{commit}:reader/{name}")])?;
        files.push((name.to_string(), bytes));
    }
    if built_from::digest(files) != built {
        return Err(format!(
            "this program was not built from {short}'s files; build it from them first \
             (cargo build --release --locked), then install"
        ));
    }
    let source = git(checkout, &["show", &format!("{commit}:{CAPTURE}")])
        .map_err(|_| format!("{short} lacks {CAPTURE}"))?;
    Ok((commit, source))
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

/// `to` made absolute with its links and `..` resolved part by part, as Python's resolve()
/// (os.path.realpath): a part that does not exist is taken as it is, and `..` after it goes
/// back over it.
fn resolved(to: &Path) -> Result<PathBuf, String> {
    let to = std::path::absolute(to).map_err(|e| format!("{}: {e}", to.display()))?;
    let mut at = PathBuf::from("/");
    for part in to.components() {
        match part {
            Component::RootDir | Component::Prefix(_) | Component::CurDir => {}
            Component::ParentDir => {
                at.pop();
            }
            Component::Normal(name) => {
                let next = at.join(name);
                at = match fs::symlink_metadata(&next) {
                    Ok(m) if m.file_type().is_symlink() => fs::canonicalize(&next).unwrap_or(next),
                    _ => next,
                };
            }
        }
    }
    Ok(at)
}

/// Installs this program (`exe`, built from `built`) and the capture source of `checkout`'s
/// commit into `to`. Ok is the line to print.
pub fn install_reader(
    to: &Path,
    checkout: &Path,
    exe: &Path,
    built: &str,
) -> Result<String, String> {
    let to = resolved(to)?;
    if let Some(why) = refusal(&to) {
        return Err(why);
    }
    let (commit, source) = commit_and_source(checkout, built)?;
    let parent = to.parent().ok_or("--to has no parent folder")?;
    fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    let new = new_folder(parent, "new")?;
    let mut left = None;
    let filled = (|| {
        fs::copy(exe, new.join("hellolink")).map_err(|e| format!("{}: {e}", exe.display()))?;
        fs::write(new.join("strip_capture.swift"), &source).map_err(|e| e.to_string())?;
        fs::write(new.join("VERSION"), format!("{commit}\n")).map_err(|e| e.to_string())?;
        // again, now that the new folder is ready: a reader may have started meanwhile
        if let Some(why) = refusal(&to) {
            return Err(why);
        }
        if to.exists() {
            let old = new_folder(parent, "old")?;
            if let Err(e) = fs::rename(&to, old.join("reader")) {
                let _ = fs::remove_dir(&old);
                return Err(format!("{}: {e}", to.display()));
            }
            if let Err(e) = fs::rename(&new, &to) {
                return Err(match fs::rename(old.join("reader"), &to) {
                    Ok(()) => {
                        let _ = fs::remove_dir(&old);
                        format!("{}: {e}; the earlier install is back", to.display())
                    }
                    Err(back) => format!(
                        "{}: {e}; the earlier install is in {} ({back})",
                        to.display(),
                        old.join("reader").display()
                    ),
                });
            }
            if let Err(e) = fs::remove_dir_all(&old) {
                left = Some(format!(
                    "; the earlier install is left in {} ({e})",
                    old.display()
                ));
            }
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
        "{} installed in {}; start the reader from there{}",
        &commit[..7.min(commit.len())],
        to.display(),
        left.unwrap_or_default()
    ))
}
