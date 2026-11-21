//! `install-reader`: the reader installed outside any git checkout (#117, docs/STRIP.md
//! section 10). The folder holds this program
//! (`hellolink`), the capture tool's source and a VERSION file that names the commit. A program
//! that serves the game starts the reader from that folder by its full path, so a checkout or a
//! branch switch never changes the reader it runs next.
//!
//! VERSION is true by construction: the program is installed only when the files it was built
//! from (built_from.rs) are those of the commit, and the capture source is taken from the
//! commit, not from the working tree. Nothing changes, and Err says why, when:
//! - the program was not built from the commit, or the commit lacks an input or the source;
//! - the folder holds anything but a whole earlier install;
//! - the reader or the assistant program runs from the folder, or another install into it
//!   runs: each holds the lock beside the folder (`lock_file`);
//! - the folder moved aside at the end is not the one checked (another was put in its place).
//!
//! The earlier install is never deleted: it is kept beside the new one, `<name>-previous-<n>`.

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

/// The build this program is, for the first line of a run: the commit that `VERSION` beside it names
/// (an install: a plain file of at most 64 bytes holding a whole commit, 40 hex digits; its first
/// 12), else what it was built from. So a log kept across restarts says which reader each run was.
/// `exe` None (its path unknown) gives what it was built from. Nothing here waits: a FIFO or a large
/// file is no VERSION.
pub fn build_name(exe: Option<&Path>) -> String {
    let named = exe.and_then(|exe| {
        let path = exe.parent()?.join("VERSION");
        let meta = fs::metadata(&path).ok()?;
        if !meta.is_file() || meta.len() > 64 {
            return None;
        }
        let text = fs::read_to_string(&path).ok()?;
        let commit = text.trim();
        (commit.len() == 40 && commit.chars().all(|c| c.is_ascii_hexdigit()))
            .then(|| commit[..12].to_string())
    });
    named.unwrap_or_else(|| format!("built from {BUILT_FROM}"))
}

/// The first line of a `watch` run: when it started (local time, with its offset) and which build.
pub fn start_line(now: chrono::DateTime<chrono::Local>, exe: Option<&Path>) -> String {
    format!(
        "started {}, hellolink {}",
        now.format("%Y-%m-%dT%H:%M:%S%:z"),
        build_name(exe)
    )
}

/// The default folder: ~/Library/Application Support/HelloLink/reader.
pub fn default_folder() -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME").ok_or("no home folder (HOME is not set)")?;
    Ok(PathBuf::from(home).join("Library/Application Support/HelloLink/reader"))
}

fn plain(p: &Path) -> bool {
    fs::symlink_metadata(p).is_ok_and(|m| m.is_file())
}

/// True when `to` holds a whole earlier install and nothing else, each file plain. (The
/// Python reader's install is gone with it, #195.)
fn is_install(to: &Path) -> bool {
    install_names(to).is_some_and(|names| {
        names.len() == RUST.len() && RUST.iter().all(|w| names.iter().any(|n| n == w))
    })
}

/// The names in `to`, or None when one is not a plain file.
fn install_names(to: &Path) -> Option<Vec<String>> {
    if !fs::symlink_metadata(to).is_ok_and(|m| m.is_dir()) {
        return None;
    }
    let mut names = Vec::new();
    for entry in fs::read_dir(to).ok()? {
        let entry = entry.ok()?;
        let (path, name) = (
            entry.path(),
            entry.file_name().to_string_lossy().into_owned(),
        );
        if !plain(&path) {
            return None;
        }
        names.push(name);
    }
    Some(names)
}

/// The lock file of the install folder `to`: `.<name>.lock` beside it, in its parent, so it
/// stays where it is while the folder is moved. A reader or assistant run from the install
/// holds it shared (`hold_lock`); `install-reader` holds it exclusive from start to end
/// (`take_lock`). So an install refuses while any account's reader runs, seen by `ps` and
/// `lsof` or not; a reader does not start while an install runs; and two installs into one
/// folder do not run at once.
fn lock_file(to: &Path) -> Option<PathBuf> {
    let name = to.file_name()?.to_string_lossy();
    Some(to.parent()?.join(format!(".{name}.lock")))
}

