//! The installers and the release packer of step 3b against the Python tools: `install` (the
//! slots) against tools/hellolink.py install, `install-reader` against the checks of
//! tests/install_reader_test.py, `package` against tools/package.py.

use hellolink::capture::{CAPTURE_SOURCE, capture_source};
use hellolink::package::sha256;
use std::collections::BTreeMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

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

fn run(program: &str, args: &[&str], env: &[(&str, &str)]) -> Output {
    Command::new(program)
        .args(args)
        .envs(env.iter().copied())
        .output()
        .unwrap()
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
                out.insert(name, (fs::read(&p).unwrap(), mode));
            }
        }
    }
    out
}

// ---- install: the slots ----

#[test]
fn the_slot_install_is_the_python_install() {
    let (rs, py) = (folder("slots-rs"), folder("slots-py"));
    let tool = format!("{REPO}/tools/hellolink.py");
    for (dir, program) in [(&rs, READER), (&py, "python3")] {
        // an earlier install with a text, then a new one over it, as a player's folder has
        fs::create_dir_all(dir.join("addons/HelloLink_S002")).unwrap();
        fs::write(
            dir.join("addons/HelloLink_S002/Inbox.lua"),
            "HelloLink_Inbox = { seq = 5, text = \"old\", slots = 2 }\n",
        )
        .unwrap();
        fs::write(
            dir.join("addons/HelloLink_S002/.parts.json"),
            "{\"seq\": 5}",
        )
        .unwrap();
        let args = ["install", "./addons/", "--slots", "3"]; // written back as Python writes a path
        let done = if program == "python3" {
            Command::new("python3")
                .arg(&tool)
                .args(args)
                .current_dir(dir)
                .output()
        } else {
            Command::new(program).args(args).current_dir(dir).output()
        }
        .unwrap();
        assert!(done.status.success(), "{}", text(&done.stderr));
        assert_eq!(
            text(&done.stdout),
            "installed HelloLink and 3 slots in addons\n"
        );
    }
    let (a, b) = (tree(&rs.join("addons")), tree(&py.join("addons")));
    assert_eq!(a.keys().collect::<Vec<_>>(), b.keys().collect::<Vec<_>>());
    for (name, (bytes, mode)) in &a {
        assert_eq!(bytes, &b[name].0, "{name}");
        // Inbox.lua is 0600 in both; the others follow the umask or the source's mode
        assert_eq!(mode, &b[name].1, "{name}");
    }
    // written out by hand from tools/hellolink.py
    assert_eq!(
        a["HelloLink_S003/HelloLink_S003.toc"].0,
        b"## Interface: 16001\n## Title: HelloLink slot 003\n## LoadOnDemand: 1\n## Group: HelloLink\n\nInbox.lua\n"
    );
    assert_eq!(
        a["HelloLink_S002/Inbox.lua"].0,
        b"HelloLink_Inbox = { seq = 0, text = \"\", slots = 3 }\n"
    );
    assert_eq!(a["HelloLink_S002/.parts.json"].0, b"{\"seq\": 5}");
    assert_eq!(
        a["HelloLink/HelloLink.toc"].0,
        fs::read(format!("{REPO}/HelloLink/HelloLink.toc")).unwrap()
    );
}

#[test]
fn the_slot_counts_the_install_refuses() {
    let dir = folder("slots-refused");
    let tool = format!("{REPO}/tools/hellolink.py");
    let at = |program: &str, args: &[&str]| {
        Command::new(program)
            .args(args)
            .current_dir(&dir)
            .output()
            .unwrap()
    };
    for n in ["0", "1000", "-7", "18446744073709551616"] {
        let rs = at(READER, &["install", "addons", "--slots", n]);
        let py = at("python3", &[&tool, "install", "addons", "--slots", n]);
        assert_eq!(rs.status.code(), Some(1), "{n}");
        assert_eq!(py.status.code(), Some(1), "{n}");
        assert_eq!(
            text(&rs.stderr),
            "hellolink: --slots must be 1 to 999\n",
            "{n}"
        );
        assert_eq!(text(&py.stderr), "--slots must be 1 to 999\n", "{n}");
    }
    assert!(!dir.join("addons").exists());
    let bad = at(READER, &["install", "addons", "--slots", "x"]);
    assert_eq!(
        text(&bad.stderr),
        "hellolink: install: argument --slots: invalid int value: \"x\"\n"
    );
}

// ---- install-reader ----

const SOURCES: [&str; 5] = [
    "reader/Cargo.toml",
    "reader/Cargo.lock",
    "reader/hellolink/Cargo.toml",
    "reader/hellolink/src",
    "tools/strip_capture.swift",
];

