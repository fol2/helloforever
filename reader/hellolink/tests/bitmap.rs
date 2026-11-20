//! The checks of tests/hellolink_strip_test.py (deleted in #195 step 3c) that read no depth
//! probe: the bitmap refuses what is not one, and the screenshot fall-back leaves nothing
//! behind. The depth probe itself was the spike's measurement and was not ported (#195).

use hellolink::bitmap::{Bitmap, render};
use hellolink::capture::Screencapture;
use std::cell::RefCell;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::rc::Rc;

/// A rendered image of some squares on the renderer's noisy background, 1400 x 300.
fn shot() -> Vec<u8> {
    let cells: String = (0..40)
        .map(|i| {
            format!(
                "{} 0 6 6 {} {} {}\n",
                i * 6,
                (i & 4 != 0) as u8,
                (i & 2 != 0) as u8,
                i & 1
            )
        })
        .collect();
    render(&cells, 2.0, 40, 60, 1400, 300).unwrap()
}

#[test]
fn a_bitmap_refuses_what_is_not_one() {
    let whole = shot();
    assert_eq!(
        Bitmap::new(&whole).map(|b| b.width).ok(),
        Some(1400),
        "a rendered image is a bitmap the reader takes"
    );
    let at = |offset: usize, value: [u8; 4]| {
        let mut b = whole.clone();
        b[offset..offset + 4].copy_from_slice(&value);
        b
    };
    let past = ((whole.len() + 1000) as u32).to_le_bytes();
    let cases: [(&str, Vec<u8>); 5] = [
        ("a header with no pixels is refused", whole[..138].to_vec()),
        (
            "a file cut short is refused",
            whole[..whole.len() / 2].to_vec(),
        ),
        ("a pixel offset past the file is refused", at(10, past)),
        (
            "an absurd width is refused",
            at(18, 2_000_000_000i32.to_le_bytes()),
        ),
        ("fifty-three bytes are not a BMP", whole[..53].to_vec()),
    ];
    for (name, data) in cases {
        assert!(Bitmap::new(&data).is_err(), "{name}");
    }
}

/// A turn of the screenshot fall-back whose `screencapture` writes `image` to each path it is
/// given, after `before` has run on the turn's folder. The folder is given back.
fn turn(image: Vec<u8>, before: impl Fn(&Path) + 'static) -> (Result<usize, String>, PathBuf) {
    let folder = Rc::new(RefCell::new(PathBuf::new()));
    let seen = folder.clone();
    let mut frames = Screencapture::new(Box::new(move |command: &[String]| {
        for path in command.iter().filter(|w| w.ends_with(".bmp")) {
            fs::write(path, &image).unwrap();
            *seen.borrow_mut() = Path::new(path).parent().unwrap().to_path_buf();
        }
        before(&seen.borrow());
        Ok(())
    }));
    let got = frames
        .turn(&mut |_| {})
        .map(|b| b.map_or(0, |b| b.width))
        .map_err(|e| format!("{e:?}"));
    let folder = folder.borrow().clone();
    (got, folder)
}

#[test]
fn a_screenshot_is_handed_on_and_deleted() {
    let (got, folder) = turn(shot(), |_| {});
    assert_eq!(
        got,
        Ok(1400),
        "on_screen hands each screenshot to the reader"
    );
    assert!(!folder.exists(), "and leaves no screenshot behind");
    // a folder in the turn's folder that keeps its file: the turn's folder cannot be deleted
    let (got, folder) = turn(shot(), |dir| {
        let locked = dir.join("locked");
        fs::create_dir(&locked).unwrap();
        fs::write(locked.join("kept"), "x").unwrap();
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o500)).unwrap();
    });
    let _ = fs::set_permissions(folder.join("locked"), fs::Permissions::from_mode(0o700));
    let _ = fs::remove_dir_all(&folder);
    assert!(
        got.is_err(),
        "a screenshot that cannot be deleted is an error, not a success ({got:?})"
    );
}
