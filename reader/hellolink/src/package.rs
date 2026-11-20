//! `package`: checks and packages a HelloForever release, as tools/package.py.
//!
//! Checks, before anything is built: the TOC version, `ns.VERSION_FALLBACK` and
//! `ns.SOURCE_REVISION` in Core.lua are the same; CHANGELOG.md has a section for that version;
//! every file the TOC loads exists. The zip holds a top-level HelloForever/ folder (the TOC and
//! the files it loads). Times and order are fixed, so the same source gives the same zip from
//! this program; Python's zlib packs other bytes, so compare the per-file SHA-256 lines, not the
//! zip's own.

use miniz_oxide::deflate::compress_to_vec;
use std::fs;
use std::path::Path;
use std::process::Command;

/// Python's str.splitlines(): every line break it knows.
fn lines(text: &str) -> impl Iterator<Item = &str> {
    text.split(|c| {
        matches!(
            c,
            '\n' | '\r'
                | '\x0b'
                | '\x0c'
                | '\x1c'
                | '\x1d'
                | '\x1e'
                | '\u{85}'
                | '\u{2028}'
                | '\u{2029}'
        )
    })
}

/// A text file, its line ends made "\n" (Python's read_text: universal newlines).
fn read(path: &Path) -> Result<String, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(text.replace("\r\n", "\n").replace('\r', "\n"))
}

/// The TOC's version and the files it loads, in order.
pub fn toc_info(addon: &Path) -> Result<(String, Vec<String>), String> {
    let (mut version, mut files) = (None, Vec::new());
    for line in lines(&read(&addon.join("HelloForever.toc"))?) {
        let line = line.trim();
        // ^##\s*Version:\s*(\S+)
        let found = line
            .strip_prefix("##")
            .map(str::trim_start)
            .and_then(|l| l.strip_prefix("Version:"))
            .map(str::trim_start)
            .and_then(|l| l.split(char::is_whitespace).next())
            .filter(|v| !v.is_empty());
        if let Some(v) = found {
            version = Some(v.to_string());
        } else if !line.is_empty() && !line.starts_with('#') {
            files.push(line.to_string());
        }
    }
    let version = version.ok_or("HelloForever.toc has no ## Version")?;
    Ok((version, files))
}

/// The first `ns.NAME = "value"` in the text (ns\.NAME\s*=\s*"([^"]+)").
fn assigned<'a>(text: &'a str, name: &str) -> Option<&'a str> {
    let key = format!("ns.{name}");
    text.match_indices(&key).find_map(|(at, _)| {
        let rest = text[at + key.len()..].trim_start();
        let rest = rest.strip_prefix('=')?.trim_start();
        let rest = rest.strip_prefix('"')?;
        let end = rest.find('"')?;
        (end > 0).then(|| &rest[..end])
    })
}

/// Python's \w for one character.
fn word(c: Option<char>) -> bool {
    c.is_some_and(|c| c.is_alphanumeric() || c == '_')
}

/// True when a line starts with `## HelloForever <version>` and a word ends there (re.M, \b).
fn has_section(changelog: &str, version: &str) -> bool {
    let head = format!("## HelloForever {version}");
    changelog.split('\n').any(|line| {
        line.strip_prefix(&head)
            .is_some_and(|rest| word(version.chars().last()) != word(rest.chars().next()))
    })
}

/// Python's repr() of a str, for the messages.
fn repr(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::from(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

/// The release checks; Ok is the version and the files the TOC loads.
pub fn check(root: &Path) -> Result<(String, Vec<String>), String> {
    let addon = root.join("HelloForever");
    let (version, files) = toc_info(&addon)?;
    let mut problems = Vec::new();
    let core = read(&addon.join("Core.lua"))?;
    for name in ["VERSION_FALLBACK", "SOURCE_REVISION"] {
        match assigned(&core, name) {
            None => problems.push(format!("Core.lua has no ns.{name}")),
            Some(v) if v != version => problems.push(format!(
                "ns.{name} is {} but the TOC says {}",
                repr(v),
                repr(&version)
            )),
            Some(_) => {}
        }
    }
    if !has_section(&read(&root.join("CHANGELOG.md"))?, &version) {
        problems.push(format!(
            "CHANGELOG.md has no '## HelloForever {version}' section"
        ));
    }
    for name in &files {
        if !addon.join(name).is_file() {
            problems.push(format!("the TOC loads {name}, which does not exist"));
        }
    }
    if !problems.is_empty() {
        return Err(format!(
            "release check failed:\n  {}",
            problems.join("\n  ")
        ));
    }
    Ok((version, files))
}

/// The two Lua suites, as tools/package.py runs them; each line goes to `say`.
pub fn run_tests(root: &Path, say: &mut dyn FnMut(String)) -> Result<(), String> {
    for test in ["tests/id_freshness.lua", "tests/fights_harness_v4.lua"] {
        let shown = format!("lua5.1 {test}");
        let done = Command::new("lua5.1")
            .arg(test)
            .current_dir(root)
            .output()
            .map_err(|e| format!("{shown}: {e}"))?;
        let out = String::from_utf8_lossy(&done.stdout);
        let tail = lines(out.trim())
            .last()
            .filter(|l| !l.is_empty())
            .unwrap_or("(no output)");
        say(format!("  {shown}: {tail}"));
        if !done.status.success() {
            return Err(format!("tests failed: {shown}"));
        }
    }
    Ok(())
}

/// SHA-256 (FIPS 180-4), as lowercase hex.
pub fn sha256(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend((data.len() as u64 * 8).to_be_bytes());
    for block in msg.chunks(64) {
        let mut w = [0u32; 64];
        for (i, word) in block.chunks(4).enumerate() {
            w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            (hh, g, f, e, d, c, b, a) = (g, f, e, d.wrapping_add(t1), c, b, a, t1.wrapping_add(t2));
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *x = x.wrapping_add(y);
        }
    }
    h.iter().map(|x| format!("{x:08x}")).collect()
}

/// CRC-32 (IEEE, as zip uses it).
fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = (crc >> 1) ^ (0xedb8_8320 & (crc & 1).wrapping_neg());
        }
    }
    !crc
}

