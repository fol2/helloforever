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
//!   folder is replaced), or another install into it runs: see `lock_file`.
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
    install_names(to).is_some_and(|names| {
        let has = |want: &[&str]| want.iter().all(|w| names.iter().any(|n| n == w));
        let only = |allowed: &[&str]| names.iter().all(|n| allowed.contains(&n.as_str()));
        let mut python_names = PYTHON.to_vec();
        python_names.extend([PYTHON_LATER, "__pycache__"]);
        (has(&RUST) && only(&RUST)) || (has(&PYTHON) && only(&python_names))
    })
}

/// The names in `to`, or None when one is not a plain file (or a __pycache__ folder of plain
/// .pyc files).
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
        if name == "__pycache__" {
            if !fs::symlink_metadata(&path).is_ok_and(|m| m.is_dir()) {
                return None;
            }
            for q in fs::read_dir(&path).ok()? {
                let q = q.ok()?.path();
                if !(plain(&q) && q.extension().is_some_and(|x| x == "pyc")) {
                    return None;
                }
            }
        } else if !plain(&path) {
            return None;
        }
        names.push(name);
    }
    Some(names)
}

/// The processes that run a reader or the assistant from `to`, or Err when they cannot be
/// listed: by their path in `ps`, and with `lsof` every process that works in the folder or
/// has a file of it open. ponytail: lsof sees only this user's processes unless run as root;
/// the folder is in this user's home (Library is 0700), so nobody else runs from it.
fn running(to: &Path) -> Result<Vec<String>, String> {
    let cannot = |what: &str, why: String| {
        format!(
            "cannot list the processes to see if a program runs from {} ({what}: {why})",
            to.display()
        )
    };
    let out = Command::new("ps")
        .args(["-axo", "pid=,ppid=,args="])
        .output()
        .map_err(|e| cannot("ps", e.to_string()))?;
    if !out.status.success() {
        return Err(cannot("ps", out.status.to_string()));
    }
    let listed = String::from_utf8_lossy(&out.stdout).into_owned();
    let rows: Vec<(&str, &str, &str)> = listed
        .lines()
        .filter_map(|line| {
            let line = line.trim_start();
            let (pid, rest) = line.split_once(char::is_whitespace)?;
            let rest = rest.trim_start();
            let (ppid, args) = rest.split_once(char::is_whitespace).unwrap_or((rest, ""));
            Some((pid, ppid, args))
        })
        .collect();
    // this program and the processes that started it (a shell that works in the folder
    // starts an upgrade from there): never a reader
    let mut mine = vec![std::process::id().to_string()];
    while let Some(up) = rows
        .iter()
        .find(|r| r.0 == mine[mine.len() - 1])
        .map(|r| r.1.to_string())
        .filter(|up| up != "0" && !mine.contains(up))
    {
        mine.push(up);
    }
    let mut found: Vec<String> = rows
        .iter()
        .filter(|r| !mine.iter().any(|m| m == r.0))
        .filter(|r| {
            PYTHON_PROGRAMS
                .iter()
                .chain(["hellolink"].iter())
                .any(|p| r.2.contains(&*to.join(p).to_string_lossy()))
        })
        .map(|r| format!("{} {}", r.0, r.2))
        .collect();
    if to.is_dir() {
        // With lsof, a process that has a file of the folder open (this program's own file
        // while it runs: however it was started), or that works in the folder and names a
        // program in its arguments (`python3 hellolink_strip.py` started there). A shell or
        // anything else that only works there is no reader. lsof's exit code is 1 even when
        // it lists some, so 0 and 1 are both a scan; a failure is a line on stderr (-w: no
        // warnings), another code, or a signal.
        let probe = Command::new("lsof")
            .args(["-w", "-F", "pf", "+d"])
            .arg(to)
            // lsof forks a helper; started here it would work in the folder and be listed
            .current_dir("/")
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| cannot("lsof", e.to_string()))?;
        mine.push(probe.id().to_string());
        let out = probe
            .wait_with_output()
            .map_err(|e| cannot("lsof", e.to_string()))?;
        let said = String::from_utf8_lossy(&out.stderr);
        if let Some(line) = said.lines().find(|l| !l.trim().is_empty()) {
            return Err(cannot("lsof", line.to_string()));
        }
        if !matches!(out.status.code(), Some(0 | 1)) {
            return Err(cannot("lsof", out.status.to_string()));
        }
        // p<pid> starts a process; each f<fd> after it is one of its files in the folder
        let mut open: Vec<(String, Vec<String>)> = Vec::new();
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            if let Some(pid) = line.strip_prefix('p') {
                open.push((pid.to_string(), Vec::new()));
            } else if let (Some(fd), Some(last)) = (line.strip_prefix('f'), open.last_mut()) {
                last.1.push(fd.to_string());
            }
        }
        let names_a_program = |pid: &str| {
            rows.iter().any(|r| {
                r.0 == pid
                    && r.2.split_whitespace().any(|w| {
                        let w = w.rsplit('/').next().unwrap_or(w);
                        PYTHON_PROGRAMS.contains(&w) || w == "hellolink"
                    })
            })
        };
        // a process that started after the ps above: its arguments, asked for now
        let new: Vec<&str> = open
            .iter()
            .filter(|(pid, _)| !rows.iter().any(|r| r.0 == pid) && !mine.contains(pid))
            .map(|(pid, _)| pid.as_str())
            .collect();
        let mut late = String::new();
        if !new.is_empty() {
            let out = Command::new("ps")
                .args(["-o", "pid=,args=", "-p", &new.join(",")])
                .output()
                .map_err(|e| cannot("ps", e.to_string()))?;
            // ps exits 1 when none of them is left: they ended, nothing to look at; a line on
            // stderr is a failure (macOS ps can say one and exit 0 with no rows)
            let said = String::from_utf8_lossy(&out.stderr);
            if let Some(line) = said.lines().find(|l| !l.trim().is_empty()) {
                return Err(cannot("ps", line.to_string()));
            }
            if !matches!(out.status.code(), Some(0 | 1)) {
                return Err(cannot("ps", out.status.to_string()));
            }
            late = String::from_utf8_lossy(&out.stdout).into_owned();
        }
        let late_names = |pid: &str| {
            late.lines().any(|l| {
                let mut w = l.split_whitespace();
                w.next() == Some(pid)
                    && w.any(|a| {
                        let a = a.rsplit('/').next().unwrap_or(a);
                        PYTHON_PROGRAMS.contains(&a) || a == "hellolink"
                    })
            })
        };
        for (pid, fds) in open {
            let known = found
                .iter()
                .any(|l| l.split_whitespace().next() == Some(&pid));
            let runs = fds.iter().any(|f| f != "cwd") || names_a_program(&pid) || late_names(&pid);
            if runs && !known && !mine.contains(&pid) {
                found.push(format!(
                    "{pid} (works in {} or runs a file of it)",
                    to.display()
                ));
            }
        }
    }
    Ok(found)
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
    let Some(path) = exe.parent().and_then(lock_file) else {
        return Ok(None);
    };
    let file = match fs::File::open(&path) {
        Ok(f) => f,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("{}: {e}", path.display())),
    };
    match file.try_lock_shared() {
        Ok(()) => Ok(Some(file)),
        Err(fs::TryLockError::WouldBlock) => Err(format!(
            "an install into {} is under way; start this again when it is done",
            exe.parent().unwrap_or(exe).display()
        )),
        Err(fs::TryLockError::Error(e)) => Err(format!("{}: {e}", path.display())),
    }
}

