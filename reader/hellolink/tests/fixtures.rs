//! Parity with the Python reader without Python: each directory of tests/fixtures/ holds
//! cells files of the addon test (row_*.txt, read in the order of their numbers), `args`
//! (the scale and the step) and `rows.jsonl`, the lines `python3 tests/render_rows.py --scale
//! S --step T` printed for them. The lines here must be the same, byte for byte.

use hellolink::bitmap::{Bitmap, render};
use hellolink::rows::{py_float, rows_of_images};
use std::fs;
use std::path::PathBuf;

#[test]
fn the_python_readers_lines() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    let mut dirs: Vec<_> = fs::read_dir(&root)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    dirs.sort();
    assert!(dirs.len() >= 4, "the fixtures are missing");
    for dir in dirs {
        let args = fs::read_to_string(dir.join("args")).unwrap();
        let [scale, step] = args
            .split_whitespace()
            .map(|a| a.parse::<f64>().unwrap())
            .collect::<Vec<_>>()[..]
        else {
            panic!("{dir:?}: args is not two numbers");
        };
        let mut cells: Vec<_> = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|e| e == "txt"))
            .collect();
        cells.sort_by_key(|p| {
            p.file_stem().unwrap().to_str().unwrap()[4..]
                .parse::<u32>()
                .unwrap()
        });
        let images: Vec<Bitmap> = cells
            .iter()
            .map(|c| {
                Bitmap::new(
                    &render(&fs::read_to_string(c).unwrap(), scale, 0, 0, 2560, 12).unwrap(),
                )
                .unwrap()
            })
            .collect();
        let mut out = Vec::new();
        rows_of_images(&images, step, false, &mut out).unwrap();
        let want = fs::read_to_string(dir.join("rows.jsonl")).unwrap();
        assert_eq!(String::from_utf8(out).unwrap(), want, "{dir:?}");
    }
}

#[test]
fn floats_as_python_writes_them() {
    for (v, text) in [
        (2.0, "2.0"),
        (2.6785714285714284, "2.6785714285714284"),
        (-0.0, "-0.0"),
        (0.1, "0.1"),
        (1e16, "1e+16"),
        (1.5e-5, "1.5e-05"),
        (0.0001, "0.0001"),
        (123456789012345.6, "123456789012345.6"),
        (1.2345e-300, "1.2345e-300"),
    ] {
        assert_eq!(py_float(v), text);
    }
}
