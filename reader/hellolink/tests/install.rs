//! The installers and the release packer of step 3b against the Python tools: `install` (the
//! slots) against tools/hellolink.py install, `install-reader` against the checks of
//! tests/install_reader_test.py, `package` against tools/package.py.
//! A test program of its own: these scan every process (`ps`, `lsof`) and start many, so they
//! run after `processes`, not beside its clock-bound tests.
#[path = "common/mod.rs"]
mod common;

use hellolink::capture::{CAPTURE_SOURCE, build_capture, capture_source};
use hellolink::package::sha256;
use hellolink::slots::install_from;
use std::collections::BTreeMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::{Duration, UNIX_EPOCH};

const READER: &str = env!("CARGO_BIN_EXE_hellolink");
/// Every file under a folder: its bytes and mode.
type Tree = BTreeMap<String, (Vec<u8>, u32)>;
/// A labelled change to a folder.
type Change<'a> = (&'a str, Box<dyn Fn(&Path) + 'a>);
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn folder(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("install-{name}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir.canonicalize().unwrap()
}

/// A command's output, with a limit: a test never waits without one (a hang would cost CI's
/// whole job). The command runs as a process group of its own, killed whole at the limit, and
/// the test fails with its name.
trait Limited {
    fn limited(&mut self) -> Output;
}

impl Limited for Command {
    fn limited(&mut self) -> Output {
        let shown = format!("{self:?}");
        let child = self
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .process_group(0)
            .spawn()
            .unwrap();
        let group = format!("-{}", child.id());
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(child.wait_with_output());
        });
        match rx.recv_timeout(Duration::from_secs(60)) {
            Ok(out) => out.unwrap(),
            Err(_) => {
                // the whole group: a child of the command (an installer under a shell) goes too
                let _ = Command::new("kill").args(["-9", "--", &group]).status();
                panic!("no end in 60 s: {shown}");
            }
        }
    }
}

fn run(program: &str, args: &[&str], env: &[(&str, &str)]) -> Output {
    Command::new(program)
        .args(args)
        .envs(env.iter().copied())
        .limited()
}