/// A zip of (name, bytes), deflated, every entry dated 1 Jan 2020 00:00 with mode 0644, as
/// tools/package.py writes it (zipfile, ZIP_DEFLATED).
pub fn zip(entries: &[(String, Vec<u8>)]) -> Result<Vec<u8>, String> {
    const DATE: u16 = (40 << 9) | (1 << 5) | 1; // 2020-01-01; the time is 00:00:00
    let mut out = Vec::new();
    let mut central = Vec::new();
    let small =
        |n: usize, what: &str| u32::try_from(n).map_err(|_| format!("{what} is too big for a zip"));
    for (name, data) in entries {
        let packed = compress_to_vec(data, 9);
        let (crc, offset) = (crc32(data), small(out.len(), "the zip")?);
        let (csize, size) = (small(packed.len(), name)?, small(data.len(), name)?);
        let name_len = u16::try_from(name.len()).map_err(|_| format!("{name}: name too long"))?;
        // bit 11: the name is UTF-8 (Python sets it for a name beyond ASCII)
        let flags: u16 = if name.is_ascii() { 0 } else { 0x800 };
        let common = |v: &mut Vec<u8>| {
            v.extend(20u16.to_le_bytes()); // version needed: 2.0
            v.extend(flags.to_le_bytes());
            v.extend(8u16.to_le_bytes()); // deflated
            v.extend(0u16.to_le_bytes()); // time
            v.extend(DATE.to_le_bytes());
            v.extend(crc.to_le_bytes());
            v.extend(csize.to_le_bytes());
            v.extend(size.to_le_bytes());
            v.extend(name_len.to_le_bytes());
            v.extend(0u16.to_le_bytes()); // extra
        };
        out.extend(0x0403_4b50u32.to_le_bytes());
        common(&mut out);
        out.extend(name.as_bytes());
        out.extend(&packed);
        central.extend(0x0201_4b50u32.to_le_bytes());
        central.extend(0x0314u16.to_le_bytes()); // made by: Unix, 2.0
        common(&mut central);
        central.extend(0u16.to_le_bytes()); // comment
        central.extend(0u16.to_le_bytes()); // disk
        central.extend(0u16.to_le_bytes()); // internal attributes
        central.extend((0o644u32 << 16).to_le_bytes());
        central.extend(offset.to_le_bytes());
        central.extend(name.as_bytes());
    }
    let count = u16::try_from(entries.len()).map_err(|_| "too many files for a zip")?;
    let (at, size) = (
        small(out.len(), "the zip")?,
        small(central.len(), "the zip")?,
    );
    out.extend(central);
    out.extend(0x0605_4b50u32.to_le_bytes());
    out.extend([0u8; 4]); // this disk, the disk with the directory
    out.extend(count.to_le_bytes());
    out.extend(count.to_le_bytes());
    out.extend(size.to_le_bytes());
    out.extend(at.to_le_bytes());
    out.extend(0u16.to_le_bytes()); // comment
    Ok(out)
}

/// The whole command: checks, the tests unless `no_tests`, then (unless `check_only`) the zip in
/// <root>/dist and the SHA-256 lines. Each line of output goes to `say`.
pub fn package(
    root: &Path,
    check_only: bool,
    no_tests: bool,
    say: &mut dyn FnMut(String),
) -> Result<(), String> {
    let (version, files) = check(root)?;
    say(format!(
        "HelloForever {version}: TOC, VERSION_FALLBACK, SOURCE_REVISION and CHANGELOG agree"
    ));
    if !no_tests {
        run_tests(root, say)?;
    }
    if check_only {
        return Ok(());
    }
    let addon = root.join("HelloForever");
    let mut names = vec!["HelloForever.toc".to_string()];
    let mut sorted = files;
    sorted.sort();
    names.extend(sorted);
    let entries = names
        .iter()
        .map(|n| {
            let path = addon.join(n);
            fs::read(&path)
                .map(|data| (format!("HelloForever/{n}"), data))
                .map_err(|e| format!("{}: {e}", path.display()))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let shown = format!("dist/HelloForever-{version}.zip");
    let dist = root.join("dist");
    match fs::create_dir(&dist) {
        Err(e) if !(e.kind() == std::io::ErrorKind::AlreadyExists && dist.is_dir()) => {
            return Err(format!("{}: {e}", dist.display()));
        }
        _ => {}
    }
    let zipped = zip(&entries)?;
    fs::write(root.join(&shown), &zipped).map_err(|e| format!("{shown}: {e}"))?;
    say(format!("{}  {shown}", sha256(&zipped)));
    for (name, data) in &entries {
        say(format!("{}  {name}", sha256(data)));
    }
    Ok(())
}