fn git(repo: &Path, args: &[&str]) -> String {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .output()
        .unwrap();
    assert!(out.status.success(), "git {args:?}: {}", text(&out.stderr));
    text(&out.stdout).trim().to_string()
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

fn set_time(path: &Path, t: SystemTime) {
    if path.is_dir() {
        for e in fs::read_dir(path).unwrap() {
            set_time(&e.unwrap().path(), t);
        }
    } else {
        fs::File::options()
            .write(true)
            .open(path)
            .unwrap()
            .set_modified(t)
            .unwrap();
    }
}

/// A git checkout of its own with the files the program is built from, all dated 1 Jan 2000.
fn other_checkout(base: &Path) -> PathBuf {
    let repo = base.join("repo");
    for s in SOURCES {
        let (from, to) = (Path::new(REPO).join(s), repo.join(s));
        fs::create_dir_all(to.parent().unwrap()).unwrap();
        if from.is_dir() {
            fs::create_dir_all(&to).unwrap();
            for e in fs::read_dir(&from).unwrap() {
                let p = e.unwrap().path();
                if p.is_file() {
                    fs::copy(&p, to.join(p.file_name().unwrap())).unwrap();
                }
            }
        } else {
            fs::copy(&from, &to).unwrap();
        }
    }
    git(&repo, &["init", "-q"]);
    git(&repo, &["add", "."]);
    git(
        &repo,
        &[
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.invalid",
            "commit",
            "-qm",
            "reader",
        ],
    );
    set_time(
        &repo.join("reader"),
        UNIX_EPOCH + Duration::from_secs(946_684_800),
    );
    set_time(
        &repo.join("tools"),
        UNIX_EPOCH + Duration::from_secs(946_684_800),
    );
    repo
}

/// Every file under `dir` with its bytes, and the names beside `dir`.
fn state(dir: &Path) -> (Tree, Vec<String>) {
    (tree(dir), names(dir.parent().unwrap()))
}

#[test]
fn the_reader_installs_outside_any_checkout() {
    let base = folder("reader");
    let to = base.join("Support/reader");
    let done = install_reader(&to, None, &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    let head = git(Path::new(REPO), &["rev-parse", "HEAD"]);
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
    assert_eq!(
        fs::read(to.join("strip_capture.swift")).unwrap(),
        fs::read(format!("{REPO}/tools/strip_capture.swift")).unwrap()
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

    // a second install leaves nothing of the first, and no temporary folder
    fs::create_dir(to.join("__pycache__")).unwrap();
    fs::write(
        to.join("__pycache__/left-over.cpython.pyc"),
        "older install",
    )
    .unwrap();
    let again = install_reader(&to, None, &[]);
    assert!(again.status.success(), "{}", text(&again.stderr));
    assert_eq!(names(&to), ["VERSION", "hellolink", "strip_capture.swift"]);
    assert_eq!(names(&base.join("Support")), ["reader"]);

    // an install of the Python reader is an earlier install: the switch is one command
    fs::remove_dir_all(&to).unwrap();
    let py = run(
        "python3",
        &[
            &format!("{REPO}/tools/install_reader.py"),
            "--to",
            to.to_str().unwrap(),
        ],
        &[],
    );
    assert!(py.status.success(), "{}", text(&py.stderr));
    fs::create_dir(to.join("__pycache__")).unwrap();
    fs::write(to.join("__pycache__/strip1.cpython-314.pyc"), "x").unwrap();
    let switched = install_reader(&to, None, &[]);
    assert!(switched.status.success(), "{}", text(&switched.stderr));
    assert_eq!(names(&to), ["VERSION", "hellolink", "strip_capture.swift"]);
}

#[test]
fn an_install_from_another_checkout_rebuilds_the_capture_tool() {
    let base = folder("reader-other");
    let repo = other_checkout(&base);
    let to = base.join("other/reader");
    let done = install_reader(&to, Some(&repo), &[]);
    assert!(done.status.success(), "{}", text(&done.stderr));
    assert_eq!(
        fs::read_to_string(to.join("VERSION")).unwrap().trim(),
        git(&repo, &["rev-parse", "HEAD"])
    );
    let copied = fs::metadata(to.join("strip_capture.swift"))
        .unwrap()
        .modified()
        .unwrap();
    assert!(copied > UNIX_EPOCH + Duration::from_secs(946_684_800 + 86_400));
}

#[test]
fn the_reader_install_refuses_and_changes_nothing() {
    let base = folder("reader-refused");
    let repo = other_checkout(&base);
    let to = base.join("Support/reader");
    assert!(install_reader(&to, Some(&repo), &[]).status.success());
    let refused = |why: &str, checkout: Option<&Path>, env: &[(&str, &str)], needle: &str| {
        let before = state(&to);
        let done = install_reader(&to, checkout, env);
        assert_eq!(done.status.code(), Some(1), "{why}: {}", text(&done.stderr));
        assert!(
            text(&done.stderr).contains(needle),
            "{why}: {}",
            text(&done.stderr)
        );
        assert!(state(&to) == before, "{why}: something changed");
    };
    // a file the program is built from differs from the commit
    let changed = repo.join("reader/hellolink/src/strip1.rs");
    let committed = fs::read(&changed).unwrap();
    fs::write(&changed, [&committed[..], b"// not committed\n"].concat()).unwrap();
    set_time(&changed, UNIX_EPOCH + Duration::from_secs(946_684_800));
    refused(
        "a changed source",
        Some(&repo),
        &[],
        "reader/hellolink/src/strip1.rs differs from",
    );
    git(
        &repo,
        &[
            "update-index",
            "--assume-unchanged",
            "reader/hellolink/src/strip1.rs",
        ],
    );
    refused(
        "a change git is told to ignore",
        Some(&repo),
        &[],
        "strip1.rs differs from",
    );
    fs::write(&changed, &committed).unwrap();
    // a source newer than the program: it was not built from them
    set_time(&changed, SystemTime::now() + Duration::from_secs(60));
    refused(
        "a source newer than the program",
        Some(&repo),
        &[],
        "strip1.rs is newer than",
    );
    set_time(&changed, UNIX_EPOCH + Duration::from_secs(946_684_800));
    // the commit lacks the capture source
    git(
        &repo,
        &["rm", "-q", "--cached", "tools/strip_capture.swift"],
    );
    git(
        &repo,
        &[
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.invalid",
            "commit",
            "-qm",
            "no swift",
        ],
    );
    refused(
        "no capture source",
        Some(&repo),
        &[],
        "lacks tools/strip_capture.swift",
    );
    // a process list that cannot be read is not "no reader runs"
    let fake = base.join("fakebin");
    fs::create_dir(&fake).unwrap();
    fs::write(fake.join("ps"), "#!/bin/sh\nexit 1\n").unwrap();
    fs::set_permissions(fake.join("ps"), fs::Permissions::from_mode(0o755)).unwrap();
    let path = format!("{}:{}", fake.display(), std::env::var("PATH").unwrap());
    refused(
        "a failed process list",
        None,
        &[("PATH", &path)],
        "cannot list the processes",
    );
    // a program that runs from the folder: this reader, the Python reader, the assistant
    for program in ["hellolink", "hellolink_strip.py", "assistant.py"] {
        let mut runner = Command::new("sh")
            .args(["-c", "sleep 60; :", to.join(program).to_str().unwrap()])
            .spawn()
            .unwrap();
        refused(program, None, &[], "runs from");
        runner.kill().unwrap();
        runner.wait().unwrap();
    }
    // folders that are not an install are never replaced
    let others: Vec<Change> = vec![
        (
            "other things",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
                fs::write(d.join("precious.txt"), "keep me\n").unwrap();
            }),
        ),
        (
            "only VERSION",
            Box::new(|d: &Path| fs::write(d.join("VERSION"), "x\n").unwrap()),
        ),
        (
            "a folder where a file goes",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
                fs::create_dir(d.join("strip_capture.swift")).unwrap();
                fs::write(d.join("strip_capture.swift/precious.txt"), "keep\n").unwrap();
            }),
        ),
        (
            "a link where a file goes",
            Box::new(|d: &Path| {
                fs::write(d.join("VERSION"), "x\n").unwrap();
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
        let before = names(&part);
        let done = install_reader(&part, None, &[]);
        assert_eq!(done.status.code(), Some(1), "{label}");
        assert!(
            text(&done.stderr).contains("not an earlier reader install"),
            "{label}: {}",
            text(&done.stderr)
        );
        assert_eq!(names(&part), before, "{label}");
    }
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

/// A root with the addon and the changelog of this checkout, and tools/package.py, for each
/// tool; `change` breaks it the same way in both.
fn roots(name: &str, change: &dyn Fn(&Path)) -> (PathBuf, PathBuf) {
    let base = folder(name);
    let made: Vec<PathBuf> = ["rs", "py"]
        .iter()
        .map(|side| {
            let root = base.join(side);
            fs::create_dir_all(root.join("tools")).unwrap();
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
            fs::copy(
                format!("{REPO}/tools/package.py"),
                root.join("tools/package.py"),
            )
            .unwrap();
            change(&root);
            root
        })
        .collect();
    (made[0].clone(), made[1].clone())
}

fn package(rs: &Path, py: &Path, args: &[&str], env: &[(&str, &str)]) -> (Output, Output) {
    let mut a = vec!["package", "--root", rs.to_str().unwrap()];
    a.extend(args);
    let mut b = vec![py.join("tools/package.py").to_string_lossy().into_owned()];
    b.extend(args.iter().map(|s| s.to_string()));
    let b: Vec<&str> = b.iter().map(String::as_str).collect();
    (run(READER, &a, env), run("python3", &b, env))
}

fn zip_of(root: &Path) -> PathBuf {
    let dist = root.join("dist");
    dist.join(&names(&dist)[0])
}

#[test]
fn the_release_zip_is_the_python_one() {
    let (rs, py) = roots("package", &|_| {});
    let (a, b) = package(&rs, &py, &["--no-tests"], &[]);
    assert!(
        a.status.success() && b.status.success(),
        "{} {}",
        text(&a.stderr),
        text(&b.stderr)
    );
    let (a, b) = (text(&a.stdout), text(&b.stdout));
    let (la, lb): (Vec<&str>, Vec<&str>) = (a.lines().collect(), b.lines().collect());
    assert_eq!(la.len(), lb.len());
    assert_eq!(la[0], lb[0]);
    assert_eq!(la[2..], lb[2..], "the per-file SHA-256 lines");
    assert!(la[1].ends_with(&format!("  dist/{}", names(&rs.join("dist"))[0])));
    // the zip's own line is its SHA-256, and the same source gives the same zip
    let zipped = fs::read(zip_of(&rs)).unwrap();
    assert_eq!(&la[1][..64], sha256(&zipped));
    let (again, _) = package(&rs, &py, &["--no-tests"], &[]);
    assert_eq!(text(&again.stdout), a);
    // Python's zipfile reads the same entries, times, modes and bytes from each zip
    let infos = r#"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
assert z.testzip() is None
for i in z.infolist():
    print(i.filename, i.date_time, oct(i.external_attr >> 16), i.compress_type, i.create_system, i.flag_bits, i.file_size, i.CRC)
"#;
    let ra = run(
        "python3",
        &["-I", "-c", infos, zip_of(&rs).to_str().unwrap()],
        &[],
    );
    let rb = run(
        "python3",
        &["-I", "-c", infos, zip_of(&py).to_str().unwrap()],
        &[],
    );
    assert!(ra.status.success(), "{}", text(&ra.stderr));
    assert_eq!(text(&ra.stdout), text(&rb.stdout));
    assert!(
        text(&ra.stdout)
            .starts_with("HelloForever/HelloForever.toc (2020, 1, 1, 0, 0, 0) 0o644 8 3 0 ")
    );
}

#[test]
fn check_only_writes_no_zip() {
    let (rs, py) = roots("package-check", &|_| {});
    let (a, b) = package(&rs, &py, &["--check", "--no-tests"], &[]);
    assert!(a.status.success());
    assert_eq!(text(&a.stdout), text(&b.stdout));
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
    let version = {
        let t = fs::read_to_string(format!("{REPO}/{toc}")).unwrap();
        let line = t
            .lines()
            .find(|l| l.starts_with("## Version:"))
            .unwrap()
            .to_string();
        line["## Version:".len()..].trim().to_string()
    };
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
                fs::remove_file(r.join("HelloForever/Core.lua"))
                    .map(|_| ())
                    .unwrap_or(())
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
                    fs::write(
                        r.join(toc),
                        format!("## Version: {v}\nMissing.lua\nCore.lua\n"),
                    )
                    .unwrap();
                }
            }),
        ),
    ];
    for (label, change) in cases {
        let (rs, py) = roots(&format!("package-{}", label.replace(' ', "-")), &*change);
        let (a, b) = package(&rs, &py, &["--no-tests"], &[]);
        assert_eq!(a.status.code(), Some(1), "{label}: {}", text(&a.stderr));
        assert_eq!(b.status.code(), Some(1), "{label}: {}", text(&b.stderr));
        let pe = text(&b.stderr);
        if pe.contains("Traceback") {
            // Python stops on a file it cannot read; the Rust program names it
            assert!(
                text(&a.stderr).contains("Core.lua"),
                "{label}: {}",
                text(&a.stderr)
            );
            continue;
        }
        assert_eq!(text(&a.stderr), format!("hellolink: {pe}"), "{label}");
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
        let (rs, py) = roots(&format!("package-tests-{label}"), &|_| {});
        let fake = rs.parent().unwrap().join("fakebin");
        fs::create_dir_all(&fake).unwrap();
        fs::write(fake.join("lua5.1"), script).unwrap();
        fs::set_permissions(fake.join("lua5.1"), fs::Permissions::from_mode(0o755)).unwrap();
        let path = format!("{}:{}", fake.display(), std::env::var("PATH").unwrap());
        let (a, b) = package(&rs, &py, &["--check"], &[("PATH", &path)]);
        assert_eq!(a.status.success(), ok, "{label}");
        assert_eq!(b.status.success(), ok, "{label}");
        assert_eq!(text(&a.stdout), text(&b.stdout), "{label}");
        if !ok {
            assert_eq!(
                text(&a.stderr),
                format!("hellolink: {}", text(&b.stderr)),
                "{label}"
            );
        }
    }
}
