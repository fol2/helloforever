//! Floats as Python's repr() writes them: each line of tests/floats.txt (written by
//! reader/tests/floats.py with Python) read as a number and written again must be the same.

use hellolink::rows::py_float;

#[test]
fn floats_as_python_repr_writes_them() {
    let text = include_str!("floats.txt");
    let (mut seen, mut differ) = (0, vec![]);
    for line in text.lines() {
        let v: f64 = line.parse().unwrap();
        seen += 1;
        if py_float(v) != line {
            differ.push(format!("{line} -> {}", py_float(v)));
        }
    }
    assert!(seen >= 6000, "the floats are missing");
    assert!(
        differ.is_empty(),
        "{} of {seen} differ:\n{}",
        differ.len(),
        differ[..differ.len().min(20)].join("\n")
    );
}