fn text(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// Every file under `dir`: its bytes and mode.
fn tree(dir: &Path) -> Tree {
    let mut out = BTreeMap::new();
    let mut todo = vec![dir.to_path_buf()];
    while let Some(d) = todo.pop() {
        for e in fs::read_dir(&d).unwrap() {
            let p = e.unwrap().path();
            if p.is_dir() {
                todo.push(p);
            } else {
                let mode = fs::metadata(&p).unwrap().permissions().mode() & 0o777;
                let name = p.strip_prefix(dir).unwrap().to_string_lossy().into_owned();
                // a file that cannot be read stands for itself by the error
                out.insert(
                    name,
                    (
                        fs::read(&p).unwrap_or_else(|e| e.to_string().into_bytes()),
                        mode,
                    ),
                );
            }
        }
    }
    out
}

// ---- install: the slots ----

#[test]
fn the_slot_install_is_the_python_install() {
    let rs = folder("slots-rs");
    // an earlier install with a text, then a new one over it, as a player's folder has
    fs::create_dir_all(rs.join("addons/HelloLink_S002")).unwrap();
    fs::write(
        rs.join("addons/HelloLink_S002/Inbox.lua"),
        "HelloLink_Inbox = { seq = 5, text = \"old\", slots = 2 }\n",
    )
    .unwrap();
    fs::write(rs.join("addons/HelloLink_S002/.parts.json"), "{\"seq\": 5}").unwrap();
    // `./addons/` is written back as Python writes a path
    let done = Command::new(READER)
        .args(["install", "./addons/", "--slots", "3"])
        .current_dir(&rs)
        .limited();
    assert!(done.status.success(), "{}", text(&done.stderr));
    assert_eq!(
        text(&done.stdout),
        "installed HelloLink and 3 slots in addons\n"
    );
    // What tools/hellolink.py install made (seen 20 Nov 2026, umask 022, before #195 step 3c
    // deleted it): the addon as its source, each slot's TOC and Inbox.lua, the kept
    // .parts.json; Inbox.lua 0600, the TOCs and .parts.json as the umask gives (0644 under 022).
    let a = tree(&rs.join("addons"));
    let source = tree(&Path::new(REPO).join("HelloLink"));
    // 0644 under umask 022: a file made here says what the umask gives
    fs::write(rs.join("control"), "").unwrap();
    let made = fs::metadata(rs.join("control"))
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    let mut want: Vec<(String, u32)> = source
        .iter()
        .map(|(n, (_, m))| (format!("HelloLink/{n}"), *m))
        .collect();
    for i in 1..=3 {
        let s = format!("HelloLink_S{i:03}");
        want.push((format!("{s}/{s}.toc"), made));
        want.push((format!("{s}/Inbox.lua"), 0o600));
    }
    want.push(("HelloLink_S002/.parts.json".into(), made));
    want.sort();
    let got: Vec<(String, u32)> = a.iter().map(|(n, (_, m))| (n.clone(), *m)).collect();
    assert_eq!(got, want, "the files and modes of the Python install");
    for (n, (bytes, _)) in &source {
        assert_eq!(
            &a[&format!("HelloLink/{n}")].0,
            bytes,
            "HelloLink/{n}: as its source"
        );
    }
    // written out by hand from tools/hellolink.py
    for i in 1..=3 {
        let s = format!("HelloLink_S{i:03}");
        assert_eq!(
            a[&format!("{s}/{s}.toc")].0,
            format!("## Interface: 16001\n## Title: HelloLink slot {i:03}\n## LoadOnDemand: 1\n## Group: HelloLink\n\nInbox.lua\n").into_bytes(),
            "{s}'s TOC"
        );
        assert_eq!(
            a[&format!("{s}/Inbox.lua")].0,
            b"HelloLink_Inbox = { seq = 0, text = \"\", slots = 3 }\n",
            "{s}'s Inbox.lua"
        );
    }
    assert_eq!(a["HelloLink_S002/.parts.json"].0, b"{\"seq\": 5}");
}

#[test]
fn the_slot_counts_the_install_refuses() {
    let dir = folder("slots-refused");
    let at =
        |program: &str, args: &[&str]| Command::new(program).args(args).current_dir(&dir).limited();
    for n in ["0", "1000", "-7", "18446744073709551616"] {
        let rs = at(READER, &["install", "addons", "--slots", n]);
        assert_eq!(rs.status.code(), Some(1), "{n}");
        assert_eq!(
            text(&rs.stderr),
            "hellolink: --slots must be 1 to 999\n",
            "{n}"
        );
    }
    assert!(!dir.join("addons").exists());
    let bad = at(READER, &["install", "addons", "--slots", "x"]);
    assert_eq!(
        text(&bad.stderr),
        "hellolink: install: argument --slots: invalid int value: \"x\"\n"
    );
}

#[test]
fn a_slot_install_onto_its_own_source_changes_nothing() {
    // AddOns/HelloLink a link to the source (as a checkout linked into the game): every file
    // would be copied onto itself, and emptied
    let base = folder("slots-same");
    let source = base.join("HelloLink");
    fs::create_dir(&source).unwrap();
    fs::write(source.join("HelloLink.toc"), "## Title: HelloLink\n").unwrap();
    fs::write(source.join("HelloLink.lua"), "-- the code\n").unwrap();
    let addons = base.join("AddOns");
    fs::create_dir(&addons).unwrap();
    std::os::unix::fs::symlink(&source, addons.join("HelloLink")).unwrap();
    let before = tree(&source);
    let done = install_from(&source, &addons, 2);
    assert!(
        done.as_ref()
            .is_err_and(|e| e.contains("are the same file")),
        "{done:?}"
    );
    assert!(tree(&source) == before, "the source is untouched");
    assert_eq!(names(&addons), ["HelloLink"], "no slot is made");
}

// ---- install-reader ----

fn git(repo: &Path, args: &[&str]) -> String {
    let out = Command::new("git").arg("-C").arg(repo).args(args).limited();
    assert!(out.status.success(), "git {args:?}: {}", text(&out.stderr));
    text(&out.stdout).trim().to_string()
}

fn commit(repo: &Path, message: &str) {
    git(
        repo,
        &[
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.invalid",
            "commit",
            "-qam",
            message,
        ],
    );
}

fn install_reader(to: &Path, checkout: Option<&Path>, env: &[(&str, &str)]) -> Output {
    let mut args = vec!["install-reader", "--to", to.to_str().unwrap()];
    if let Some(c) = checkout {
        args.extend(["--checkout", c.to_str().unwrap()]);
    }
    run(READER, &args, env)
}

fn names(dir: &Path) -> Vec<String> {
    let mut n: Vec<String> = fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    n.sort();
    n
}

fn copy_tree(from: &Path, to: &Path) {
    fs::create_dir_all(to).unwrap();
    for e in fs::read_dir(from).unwrap() {
        let p = e.unwrap().path();
        let dst = to.join(p.file_name().unwrap());
        if p.is_dir() {
            copy_tree(&p, &dst);
        } else {
            fs::copy(&p, &dst).unwrap();
        }
    }
}

/// A git checkout of its own with the files this program is built from (as they are here) and
/// the capture source, its old copy dated 1 Jan 2000.
fn other_checkout(base: &Path) -> PathBuf {
    let repo = base.join("repo");
    for f in [
        "reader/Cargo.toml",
        "reader/Cargo.lock",
        "reader/hellolink/Cargo.toml",
        "reader/hellolink/build.rs",
        "tools/strip_capture.swift",
    ] {
        fs::create_dir_all(repo.join(f).parent().unwrap()).unwrap();
        fs::copy(Path::new(REPO).join(f), repo.join(f)).unwrap();
    }
    copy_tree(
        &Path::new(REPO).join("reader/hellolink/src"),
        &repo.join("reader/hellolink/src"),
    );
    git(&repo, &["init", "-q"]);
    git(&repo, &["add", "."]);
    commit(&repo, "reader");
    fs::File::options()
        .write(true)
        .open(repo.join("tools/strip_capture.swift"))
        .unwrap()
        .set_modified(UNIX_EPOCH + Duration::from_secs(946_684_800))
        .unwrap();
    repo
}

/// Every file under `dir` with its bytes, and the names beside `dir`.
fn state(dir: &Path) -> (Tree, Vec<String>) {
    (tree(dir), names(dir.parent().unwrap()))
}

#[test]
fn the_reader_installs_outside_any_checkout() {
    // from a checkout of the files as they are (not this repository's commit, so that a
    // change to them, as a mutation run makes, is still the program's own)
    let base = folder("reader");
    let repo = other_checkout(&base);
    let to = base.join("Support/reader");
    let done = install_reader(&to, Some(&repo), &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    let head = git(&repo, &["rev-parse", "HEAD"]);
    assert_eq!(
        text(&done.stdout),
        format!(
            "install-reader: {} installed in {}; start the reader from there\n",
            &head[..7],
            to.display()
        )
    );
    assert_eq!(names(&to), ["VERSION", "hellolink", "strip_capture.swift"]);
    assert_eq!(
        fs::read(to.join("hellolink")).unwrap(),
        fs::read(READER).unwrap()
    );
    let committed = git(&repo, &["show", "HEAD:tools/strip_capture.swift"]);
    assert_eq!(
        fs::read_to_string(to.join("strip_capture.swift"))
            .unwrap()
            .trim(),
        committed
    );
    assert_eq!(
        fs::read_to_string(to.join("VERSION")).unwrap(),
        format!("{head}\n")
    );
    // the installed program runs, and builds the capture tool from the source beside it
    let helped = run(to.join("hellolink").to_str().unwrap(), &["--help"], &[]);
    assert!(helped.status.success() && text(&helped.stdout).contains("install-reader"));
    assert_eq!(
        capture_source(Some(&to.join("hellolink"))),
        to.join("strip_capture.swift")
    );
    assert_eq!(
        capture_source(Some(Path::new(READER))),
        PathBuf::from(CAPTURE_SOURCE)
    );

    // a second install: the first is kept beside it, whole, never deleted; no temporary
    // folder is left; the lock file stays
    let again = install_reader(&to, Some(&repo), &[]);
    assert!(again.status.success(), "{}", text(&again.stderr));
    let previous = base.join("Support/reader-previous-1");
    assert!(text(&again.stdout).contains(&format!(
        "the earlier install is kept in {}",
        previous.display()
    )));
    assert_eq!(names(&to), ["VERSION", "hellolink", "strip_capture.swift"]);
    assert_eq!(
        names(&previous),
        ["VERSION", "hellolink", "strip_capture.swift"]
    );
    assert_eq!(
        names(&base.join("Support")),
        [".reader.lock", "reader", "reader-previous-1"]
    );
}

#[test]
fn the_default_checkout_is_the_one_built_from() {
    // no --checkout: this repository, whose HEAD this program is built from
    let base = folder("reader-default");
    let to = base.join("reader");
    let done = install_reader(&to, None, &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    let head = git(Path::new(REPO), &["rev-parse", "HEAD"]);
    assert_eq!(
        fs::read_to_string(to.join("VERSION")).unwrap(),
        format!("{head}\n")
    );
}

#[test]
fn an_install_from_another_checkout_takes_the_commits_files() {
    let base = folder("reader-other");
    let repo = other_checkout(&base);
    // a commit that changes only the tests' own programs (src/bin) is still this program's
    let helper = repo.join("reader/hellolink/src/bin/fake_capture.rs");
    let was = fs::read(&helper).unwrap();
    fs::write(&helper, [&was[..], b"// a test helper changed\n"].concat()).unwrap();
    commit(&repo, "helper");
    // a change not committed: the program is still built from the commit, and the install
    // takes the commit's capture source, not the working tree's
    let swift = repo.join("tools/strip_capture.swift");
    let committed = fs::read(&swift).unwrap();
    fs::write(&swift, b"// not committed\n").unwrap();
    let to = base.join("other/reader");
    let done = install_reader(&to, Some(&repo), &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    assert_eq!(
        fs::read_to_string(to.join("VERSION")).unwrap().trim(),
        git(&repo, &["rev-parse", "HEAD"])
    );
    assert_eq!(fs::read(to.join("strip_capture.swift")).unwrap(), committed);
    // a new file, so a new time
    let copied = fs::metadata(to.join("strip_capture.swift"))
        .unwrap()
        .modified()
        .unwrap();
    assert!(copied > UNIX_EPOCH + Duration::from_secs(946_684_800 + 86_400));
}

#[test]
fn the_capture_tool_is_built_once_for_each_source() {
    let base = folder("capture-cache");
    // a stand-in for swiftc: counts its runs; the tool it makes holds the source it was given
    let log = base.join("runs");
    let fake = base.join("swiftc");
    let script = format!(
        "#!/bin/sh\necho \"$4\" >> '{}'\ngrep -q fail \"$4\" && exit 1\ncat \"$4\" > \"$6\"\n",
        log.display()
    );
    common::executable(&fake, &script);
    let fake = fake.to_str().unwrap();
    let source = base.join("strip_capture.swift");
    let cache = base.join("cache");
    let runs = || fs::read_to_string(&log).map_or(0, |s| s.lines().count());
    let build = |text: &str| {
        fs::write(&source, text).unwrap();
        build_capture(&cache, &source, fake)
    };
    let tool_a = build("source A").unwrap();
    assert_eq!(fs::read_to_string(&tool_a).unwrap(), "source A");
    // the same path with other bytes (a branch switch): another tool
    let tool_b = build("source B").unwrap();
    assert_ne!(tool_a, tool_b);
    assert_eq!(fs::read_to_string(&tool_b).unwrap(), "source B");
    // A again, though B's tool is newer: A's own tool, not built again
    assert_eq!(build("source A").unwrap(), tool_a);
    assert_eq!(fs::read_to_string(&tool_a).unwrap(), "source A");
    assert_eq!(runs(), 2);
    // the compiler reads a copy of the bytes the name is made from, never the source itself
    let given = fs::read_to_string(&log).unwrap();
    assert!(!given.lines().any(|l| Path::new(l) == source), "{given}");
    // a build that fails leaves nothing: no tool under the name, no copy of the source
    assert!(build("source fail").is_err());
    assert_eq!(names(&cache).len(), 2, "{:?}", names(&cache));
}

#[test]
fn the_reader_install_refuses_and_changes_nothing() {
    let base = folder("reader-refused");
    let repo = other_checkout(&base);
    let to = base.join("Support/reader");
    let first = install_reader(&to, Some(&repo), &[]);
    assert!(first.status.success(), "{}", text(&first.stderr));
    let refused =
        |why: &str, to: &Path, checkout: Option<&Path>, env: &[(&str, &str)], needle: &str| {
            let before = state(to);
            let done = install_reader(to, checkout, env);
            assert_eq!(done.status.code(), Some(1), "{why}: {}", text(&done.stderr));
            assert!(
                text(&done.stderr).contains(needle),
                "{why}: {}",
                text(&done.stderr)
            );
            assert!(state(to) == before, "{why}: something changed");
        };
    // the program was not built from the commit
    let source = repo.join("reader/hellolink/src/strip1.rs");
    let was = fs::read(&source).unwrap();
    fs::write(&source, [&was[..], b"// committed later\n"].concat()).unwrap();
    commit(&repo, "a change");
    refused(
        "another commit",
        &to,
        Some(&repo),
        &[],
        "was not built from",
    );
    fs::write(&source, &was).unwrap();
    commit(&repo, "back");
    // the commit lacks an input: the lock file left in the working tree
    git(&repo, &["rm", "-q", "--cached", "reader/Cargo.lock"]);
    commit(&repo, "no lock");
    refused(
        "no lock file",
        &to,
        Some(&repo),
        &[],
        "lacks reader/Cargo.lock",
    );
    git(&repo, &["add", "reader/Cargo.lock"]);
    commit(&repo, "lock");
    // the commit lacks the build script
    git(
        &repo,
        &["rm", "-q", "--cached", "reader/hellolink/build.rs"],
    );
    commit(&repo, "no build script");
    refused(
        "no build script",
        &to,
        Some(&repo),
        &[],
        "lacks reader/hellolink/build.rs",
    );
    git(&repo, &["add", "reader/hellolink/build.rs"]);
    commit(&repo, "build script");
    // a copied program not built from the commit (a build replaced the file meanwhile)
    let stand_in = base.join("stand-in");
    common::executable(&stand_in, "#!/bin/sh\necho 0000000000000000\n");
    let before = state(&to);
    let done =
        hellolink::install::install_reader(&to, &repo, &stand_in, hellolink::install::BUILT_FROM);
    assert!(
        done.as_ref()
            .is_err_and(|e| e.contains("was not built from")),
        "{done:?}"
    );
    assert!(state(&to) == before);
    // A stand-in for the copied program: when the install asks it what it was built from, it
    // runs `act` on the folder first (something that happens while the install runs), then
    // gives the right answer.
    let acting = |act: &str| {
        let program = base.join("acting");
        common::executable(
            &program,
            &format!(
                "#!/bin/sh\nto='{}'\n{act}\necho {}\n",
                to.display(),
                hellolink::install::BUILT_FROM
            ),
        );
        hellolink::install::install_reader(&to, &repo, &program, hellolink::install::BUILT_FROM)
    };
    // a file that comes into the folder while the install runs is never deleted: it is in the
    // earlier install, which is kept
    let done = acting("echo mine > \"$to/notes.txt\"");
    assert!(done.is_ok(), "{done:?}");
    let kept = base.join("Support/reader-previous-1");
    assert_eq!(
        fs::read_to_string(kept.join("notes.txt")).unwrap(),
        "mine\n"
    );
    assert_eq!(names(&to), ["VERSION", "hellolink", "strip_capture.swift"]);
    let installed = to.join("hellolink");
    fs::copy(READER, &installed).unwrap(); // the stand-in was installed; put the program back
    // a folder put in place of the install while it runs is not moved aside: the install
    // puts it back and refuses
    let done =
        acting("mv \"$to\" \"$to.away\" && mkdir \"$to\" && echo theirs > \"$to/notes.txt\"");
    assert!(
        done.as_ref()
            .is_err_and(|e| e.contains("was replaced by another folder")),
        "{done:?}"
    );
    assert_eq!(names(&to), ["notes.txt"]);
    assert_eq!(
        names(&base.join("Support/reader.away")),
        ["VERSION", "hellolink", "strip_capture.swift"]
    );
    assert!(!base.join("Support/reader-previous-2").exists());
    fs::remove_dir_all(&to).unwrap();
    fs::rename(base.join("Support/reader.away"), &to).unwrap();
    // the commit lacks the capture source
    git(
        &repo,
        &["rm", "-q", "--cached", "tools/strip_capture.swift"],
    );
    commit(&repo, "no swift");
    refused(
        "no capture source",
        &to,
        Some(&repo),
        &[],
        "lacks tools/strip_capture.swift",
    );
    git(&repo, &["add", "tools/strip_capture.swift"]);
    commit(&repo, "swift");
    // a lock file that cannot be opened is no free lock
    let lock = base.join("Support/.reader.lock");
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&lock)
        .unwrap();
    fs::set_permissions(&lock, fs::Permissions::from_mode(0o000)).unwrap();
    refused(
        "an unreadable lock file",
        &to,
        Some(&repo),
        &[],
        ".reader.lock: Permission denied",
    );
    fs::set_permissions(&lock, fs::Permissions::from_mode(0o644)).unwrap();
    // a kept install's name is no --to: its reader would take the lock of `reader`
    let support = names(&base.join("Support"));
    let done = install_reader(&base.join("Support/reader-previous-9"), Some(&repo), &[]);
    assert_eq!(done.status.code(), Some(1), "{}", text(&done.stdout));
    assert!(
        text(&done.stderr).contains("the name of a kept earlier install"),
        "{}",
        text(&done.stderr)
    );
    assert_eq!(names(&base.join("Support")), support);
    // ... nor another case of a kept install's name, where the disk takes it for the same
    // folder (macOS; on a disk that tells cases apart it is another folder)
    if base.join("Support/reader-PREVIOUS-1").exists() {
        let done = install_reader(&base.join("Support/reader-PREVIOUS-1"), Some(&repo), &[]);
        assert_eq!(done.status.code(), Some(1), "{}", text(&done.stdout));
        assert!(
            text(&done.stderr).contains("the name of a kept earlier install"),
            "{}",
            text(&done.stderr)
        );
        assert_eq!(names(&base.join("Support")), support);
    }
    // a reader runs from the folder: `watch` and `assist` hold the lock while they run (of any
    // account; here the test holds it), and the install refuses
    let holder = fs::File::open(&lock).unwrap();
    holder.lock_shared().unwrap();
    refused("a lock holder", &to, Some(&repo), &[], "it holds");
    drop(holder);
    // an upgrade by the installed program itself, and one from a shell that works in the
    // folder. Each shell runs a second command after the install, so it stays (one command
    // alone, sh would become it).
    let by_itself = format!(
        "'{}' install-reader --to '{}' --checkout '{}'; echo shell",
        installed.display(),
        to.display(),
        repo.display()
    );
    let in_folder = format!(
        "'{READER}' install-reader --to . --checkout '{}'; echo shell",
        repo.display()
    );
    for (label, script, dir) in [
        ("by itself", by_itself, base.clone()),
        ("in the folder", in_folder, to.clone()),
    ] {
        let done = Command::new("sh")
            .args(["-c", &script])
            .current_dir(&dir)
            .limited();
        let said = text(&done.stdout);
        assert!(
            said.contains("installed in") && said.ends_with("shell\n"),
            "{label}: {said} {}",
            text(&done.stderr)
        );
    }
    // an option where a value goes is no destination, run where it would have made it
    let here = base.join("here");
    fs::create_dir(&here).unwrap();
    for option in ["--checkout", "-h", "--7"] {
        let done = Command::new(READER)
            .args(["install-reader", "--to", option])
            .current_dir(&here)
            .limited();
        assert_eq!(done.status.code(), Some(1), "{option}");
        assert!(
            text(&done.stderr).contains("--to needs a value"),
            "{option}: {}",
            text(&done.stderr)
        );
        assert!(names(&here).is_empty(), "{option}: {:?}", names(&here));
    }
    // a link that leads nowhere, then `..`: Python would go on from the link's target; the
    // install refuses rather than guess
    fs::create_dir(base.join("A")).unwrap();
    std::os::unix::fs::symlink(base.join("B/missing"), base.join("A/link")).unwrap();
    let done = install_reader(&base.join("A/link/../reader"), None, &[]);
    assert_eq!(done.status.code(), Some(1));
    assert!(
        text(&done.stderr).contains("a link that cannot be followed"),
        "{}",
        text(&done.stderr)
    );
    assert_eq!(names(&base.join("A")), ["link"]);
    // `..` after a folder that does not exist goes back over it, as Python's resolve()
    let notes = base.join("notes");
    fs::create_dir(&notes).unwrap();
    fs::write(notes.join("mine.txt"), "keep me\n").unwrap();
    let dotted = base.join("missing/../notes");
    let done = install_reader(&dotted, None, &[]);
    assert_eq!(done.status.code(), Some(1));
    assert!(
        text(&done.stderr).contains("not an earlier reader install"),
        "{}",
        text(&done.stderr)
    );
    assert_eq!(names(&notes), ["mine.txt"]);
    assert!(!base.join("missing").exists());
    // folders that are not a whole install are never replaced
    let others: Vec<Change> = vec![
        (
            "other things",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
                fs::write(d.join("precious.txt"), "keep me\n").unwrap();
            }),
        ),
        (
            "a whole install and one more file",
            Box::new(|d: &Path| {
                for f in [
                    "hellolink",
                    "strip_capture.swift",
                    "VERSION",
                    "precious.txt",
                ] {
                    fs::write(d.join(f), "x\n").unwrap();
                }
            }),
        ),
        (
            "only VERSION",
            Box::new(|d: &Path| fs::write(d.join("VERSION"), "x\n").unwrap()),
        ),
        (
            "no program",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
                fs::write(d.join("strip_capture.swift"), "x\n").unwrap();
            }),
        ),
        (
            "a whole Python install (the Python reader is gone, #195)",
            Box::new(|d: &Path| {
                for f in [
                    "hellolink_strip.py",
                    "strip1.py",
                    "strip_api.py",
                    "hellolink.py",
                    "assistant.py",
                    "strip_capture.swift",
                    "VERSION",
                ] {
                    fs::write(d.join(f), "x\n").unwrap();
                }
            }),
        ),
        (
            "a folder where a file goes",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
                fs::write(d.join("hellolink"), "x\n").unwrap();
                fs::create_dir(d.join("strip_capture.swift")).unwrap();
                fs::write(d.join("strip_capture.swift/precious.txt"), "keep\n").unwrap();
            }),
        ),
        (
            "a link where a file goes",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
                fs::write(d.join("hellolink"), "x\n").unwrap();
                std::os::unix::fs::symlink(
                    format!("{REPO}/tools/strip_capture.swift"),
                    d.join("strip_capture.swift"),
                )
                .unwrap();
            }),
        ),
    ];
    for (label, make) in others {
        let part = base.join(format!("part-{}", label.replace(' ', "-")));
        fs::create_dir(&part).unwrap();
        make(&part);
        refused(label, &part, None, &[], "not an earlier reader install");
    }
}