/// A free name beside `to` for the earlier install: `<name>-previous-<n>`.
fn previous_name(to: &Path) -> Option<PathBuf> {
    let name = to.file_name()?.to_string_lossy().into_owned();
    (1..)
        .map(|n| to.with_file_name(format!("{name}-previous-{n}")))
        .find(|p| fs::symlink_metadata(p).is_err())
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
    let parent = to.parent().ok_or("--to has no parent folder")?;
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
    if let Some(why) = refusal(&to) {
        return Err(why);
    }
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
        // again, now that the new folder is ready (a Python reader takes no lock)
        if let Some(why) = refusal(&to) {
            return Err(why);
        }
        if to.exists() {
            // The earlier install is kept, never deleted: nothing of it, or of what came
            // into it meanwhile, is lost. Delete it by hand when the new one runs well.
            let previous = previous_name(&to).ok_or("no free name for the earlier install")?;
            fs::rename(&to, &previous).map_err(|e| format!("{}: {e}", to.display()))?;
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
    if new.exists() {
        let _ = fs::remove_dir_all(&new);
    }
    filled?;
    let kept = kept.map_or(String::new(), |p| {
        format!("; the earlier install is kept in {}", p.display())
    });
    Ok(format!(
        "{} installed in {}; start the reader from there{kept}",
        &commit[..7.min(commit.len())],
        to.display()
    ))
}