/// The install's side of the lock (the parent folder must exist).
fn take_lock(to: &Path) -> Result<fs::File, String> {
    let path = lock_file(to).ok_or("--to has no name or no parent folder")?;
    let file = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    match file.try_lock() {
        Ok(()) => Ok(file),
        Err(fs::TryLockError::WouldBlock) => Err(format!(
            "the reader, the assistant program or another install runs from {} (it holds {}); \
             stop it first",
            to.display(),
            path.display()
        )),
        Err(fs::TryLockError::Error(e)) => Err(format!("{}: {e}", path.display())),
    }
}

/// For `watch` and `assist`: when the program's folder has the lock file of an install beside
/// it (`install-reader` made it), the shared lock for as long as the program runs. Ok(None)
/// when there is none (a checkout's build); Err when it cannot be had (an install is under
/// way): the program then does not start. The lock file is beside the folder, so this holds
/// while an install has moved the folder aside, too.
pub fn hold_lock(exe: &Path) -> Result<Option<fs::File>, String> {
    // the program's real path, not a link to it; and from a kept earlier install, the lock of
    // the folder it was moved from (on Linux an install can move the program before it gets
    // here)
    let exe = fs::canonicalize(exe).map_err(|e| format!("{}: {e}", exe.display()))?;
    let Some(path) = exe.parent().map(moved_from).as_deref().and_then(lock_file) else {
        return Ok(None);
    };
    let file = match fs::File::open(&path) {
        Ok(f) => f,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            // said, not silent: an install will not see this program (accepted in #206)
            if exe.parent().is_some_and(is_install) {
                eprintln!(
                    "hellolink: warning: no install lock {}; an install will not wait for this program",
                    path.display()
                );
            }
            return Ok(None);
        }
        Err(e) => return Err(format!("{}: {e}", path.display())),
    };
    match file.try_lock_shared() {
        Ok(()) => Ok(Some(file)),
        Err(fs::TryLockError::WouldBlock) => Err(format!(
            "an install into {} is under way; start this again when it is done",
            exe.parent().unwrap_or(&exe).display()
        )),
        Err(fs::TryLockError::Error(e)) => Err(format!("{}: {e}", path.display())),
    }
}

/// The folder `folder` was moved from when it is a kept earlier install
/// (`<name>-previous-<n>`), or `folder` itself.
fn moved_from(folder: &Path) -> PathBuf {
    let name = folder.file_name().map(|n| n.to_string_lossy().into_owned());
    match name.as_deref().and_then(|n| n.rsplit_once("-previous-")) {
        Some((base, n)) if !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()) => {
            folder.with_file_name(base)
        }
        _ => folder.to_path_buf(),
    }
}

/// A folder's identity: its device and inode.
fn identity(path: &Path) -> Option<(u64, u64)> {
    use std::os::unix::fs::MetadataExt;
    fs::symlink_metadata(path).ok().map(|m| (m.dev(), m.ino()))
}

/// A free name beside `to` for the earlier install: `<name>-previous-<n>`.
fn previous_name(to: &Path) -> Option<PathBuf> {
    let name = to.file_name()?.to_string_lossy().into_owned();
    (1..)
        .map(|n| to.with_file_name(format!("{name}-previous-{n}")))
        .find(|p| fs::symlink_metadata(p).is_err())
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
        "hellolink/build.rs",
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
        return Err(not_built_from(short));
    }
    let source = git(checkout, &["show", &format!("{commit}:{CAPTURE}")])
        .map_err(|_| format!("{short} lacks {CAPTURE}"))?;
    Ok((commit, source))
}