#[test]
fn an_installed_reader_does_not_start_while_an_install_holds_the_lock() {
    let base = folder("lock-held");
    let repo = other_checkout(&base);
    let to = base.join("reader");
    let done = install_reader(&to, Some(&repo), &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    // the install's side of the lock, held here by a stand-in
    let holder = fs::File::open(base.join(".reader.lock")).unwrap();
    holder.lock().unwrap();
    let ran = run(
        to.join("hellolink").to_str().unwrap(),
        &["assist", "--addons", base.to_str().unwrap()],
        &[],
    );
    // the same through a link to the program, and from a kept earlier install of the folder
    // (on Linux an install can move the program before it reaches the lock)
    let bin = base.join("bin");
    fs::create_dir(&bin).unwrap();
    std::os::unix::fs::symlink(to.join("hellolink"), bin.join("hellolink")).unwrap();
    let kept = base.join("reader-previous-1");
    copy_tree(&to, &kept);
    for program in [bin.join("hellolink"), kept.join("hellolink")] {
        let other = run(
            program.to_str().unwrap(),
            &["assist", "--addons", base.to_str().unwrap()],
            &[],
        );
        assert_eq!(other.status.code(), Some(1), "{}", program.display());
        assert!(
            text(&other.stderr).contains("is under way"),
            "{}: {}",
            program.display(),
            text(&other.stderr)
        );
    }
    drop(holder);
    assert_eq!(ran.status.code(), Some(1));
    assert!(
        text(&ran.stderr).contains("is under way"),
        "{}",
        text(&ran.stderr)
    );
}

// ---- package ----

#[test]
fn sha256_against_fips_180_vectors() {
    assert_eq!(
        sha256(b""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    assert_eq!(
        sha256(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    assert_eq!(
        sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    );
    assert_eq!(
        sha256(&vec![b'a'; 1_000_000]),
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
    );
}

/// A root with the addon and the changelog of this checkout; `change` breaks it.
fn root(name: &str, change: &dyn Fn(&Path)) -> PathBuf {
    let root = folder(name);
    let copied = Command::new("cp")
        .args([
            "-R",
            &format!("{REPO}/HelloForever"),
            &format!("{REPO}/CHANGELOG.md"),
        ])
        .arg(&root)
        .status()
        .unwrap();
    assert!(copied.success());
    change(&root);
    root
}

fn package(root: &Path, args: &[&str], env: &[(&str, &str)]) -> Output {
    let mut a = vec!["package", "--root", root.to_str().unwrap()];
    a.extend(args);
    run(READER, &a, env)
}

/// What tools/package.py said in each case (kept in tests/package/ before #195 step 3c deleted
/// it), with this checkout's version for `{V}`: (exit code, stdout, stderr).
fn python_said(label: &str) -> (Option<i32>, String, String) {
    let file = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/package/python_messages.json");
    let all: serde_json::Value = serde_json::from_str(&fs::read_to_string(file).unwrap()).unwrap();
    let case = &all[label];
    let v = toc_version();
    let t = |k: &str| case[k].as_str().unwrap().replace("{V}", &v);
    (
        case["code"].as_i64().map(|c| c as i32),
        t("stdout"),
        t("stderr"),
    )
}

fn toc_version() -> String {
    let t = fs::read_to_string(format!("{REPO}/HelloForever/HelloForever.toc")).unwrap();
    let line = t.lines().find(|l| l.starts_with("## Version:")).unwrap();
    line["## Version:".len()..].trim().to_string()
}

fn zip_of(root: &Path) -> PathBuf {
    let dist = root.join("dist");
    dist.join(&names(&dist)[0])
}

/// Each entry's name and general-purpose flags, read from the zip's central directory as the
/// zip format (APPNOTE 4.3.12) lays it out: signature 0x02014b50, flags at +8, the name's
/// length at +28, the extra and comment lengths at +30 and +32, the name at +46.
fn zip_flags(zip: &[u8]) -> Vec<(String, u16)> {
    let le16 = |at: usize| u16::from_le_bytes([zip[at], zip[at + 1]]) as usize;
    let mut out = vec![];
    let mut at = 0;
    while at + 46 <= zip.len() {
        if zip[at..at + 4] == [0x50, 0x4b, 0x01, 0x02] {
            let (n, e, c) = (le16(at + 28), le16(at + 30), le16(at + 32));
            let name = String::from_utf8_lossy(&zip[at + 46..at + 46 + n]).into_owned();
            out.push((name, le16(at + 8) as u16));
            at += 46 + n + e + c;
        } else {
            at += 1;
        }
    }
    out
}

#[test]
fn the_release_zip_is_the_python_one() {
    // a name beyond ASCII too: Python marked it UTF-8 in the zip (flag bit 11)
    let rs = root("package", &|r: &Path| {
        fs::write(r.join("HelloForever/\u{c9}quipement.lua"), "-- gear\n").unwrap();
        let toc = r.join("HelloForever/HelloForever.toc");
        let was = fs::read_to_string(&toc).unwrap();
        fs::write(&toc, format!("{was}\u{c9}quipement.lua\n")).unwrap();
    });
    let done = package(&rs, &["--no-tests"], &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    let out = text(&done.stdout);
    let lines: Vec<&str> = out.lines().collect();
    let v = toc_version();
    assert_eq!(
        lines[0],
        format!("HelloForever {v}: TOC, VERSION_FALLBACK, SOURCE_REVISION and CHANGELOG agree")
    );
    // the zip's own line is its SHA-256, and the same source gives the same zip
    let zip = zip_of(&rs);
    let zipped = fs::read(&zip).unwrap();
    assert_eq!(
        lines[1],
        format!("{}  dist/HelloForever-{v}.zip", sha256(&zipped))
    );
    let again = package(&rs, &["--no-tests"], &[]);
    assert_eq!(
        text(&again.stdout),
        out,
        "the same source gives the same zip"
    );
    // then each file's SHA-256, as tools/package.py printed them: the TOC, then the files it
    // loads, sorted by name
    let toc = fs::read_to_string(rs.join("HelloForever/HelloForever.toc")).unwrap();
    let mut files = vec!["HelloForever.toc".to_string()];
    files.extend(
        toc.lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .map(String::from),
    );
    files[1..].sort();
    let want: Vec<String> = files
        .iter()
        .map(|f| {
            let bytes = fs::read(rs.join("HelloForever").join(f)).unwrap();
            format!("{}  HelloForever/{f}", sha256(&bytes))
        })
        .collect();
    assert_eq!(lines[2..], want, "the per-file SHA-256 lines");
    // Info-ZIP reads it: the CRCs hold, each entry's bytes are the file's, and each entry is
    // as Python's zipfile wrote it: mode 0644, made on Unix, deflated, 1 Jan 2020 00:00
    let z = zip.to_str().unwrap();
    let tested = run("unzip", &["-tq", z], &[]);
    assert!(tested.status.success(), "{}", text(&tested.stdout));
    for f in &files {
        let entry = format!("HelloForever/{f}");
        let bytes = run("unzip", &["-p", z, &entry], &[]).stdout;
        assert_eq!(
            bytes,
            fs::read(rs.join(&entry)).unwrap(),
            "{entry}: its bytes"
        );
    }
    let listed = text(&run("zipinfo", &[z], &[]).stdout);
    let entries: Vec<&str> = listed
        .lines()
        .filter(|l| l.starts_with('?') || l.starts_with('-'))
        .collect();
    assert_eq!(entries.len(), files.len(), "{listed}");
    for line in entries {
        let w: Vec<&str> = line.split_whitespace().collect();
        assert_eq!(
            (w[0], w[2], w[5], w[6], w[7]),
            ("?rw-r--r--", "unx", "defN", "20-Jan-01", "00:00"),
            "{line}"
        );
    }
    // the entries in the order of the SHA-256 lines; the name beyond ASCII is marked UTF-8
    // (bit 11), the others are not
    let entries: Vec<String> = zip_flags(&zipped).into_iter().map(|(n, _)| n).collect();
    let order: Vec<String> = files.iter().map(|f| format!("HelloForever/{f}")).collect();
    assert_eq!(
        entries, order,
        "the TOC first, then its files sorted by name"
    );
    for (name, flags) in zip_flags(&zipped) {
        assert_eq!(flags & 0x800 != 0, !name.is_ascii(), "{name}: flag bit 11");
    }
}

#[test]
fn check_only_writes_no_zip() {
    // the changelog with old Mac line ends (CR only): Python read them as line ends too
    let rs = root("package-check", &|r: &Path| {
        let log = r.join("CHANGELOG.md");
        let was = fs::read_to_string(&log).unwrap();
        fs::write(&log, was.replace('\n', "\r")).unwrap();
    });
    let done = package(&rs, &["--check", "--no-tests"], &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    assert_eq!(text(&done.stdout), python_said("check-only").1);
    assert!(!rs.join("dist").exists());
}

#[test]
fn the_release_checks_fail_as_the_python_ones() {
    let edit = |root: &Path, file: &str, from: &str, to: &str| {
        let path = root.join(file);
        let was = fs::read_to_string(&path).unwrap();
        assert!(was.contains(from), "{file} has no {from:?}");
        fs::write(&path, was.replacen(from, to, 1)).unwrap();
    };
    let toc = "HelloForever/HelloForever.toc";
    let core = "HelloForever/Core.lua";
    let version = toc_version();
    let v = version.clone();
    let cases: Vec<Change> = vec![
        (
            "no version",
            Box::new(move |r: &Path| edit(r, toc, &format!("## Version: {v}"), "## Version:")),
        ),
        (
            "a fallback that differs",
            Box::new({
                let v = version.clone();
                move |r: &Path| {
                    edit(
                        r,
                        core,
                        &format!("ns.VERSION_FALLBACK = \"{v}\""),
                        "ns.VERSION_FALLBACK = \"it's 0.0\"",
                    )
                }
            }),
        ),
        (
            "no source revision",
            Box::new(|r: &Path| edit(r, core, "ns.SOURCE_REVISION", "ns.SOURCE_REVISION_X")),
        ),
        (
            "no changelog section",
            Box::new({
                let v = version.clone();
                move |r: &Path| {
                    edit(
                        r,
                        "CHANGELOG.md",
                        &format!("## HelloForever {v}"),
                        &format!("## HelloForever {v}x"),
                    )
                }
            }),
        ),
        (
            "a file the TOC loads is missing",
            Box::new(|r: &Path| {
                // not Core.lua: its constants are read before the TOC's files are looked at
                fs::remove_file(r.join("HelloForever/Commands.lua")).unwrap()
            }),
        ),
        (
            "several at once",
            Box::new({
                let v = version.clone();
                move |r: &Path| {
                    edit(
                        r,
                        core,
                        &format!("ns.SOURCE_REVISION = \"{v}\""),
                        "ns.SOURCE_REVISION = \"x\\\\y\"",
                    );
                    fs::write(r.join(toc), "## Version: 0'\"1\nMissing.lua\nCore.lua\n").unwrap();
                }
            }),
        ),
    ];
    for (label, change) in cases {
        let rs = root(&format!("package-{}", label.replace(' ', "-")), &*change);
        let done = package(&rs, &["--no-tests"], &[]);
        let (code, _, said) = python_said(&format!("fails: {label}"));
        assert_eq!(code, Some(1), "{label}: what Python did");
        assert_eq!(
            done.status.code(),
            Some(1),
            "{label}: {}",
            text(&done.stderr)
        );
        assert_eq!(text(&done.stderr), format!("hellolink: {said}"), "{label}");
        assert!(!rs.join("dist").exists(), "{label}");
    }
}

#[test]
fn the_tests_run_before_the_zip_as_in_python() {
    for (label, script, ok) in [
        (
            "passing",
            "#!/bin/sh\nprintf 'first\\n== 12 checks, 0 failed\\n\\n'\n",
            true,
        ),
        ("silent", "#!/bin/sh\nprintf '  \\n'\n", true),
        (
            "failing",
            "#!/bin/sh\necho \"$1: 1 failed\"\nexit 3\n",
            false,
        ),
    ] {
        let rs = root(&format!("package-tests-{label}"), &|_| {});
        let fake = rs.join("fakebin");
        fs::create_dir_all(&fake).unwrap();
        common::executable(&fake.join("lua5.1"), script);
        let path = format!("{}:{}", fake.display(), std::env::var("PATH").unwrap());
        // a failing suite stops the release before the zip; a passing one is seen in --check
        let args: &[&str] = if ok { &["--check"] } else { &[] };
        let done = package(&rs, args, &[("PATH", &path)]);
        let (code, said_out, said_err) = python_said(&format!("tests: {label}"));
        assert!(!rs.join("dist").exists(), "{label}");
        assert_eq!(done.status.success(), ok, "{label}");
        assert_eq!(code == Some(0), ok, "{label}: what Python did");
        assert_eq!(text(&done.stdout), said_out, "{label}");
        if !ok {
            assert_eq!(
                text(&done.stderr),
                format!("hellolink: {said_err}"),
                "{label}"
            );
        }
    }
}