fn not_built_from(short: &str) -> String {
    format!(
        "this program was not built from {short}'s files; build it from them first \
         (cargo build --release --locked), then install"
    )
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
                    // a link that leads nowhere: where a `..` after it goes is not known
                    Ok(m) if m.file_type().is_symlink() => {
                        fs::canonicalize(&next).map_err(|e| {
                            format!(
                                "{}: a link that cannot be followed ({e}); give another --to",
                                next.display()
                            )
                        })?
                    }
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
    // an existing folder by the name the disk stores it under, as its reader finds it
    // (`hold_lock`): on macOS another case or form of the name opens the same folder
    let to = match to.exists() {
        true => fs::canonicalize(&to).map_err(|e| format!("{}: {e}", to.display()))?,
        false => to,
    };
    let parent = to.parent().ok_or("--to has no parent folder")?;
    // that name is a kept install's, whose reader takes the lock of the folder it came from
    if moved_from(&to) != to {
        return Err(format!(
            "{} has the name of a kept earlier install (<name>-previous-<n>); give another --to",
            to.display()
        ));
    }
    if to.exists() && !is_install(&to) {
        return Err(format!(
            "{} is not an earlier reader install (it holds other things); give another --to",
            to.display()
        ));
    }
    let (commit, source) = commit_and_source(checkout, built)?;
    fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    // held to the end: no reader runs from the folder and no other install runs meanwhile
    let _lock = take_lock(&to)?;
    // the folder the checks are of: the one moved aside at the end must be the same
    let checked = identity(&to);
    let new = new_folder(parent, "new")?;
    let mut kept = None;
    let filled = (|| {
        fs::copy(exe, new.join("hellolink")).map_err(|e| format!("{}: {e}", exe.display()))?;
        // the copy, not the path it came from, must be built from the commit: a build can
        // replace the file at that path while this runs
        let says = Command::new(new.join("hellolink"))
            .arg("built-from")
            .output()
            .map_err(|e| format!("the copied program: {e}"))?;
        if String::from_utf8_lossy(&says.stdout).trim() != built {
            return Err(not_built_from(&commit[..7.min(commit.len())]));
        }
        fs::write(new.join("strip_capture.swift"), &source).map_err(|e| e.to_string())?;
        fs::write(new.join("VERSION"), format!("{commit}\n")).map_err(|e| e.to_string())?;
        if to.exists() {
            // The earlier install is kept, never deleted: nothing of it, or of what came
            // into it meanwhile, is lost. Delete it by hand when the new one runs well.
            let previous = previous_name(&to).ok_or("no free name for the earlier install")?;
            fs::rename(&to, &previous).map_err(|e| format!("{}: {e}", to.display()))?;
            if identity(&previous) != checked {
                return Err(match fs::rename(&previous, &to) {
                    Ok(()) => format!(
                        "{} was replaced by another folder while the install ran; it is left as it is",
                        to.display()
                    ),
                    Err(back) => format!(
                        "{} was replaced by another folder while the install ran; that folder is now {} ({back})",
                        to.display(),
                        previous.display()
                    ),
                });
            }
            if let Err(e) = fs::rename(&new, &to) {
                return Err(match fs::rename(&previous, &to) {
                    Ok(()) => format!("{}: {e}; the earlier install is back", to.display()),
                    Err(back) => format!(
                        "{}: {e}; the earlier install is in {} ({back})",
                        to.display(),
                        previous.display()
                    ),
                });
            }
            kept = Some(previous);
        } else {
            fs::rename(&new, &to).map_err(|e| format!("{}: {e}", to.display()))?;
        }
        Ok(())
    })();
    let left = match new.exists() {
        true => fs::remove_dir_all(&new).err().map(|e| {
            format!(
                "; the temporary folder {} is left ({e}); delete it by hand",
                new.display()
            )
        }),
        false => None,
    }
    .unwrap_or_default();
    filled.map_err(|why| format!("{why}{left}"))?;
    let kept = kept.map_or(String::new(), |p| {
        format!("; the earlier install is kept in {}", p.display())
    });
    Ok(format!(
        "{} installed in {}; start the reader from there{kept}{left}",
        &commit[..7.min(commit.len())],
        to.display()
    ))
}
