//! `watch` with a world the test gives (`follow` and its `World`): the checks of
//! tests/strip_waiting_test.py, strip_waiting_fallback_test.py, strip_stream_again_test.py,
//! strip_slow_stream_test.py, strip_replayd_hint_test.py, strip_stream_back_test.py (its first
//! four), strip_start_test.py, strip_fallback_test.py, strip_fallback_missing_test.py and the
//! command-line part of strip_record_test.py. Each assert's message is the Python check's
//! name. The Python tests replace the clock, the sleeps and the capture functions of the
//! module; here the World's are replaced, the same way. Time is the test's clock only.

use crate::common::*;
use hellolink::bitmap::{Bitmap, render};
use hellolink::capture::{Colour, Found, Screencapture, Unrun, look};
use hellolink::follow::{Args, Frames, Halt, NoProcess, World, follow, parse_watch};
use hellolink::strip1::{read_row, row_colours};
use hellolink::watch::Watcher;
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::rc::Rc;

/// What the reader wrote; `first_wait` gets "wait" when the first `waiting` line is written.
#[derive(Clone, Default)]
struct Buf(Rc<RefCell<Vec<u8>>>, Option<Rc<RefCell<Vec<&'static str>>>>);

impl Write for Buf {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        if let Some(order) = &self.1
            && String::from_utf8_lossy(data).contains("\"waiting\"")
            && !order.borrow().contains(&"wait")
        {
            order.borrow_mut().push("wait");
        }
        self.0.borrow_mut().extend_from_slice(data);
        Ok(data.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Buf {
    fn text(&self) -> String {
        String::from_utf8_lossy(&self.0.borrow()).into_owned()
    }
    fn events(&self) -> Vec<Value> {
        self.text()
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }
}

fn kinds(events: &[Value]) -> Vec<String> {
    events
        .iter()
        .map(|e| e["kind"].as_str().unwrap().to_string())
        .collect()
}

fn whys(events: &[Value]) -> Vec<String> {
    events
        .iter()
        .filter(|e| e["kind"] == "waiting")
        .map(|e| e["why"].as_str().unwrap().to_string())
        .collect()
}

thread_local! {
    static DISPLAYS: RefCell<HashMap<(u32, bool), Vec<u8>>> = RefCell::new(HashMap::new());
}

/// A display's image as `screencapture` writes it, 1280 x 200 with noise all over; with
/// `row`, the row of seq `seq` on it from x = 0.
fn display_bmp(seq: u32, row: bool) -> Vec<u8> {
    DISPLAYS.with(|cache| {
        cache
            .borrow_mut()
            .entry((seq, row))
            .or_insert_with(|| {
                let cells: String = if row {
                    row_colours(4711, 4, LEVELS, &frame(seq))
                        .iter()
                        .enumerate()
                        .map(|(i, [r, g, b])| format!("{} 0 2 2 {r:.6} {g:.6} {b:.6}\n", i * 2))
                        .collect()
                } else {
                    String::new()
                };
                render(&cells, 1.0, 0, 0, 1280, 200).unwrap()
            })
            .clone()
    })
}

fn display(seq: u32, row: bool) -> Bitmap {
    Bitmap::new(&display_bmp(seq, row)).unwrap()
}

/// What a look at display 1 (1280 wide) that shows `image` finds.
fn found(display: i64, image: &Bitmap) -> Found {
    (display, 1280, read_row(image, None).unwrap().grid.unwrap())
}

type Clock = Rc<Cell<f64>>;

/// A world on the test's clock: sleeps move it; no capture tool part is there until the test
/// gives it (each ends the watch).
fn world(clock: &Clock, out: &Buf, err: &Buf) -> World {
    let (c1, c2) = (clock.clone(), clock.clone());
    World {
        now: Box::new(move || c1.get()),
        sleep: Box::new(move |s| {
            c2.set(c2.get() + s);
            Ok(())
        }),
        capture_tool: Box::new(|_| Ok(PathBuf::from("tool"))),
        locate: Box::new(|_, _| Err(Halt::Stop)),
        stream: Box::new(|_, _| Box::new(NoProcess(std::iter::once(Err(Halt::Stop))))),
        screencapture: Box::new(|_| Err(Halt::Stop)),
        out: Box::new(out.clone()),
        err: Box::new(err.clone()),
        reader_left: || false,
        tell: Box::new(|_| {}),
    }
}

fn args(words: &[&str]) -> Args {
    parse_watch(&words.iter().map(|s| s.to_string()).collect::<Vec<_>>()).unwrap()
}

/// A sleep that ends the watch once the clock is past `end`.
fn sleep_until(clock: &Clock, end: f64) -> Box<dyn FnMut(f64) -> Result<(), Halt>> {
    let c = clock.clone();
    Box::new(move |s| {
        c.set(c.get() + s);
        if c.get() > end {
            Err(Halt::Stop)
        } else {
            Ok(())
        }
    })
}

/// An iterator that runs `step(n)` for its n-th item, from 0; Python's generators, whose code
/// runs only when the next item is asked for.
fn lazily(mut step: impl FnMut(usize) -> Option<Result<Option<Bitmap>, Halt>> + 'static) -> Frames {
    let mut n = 0;
    Box::new(NoProcess(std::iter::from_fn(move || {
        n += 1;
        step(n - 1)
    })))
}

// --- tests/strip_waiting_test.py: while no display shows the row, `waiting`, never `relocate` ---

#[test]
fn waiting_while_no_display_shows_the_row() {
    let (clock, out, err) = (Rc::new(Cell::new(1000.0)), Buf::default(), Buf::default());
    let mut w = world(&clock, &out, &err);
    w.sleep = sleep_until(&clock, 1150.0); // 150 s with no row
    w.locate = Box::new(|_, _| Ok(Err("no row on any display".into())));
    follow(&args(&["--json"]), &mut w).unwrap();
    let events = out.events();
    let kinds = kinds(&events);
    assert!(
        !kinds.contains(&"relocate".into()),
        "no row on any display: no `relocate` line"
    );
    assert_eq!(
        kinds.iter().filter(|k| *k == "waiting").count(),
        4,
        "`waiting` at the start (#80), then again once a minute: 4 lines in 150 s"
    );
    assert_eq!(
        whys(&events),
        [
            "looking for the row",
            "no row on any display",
            "no row on any display",
            "no row on any display"
        ],
        "every `waiting` line says why: looking at the start, then no row"
    );
}

// --- tests/strip_api_test.py: `watch --serve` tells the API what it prints ---

#[test]
fn every_event_printed_is_told() {
    let (clock, out, err) = (Rc::new(Cell::new(1000.0)), Buf::default(), Buf::default());
    let heard = Rc::new(RefCell::new(Vec::new()));
    let mut w = world(&clock, &out, &err);
    w.sleep = sleep_until(&clock, 1150.0);
    w.locate = Box::new(|_, _| Ok(Err("no row on any display".into())));
    let h = Rc::clone(&heard);
    w.tell = Box::new(move |e| h.borrow_mut().push(e.clone()));
    follow(&args(&["--json"]), &mut w).unwrap();
    let printed = out.events();
    assert_eq!(printed.len(), 4);
    assert_eq!(
        *heard.borrow(),
        printed,
        "it tells the API every event it prints (#80's `waiting` first)"
    );
}

// --- tests/strip_waiting_fallback_test.py: the same on the slow fall-back ---

#[test]
fn waiting_on_the_slow_fall_back() {
    let (clock, out, err) = (Rc::new(Cell::new(1000.0)), Buf::default(), Buf::default());
    let mut w = world(&clock, &out, &err);
    w.capture_tool = Box::new(|_| Err("no tool".into()));
    w.sleep = Box::new(|_| Ok(())); // Python's fake fall-back has no pause
    let (c, blank) = (clock.clone(), display(0, false));
    let mut turn = 0;
    // a display with no row, three images a second, for 150 s; every tenth turn no image
    w.screencapture = Box::new(move |_| {
        if turn > 0 {
            c.set(c.get() + 0.3);
        }
        if c.get() > 1150.0 {
            return Err(Halt::Stop);
        }
        turn += 1;
        Ok(if turn % 10 == 0 {
            None
        } else {
            Some(blank.clone())
        })
    });
    follow(&args(&["--json"]), &mut w).unwrap();
    let events = out.events();
    let kinds = kinds(&events);
    assert!(
        !kinds.contains(&"relocate".into()),
        "the fall-back, no row on the display: no `relocate` line"
    );
    assert_eq!(
        kinds.iter().filter(|k| *k == "waiting").count(),
        4,
        "the fall-back: `waiting` at the start (#80), then again once a minute: 4 lines in 150 s"
    );
    assert_eq!(
        whys(&events),
        [
            "looking for the row",
            "no row on any display",
            "no row on any display",
            "no row on any display"
        ],
        "the fall-back: every `waiting` line says why: looking at the start, then no row"
    );
}

// --- tests/strip_stream_again_test.py: a failed stream is tried again, never the fall-back ---

/// `watch` for `seconds` of the test's clock. `answers(n)`: the n-th look at the stream
/// answers (no row), or fails. The times of the looks and of the screencapture turns, and
/// what went to stderr.
fn again(tool: bool, answers: fn(usize) -> bool, seconds: f64) -> (Vec<f64>, Vec<f64>, String) {
    let (clock, out, err) = (Rc::new(Cell::new(0.0)), Buf::default(), Buf::default());
    let looks = Rc::new(RefCell::new(vec![]));
    let turns = Rc::new(RefCell::new(vec![]));
    let mut w = world(&clock, &out, &err);
    w.sleep = sleep_until(&clock, seconds);
    if !tool {
        w.capture_tool = Box::new(|_| Err("no tool".into()));
    }
    let (c, l) = (clock.clone(), looks.clone());
    w.locate = Box::new(move |_, _| {
        l.borrow_mut().push(c.get());
        if !answers(l.borrow().len()) {
            return Err(Halt::Failed("no frame in 3 s".into()));
        }
        Ok(Err("no row on any display".into()))
    });
    let (c, t, blank) = (clock.clone(), turns.clone(), display(0, false));
    w.screencapture = Box::new(move |_| {
        if !t.borrow().is_empty() {
            c.set(c.get() + 0.3);
        }
        if c.get() > seconds {
            return Err(Halt::Stop);
        }
        t.borrow_mut().push(c.get());
        Ok(Some(blank.clone()))
    });
    follow(&args(&["--json"]), &mut w).unwrap();
    let (looks, turns) = (looks.borrow().clone(), turns.borrow().clone());
    (looks, turns, err.text())
}

#[test]
fn a_failed_stream_is_tried_again() {
    let (once, once_turns, once_notes) = again(true, |n| n > 1, 200.0);
    let (never, never_turns, never_notes) = again(true, |_| false, 200.0);
    let (none, none_turns, _) = again(false, |_| true, 150.0);
    let gaps: Vec<i64> = never
        .windows(2)
        .map(|w| (w[1] - w[0]).round() as i64)
        .collect();
    assert!(
        once.len() > 1 && (1.5..=3.0).contains(&(once[1] - once[0])),
        "the stream failed once: it is tried again after 2 s (looks at {once:?})"
    );
    assert!(
        once_turns.is_empty() && never_turns.is_empty(),
        "no screencapture while there is a capture tool"
    );
    assert!(
        gaps[..5] == [2, 4, 8, 16, 30] && gaps[5..].iter().all(|g| *g == 30),
        "the stream fails every time: the pauses grow 2, 4, 8, 16, then 30 s each ({gaps:?})"
    );
    assert!(
        never.len() >= 9,
        "so it is tried again at most each 30 s, never left: {} looks in 200 s",
        never.len()
    );
    assert!(
        none.is_empty() && none_turns.len() > 100,
        "no capture tool: no look at a stream, and screencapture runs (got {} looks, {} turns)",
        none.len(),
        none_turns.len()
    );
    assert_eq!(
        never_notes.matches("killall replayd").count(),
        1,
        "a stream that keeps failing gets one note: restarting replayd helped once (#113)"
    );
    assert!(
        !once_notes.contains("killall replayd"),
        "a stream that failed once gets no such note"
    );
}

// --- tests/strip_slow_stream_test.py: a stream whose first frame is slow is waited for ---

struct Slow {
    looks: Vec<f64>,
    streams: Vec<f64>,
    events: Vec<Value>,
}

/// A stream that is silent for `silent_for` seconds, then gives frames. With `before`, a
/// first stream gives that many frames and then fails. With `jump`, the silence is one step:
/// the first frame itself comes late.
fn slow(silent_for: f64, before: u32, jump: bool) -> Slow {
    let (clock, out, err) = (Rc::new(Cell::new(0.0)), Buf::default(), Buf::default());
    let (seq, looks, streams) = (
        Rc::new(Cell::new(0)),
        Rc::new(RefCell::new(vec![])),
        Rc::new(RefCell::new(vec![])),
    );
    let mut w = world(&clock, &out, &err);
    let (c, s, l) = (clock.clone(), seq.clone(), looks.clone());
    w.locate = Box::new(move |_, _| {
        l.borrow_mut().push(c.get());
        if l.borrow().len() > 3 {
            return Err(Halt::Stop);
        }
        s.set(s.get() + 1);
        Ok(Ok(found(1, &display(s.get(), true))))
    });
    let (c, s, st) = (clock.clone(), seq.clone(), streams.clone());
    w.stream = Box::new(move |_, idle| {
        let (c, s, st) = (c.clone(), s.clone(), st.clone());
        let (mut given, mut start) = (0, 0.0);
        let mut frames = false;
        let mut first = true;
        lazily(move |n| {
            let image = |c: &Clock, s: &Rc<Cell<u32>>| {
                s.set(s.get() + 1);
                c.set(c.get() + 0.1);
                Some(Ok(Some(display(s.get(), true))))
            };
            if n == 0 {
                st.borrow_mut().push(c.get());
                start = c.get();
                first = st.borrow().len() == 1 && before > 0;
                if !first && jump {
                    c.set(c.get() + silent_for);
                }
            }
            if first {
                if given < before {
                    given += 1;
                    return image(&c, &s);
                }
                return (given == before).then(|| {
                    given += 1;
                    Err(Halt::Failed("the display went away".into()))
                });
            }
            if !frames && c.get() - start < silent_for {
                c.set(c.get() + idle);
                return Some(Ok(None));
            }
            frames = true;
            if given < 5 {
                given += 1;
                return image(&c, &s);
            }
            Some(Err(Halt::Stop))
        })
    });
    follow(&args(&["--json"]), &mut w).unwrap();
    let (looks, streams) = (looks.borrow().clone(), streams.borrow().clone());
    Slow {
        looks,
        streams,
        events: out.events(),
    }
}

#[test]
fn a_slow_first_frame_of_a_stream() {
    let r = slow(8.0, 0, false);
    assert!(
        r.looks.len() == 1 && r.streams.len() == 1,
        "a stream silent for 8 s is kept: one look, one stream ({} looks, {} streams)",
        r.looks.len(),
        r.streams.len()
    );
    assert!(
        kinds(&r.events).iter().filter(|k| *k == "state").count() >= 5,
        "... and its frames give states"
    );
    let r = slow(60.0, 0, false);
    assert!(
        r.streams.len() >= 2 && (15.0..=20.0).contains(&(r.streams[1] - r.streams[0])),
        "a stream silent for longer than the limit is given up after it, and tried again (streams at {:?})",
        r.streams
    );
    assert!(
        r.events.iter().any(|e| e["kind"] == "waiting"
            && e["why"].as_str().unwrap_or("").contains("does not answer")),
        "... with `waiting` and the reason"
    );
    let r = slow(8.0, 3, false);
    let k = kinds(&r.events);
    let at = |kind: &str| k.iter().position(|x| x == kind);
    assert!(
        at("stale").is_some() && at("stale") > at("state"),
        "while a new stream is silent, the state known before goes stale ({k:?})"
    );
    assert_eq!(
        r.streams.len(),
        2,
        "... and the new stream is still kept, not cut at 3 s"
    );
    let r = slow(16.0, 0, true);
    assert!(
        !kinds(&r.events).contains(&"state".into()) && r.streams.len() >= 2,
        "a first frame that comes after the limit is not taken: no state from it, the stream is tried again ({} streams)",
        r.streams.len()
    );
}

// --- tests/strip_replayd_hint_test.py: the note about replayd comes once a run ---

#[test]
fn the_note_about_replayd_comes_once() {
    let (clock, out, err) = (Rc::new(Cell::new(0.0)), Buf::default(), Buf::default());
    let streams = Rc::new(Cell::new(0));
    let mut w = world(&clock, &out, &err);
    w.locate = Box::new(|_, _| Ok(Ok(found(1, &display(1, true)))));
    let (c, st) = (clock.clone(), streams.clone());
    w.stream = Box::new(move |_, _| {
        let (c, st) = (c.clone(), st.clone());
        lazily(move |n| {
            if n == 0 {
                st.set(st.get() + 1);
            }
            Some(match (st.get(), n) {
                (1 | 2 | 3 | 5 | 6 | 7, _) => Err(Halt::Failed("no frame in 15 s".into())),
                (4, 0) => {
                    // the stream answers once, between the two series
                    c.set(c.get() + 0.1);
                    Ok(Some(display(2, true)))
                }
                (4, _) => Err(Halt::Failed("the display went away".into())),
                _ => Err(Halt::Stop),
            })
        })
    });
    follow(&args(&["--json"]), &mut w).unwrap();
    let count = err.text().matches("killall replayd").count();
    assert!(
        streams.get() >= 7 && count == 1,
        "three failures, an answer, three failures: one note, not two ({count} notes, {} streams)",
        streams.get()
    );
}

// --- tests/strip_stream_back_test.py: after a failure the reader follows the stream ---

#[test]
fn the_stream_answers_again() {
    let (clock, out, err) = (Rc::new(Cell::new(0.0)), Buf::default(), Buf::default());
    let seq = Rc::new(Cell::new(0));
    let source = Rc::new(RefCell::new(Vec::<&str>::new()));
    let streams = Rc::new(RefCell::new(Vec::<Vec<String>>::new()));
    let image = {
        let (seq, source) = (seq.clone(), source.clone());
        move |by: &'static str| {
            seq.set(seq.get() + 1);
            source.borrow_mut().push(by);
            display(seq.get(), true)
        }
    };
    let mut w = world(&clock, &out, &err);
    w.sleep = Box::new(|_| Ok(())); // Python's test left time.sleep alone: the clock stands
    let (looks, im) = (Rc::new(Cell::new(0)), image.clone());
    w.locate = Box::new(move |_, _| {
        looks.set(looks.get() + 1);
        if looks.get() == 1 {
            return Err(Halt::Failed("no frame in 3 s".into()));
        }
        Ok(Ok(found(0, &im("look"))))
    });
    let (c, im) = (clock.clone(), image.clone());
    w.screencapture = Box::new(move |_| {
        c.set(c.get() + 2.0);
        Ok(Some(im("screencapture")))
    });
    let (c, st) = (clock.clone(), streams.clone());
    w.stream = Box::new(move |command, _| {
        st.borrow_mut().push(command.to_vec());
        let (c, im) = (c.clone(), image.clone());
        lazily(move |n| {
            if n < 10 {
                c.set(c.get() + 0.1);
                return Some(Ok(Some(im("stream"))));
            }
            Some(Err(Halt::Stop))
        })
    });
    follow(&args(&["--json"]), &mut w).unwrap();
    let events = out.events();
    let mut kinds = kinds(&events);
    kinds.sort();
    kinds.dedup();
    let seqs: Vec<u64> = events
        .iter()
        .filter(|e| e["kind"] == "state")
        .map(|e| e["seq"].as_u64().unwrap())
        .collect();
    let source = source.borrow();
    let by_stream: Vec<u64> = (1..)
        .zip(source.iter())
        .filter(|(_, by)| **by == "stream")
        .map(|(n, _)| n)
        .collect();
    let streams = streams.borrow();
    assert!(
        streams.len() == 1 && streams[0].contains(&"stream".to_string()),
        "the stream answers again and is started once ({})",
        streams.len()
    );
    assert!(
        by_stream.len() == 10 && by_stream.iter().all(|n| seqs.contains(n)),
        "the ten images of the stream give ten states (seq {by_stream:?})"
    );
    let mut sorted = seqs.clone();
    sorted.sort();
    sorted.dedup();
    assert!(
        source.iter().all(|by| *by == "stream" || *by == "look") && seqs == sorted,
        "no screencapture: every state is the stream's, in order"
    );
    assert!(
        kinds == ["state", "waiting"]
            && whys(&events)
                == [
                    "looking for the row",
                    "the capture stream does not answer (no frame in 3 s)"
                ],
        "before it, `waiting` at the start and once with the stream's failure; then only `state` (got {kinds:?})"
    );
}

// --- tests/strip_start_test.py: `waiting` at once, and the place remembered (#80) ---

#[derive(Clone, Copy)]
enum StreamOf {
    Ten,
    NoRow,
    Fails,
}

struct Start {
    events: Vec<Value>,
    looks: usize,
    streams: Vec<Vec<String>>,
    order: Vec<&'static str>,
}

/// `start_in` as `watch --json --display` would: the displays only, as these checks were written.
fn start(remember: Option<&Path>, stream_of: StreamOf) -> Start {
    start_in(remember, stream_of, &["--json", "--display"])
}

fn start_in(remember: Option<&Path>, stream_of: StreamOf, words: &[&str]) -> Start {
    let (clock, err) = (Rc::new(Cell::new(0.0)), Buf::default());
    let order = Rc::new(RefCell::new(vec![]));
    let out = Buf(Rc::default(), Some(order.clone()));
    let (seq, looks, streams) = (
        Rc::new(Cell::new(0)),
        Rc::new(Cell::new(0)),
        Rc::new(RefCell::new(vec![])),
    );
    let frame = {
        let (clock, seq) = (clock.clone(), seq.clone());
        move |row: bool| {
            seq.set(seq.get() + 1);
            clock.set(clock.get() + 0.1);
            display(seq.get(), row)
        }
    };
    let mut w = world(&clock, &out, &err);
    let o = order.clone();
    w.capture_tool = Box::new(move |_| {
        o.borrow_mut().push("tool");
        Ok(PathBuf::from("tool"))
    });
    let (o, l, f) = (order.clone(), looks.clone(), frame.clone());
    w.locate = Box::new(move |_, _| {
        l.set(l.get() + 1);
        o.borrow_mut().push("look");
        if l.get() > 3 {
            return Err(Halt::Stop);
        }
        Ok(Ok(found(1, &f(true))))
    });
    let (o, st) = (order.clone(), streams.clone());
    w.stream = Box::new(move |command, _| {
        let (o, st, f) = (o.clone(), st.clone(), frame.clone());
        let command = command.to_vec();
        lazily(move |n| {
            if n == 0 {
                st.borrow_mut().push(command.clone());
                o.borrow_mut().push("stream");
            }
            let which = st.borrow().len();
            let (count, row) = match (stream_of, which) {
                (StreamOf::NoRow, 1) => (60, false),
                (StreamOf::Fails, 1) => return Some(Err(Halt::Failed("no frame in 3 s".into()))),
                _ => (10, true),
            };
            Some(if n < count {
                Ok(Some(f(row)))
            } else {
                Err(Halt::Stop)
            })
        })
    });
    let o = order.clone();
    w.screencapture = Box::new(move |_| {
        o.borrow_mut().push("fall-back");
        Err(Halt::Stop)
    });
    let mut a = args(words);
    a.remember = remember.map(Path::to_path_buf);
    follow(&a, &mut w).unwrap();
    let (looks, streams, order) = (
        looks.get(),
        streams.borrow().clone(),
        order.borrow().clone(),
    );
    Start {
        events: out.events(),
        looks,
        streams,
        order,
    }
}

fn folder(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("follow-{name}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn with_the_window_first_a_remembered_display_is_not_taken_at_the_start() {
    // seen 23 Nov 2026: the first start after the install of #316 streamed a remembered display;
    // the start looks instead, the game's window first
    let dir = folder("start-window-first");
    let place = dir.join("place.json");
    fs::write(
        &place,
        r#"{"display": 1, "left": 0, "top": 0, "width": 100, "lines": 4}"#,
    )
    .unwrap();
    let r = start_in(Some(&place), StreamOf::Ten, &["--json"]);
    assert!(
        r.looks == 1,
        "with the window first a remembered display is not taken at the start ({} looks)",
        r.looks
    );
}

#[test]
fn the_start_and_the_remembered_place() {
    let dir = folder("start");
    let place = dir.join("place.json");

    // 1. no remembered place: `waiting` first, then a look, and the place is written
    let r = start(Some(&place), StreamOf::Ten);
    assert!(
        r.events.first() == Some(&json!({"kind": "waiting", "why": "looking for the row"}))
            && r.looks == 1,
        "the first event is `waiting`, with a reason, before any display is looked at"
    );
    assert_eq!(
        r.order[..3],
        ["wait", "tool", "look"],
        "it is written before the capture tool is asked for and before any look"
    );
    assert!(
        kinds(&r.events[1..])
            .iter()
            .filter(|k| *k == "state")
            .count()
            >= 10,
        "the states follow it"
    );
    let written: Value = serde_json::from_str(&fs::read_to_string(&place).unwrap()).unwrap();
    let keys: Vec<&String> = written.as_object().unwrap().keys().collect();
    assert!(
        keys == ["display", "left", "lines", "top", "width"]
            && written.as_object().unwrap().values().all(Value::is_i64)
            && written["display"] == 1,
        "the place that was found is written: five whole numbers ({written})"
    );
    let rectangle: Vec<String> = ["display", "left", "top", "width", "lines"]
        .iter()
        .map(|k| written[k].to_string())
        .collect();
    assert!(
        r.streams.len() == 1 && r.streams[0][1] == "stream" && r.streams[0][2..7] == rectangle,
        "the stream was started on that rectangle"
    );

    // 2. with the remembered place: the stream starts there and no display is looked at
    let r = start(Some(&place), StreamOf::Ten);
    assert!(
        r.looks == 0 && r.streams.len() == 1 && r.streams[0][2..7] == rectangle,
        "with a remembered place no display is looked at ({} looks) and the stream starts on it",
        r.looks
    );
    assert!(
        kinds(&r.events).iter().filter(|k| *k == "state").count() >= 10
            && r.events[0]["kind"] == "waiting",
        "and the states come"
    );

    // 3. the remembered place shows no row: the reader looks again
    let r = start(Some(&place), StreamOf::NoRow);
    assert!(
        r.looks >= 1 && r.streams.len() >= 2 && !r.order.contains(&"fall-back"),
        "a remembered place that shows no row is followed by a look at the displays ({:?})",
        &r.order[..5.min(r.order.len())]
    );

    // 4. the remembered place's stream fails: a look, not the fall-back
    let r = start(Some(&place), StreamOf::Fails);
    assert!(
        r.looks == 1 && !r.order.contains(&"fall-back") && r.streams.len() == 2,
        "a remembered place whose stream fails is followed by a look, not by the fall-back ({:?})",
        &r.order[..5.min(r.order.len())]
    );

    // 4b. a remembered place in the game's window (display -1, since 23 Nov 2026): the stream
    // starts in the window
    fs::write(
        &place,
        r#"{"display": -1, "left": 0, "top": 0, "width": 100, "lines": 4}"#,
    )
    .unwrap();
    let r = start_in(Some(&place), StreamOf::Ten, &["--json"]);
    assert!(
        r.looks == 0 && r.streams.len() == 1 && r.streams[0][1..4] == ["--window", "Wow", "stream"],
        "a remembered place in the window streams the window ({:?})",
        r.streams.first()
    );
    // ... but not with --display: a look
    let r = start(Some(&place), StreamOf::Ten);
    assert!(
        r.looks == 1,
        "with --display a remembered window is not taken ({} looks)",
        r.looks
    );
    // 5. a file that is no place is ignored
    for bad in [
        "",
        "{",
        "[1, 2, 3, 4, 5]",
        r#"{"display": 1}"#,
        r#"{"display": -2, "left": 0, "top": 0, "width": 100, "lines": 4}"#,
        r#"{"display": 1, "left": 0, "top": 0, "width": 0, "lines": 4}"#,
        r#"{"display": 1.5, "left": 0, "top": 0, "width": 100, "lines": 4}"#,
        r#"{"display": 1, "left": 0, "top": 0, "width": 99999999, "lines": 4}"#,
        r#"{"display": 1, "left": 0, "top": 0, "width": 100, "lines": 4, "extra": 6}"#,
        "null",
        r#""text""#,
        "5",
        r#"{"display": true, "left": 0, "top": 0, "width": 100, "lines": 4}"#,
    ] {
        fs::write(&place, bad).unwrap();
        let r = start(Some(&place), StreamOf::Ten);
        assert!(
            r.looks == 1 && r.streams.len() == 1,
            "a file that is no place is ignored, and the reader looks ({bad:?})"
        );
    }

    // 6. without --remember nothing is read or written
    fs::remove_file(&place).unwrap();
    let r = start(None, StreamOf::Ten);
    assert!(
        r.looks == 1 && !place.exists(),
        "without --remember the reader looks, and writes no file"
    );
    fs::remove_dir_all(&dir).unwrap();
}

// --- tests/strip_fallback_test.py and strip_fallback_missing_test.py: the slow fall-back ---

/// `turns` images from the fall-back with `count` displays, the row on display `shown`
/// (counted from 1), gone after `gone_after` captures; display `missing` writes no file.
/// The Watcher's events and the display each capture asked for (None: all of them).
fn fallback(
    count: usize,
    shown: usize,
    turns: usize,
    gone_after: Option<usize>,
    missing: Option<usize>,
) -> (Vec<Value>, Vec<Option<usize>>) {
    let asked = Rc::new(RefCell::new(vec![]));
    let a = asked.clone();
    let mut frames = Screencapture::new(Box::new(move |command: &[String]| {
        assert_eq!(command[0], "screencapture");
        let one = command
            .iter()
            .position(|w| w == "-D")
            .map(|i| command[i + 1].parse::<usize>().unwrap());
        a.borrow_mut().push(one);
        let n = a.borrow().len();
        let paths = command.iter().filter(|w| w.ends_with(".bmp"));
        let numbers: Vec<usize> = one.map_or((1..=count).collect(), |one| vec![one]);
        let there = gone_after.is_none_or(|g| n <= g);
        for (number, path) in numbers.into_iter().zip(paths) {
            if Some(number) != missing {
                fs::write(path, display_bmp(n as u32, number == shown && there)).unwrap();
            }
        }
        Ok(())
    }));
    let (mut watcher, mut events) = (Watcher::default(), vec![]);
    for turn in 0..turns {
        let now = turn as f64 * 0.3;
        events.extend(match frames.turn(&mut |_| {}).unwrap() {
            Some(frame) => watcher.feed(&frame, now),
            None => watcher.idle(now),
        });
    }
    let asked = asked.borrow().clone();
    (events, asked)
}

#[test]
fn the_slow_fall_back_follows_the_display_that_shows_the_row() {
    let (events, asked) = fallback(3, 2, 6, None, None);
    assert_eq!(
        kinds(&events),
        ["state"; 6],
        "the row on the second of three displays: six images give six states, and no 'no row' for the other displays"
    );
    assert!(
        asked[0].is_none() && asked.len() > 1 && asked[1..].iter().all(|a| *a == Some(2)),
        "after the first find only the display that shows the row is captured (asked for {asked:?})"
    );
    let (events, asked) = fallback(3, 3, 6, Some(3), None);
    assert!(
        asked[4..].contains(&None),
        "when the row leaves that display, every display is captured again (asked for {asked:?})"
    );
    assert!(
        kinds(&events).contains(&"relocate".into()),
        "... and the reader is told that the row is gone"
    );
}

#[test]
fn the_slow_fall_back_keeps_a_displays_number() {
    let (events, asked) = fallback(2, 2, 6, None, Some(1));
    assert!(
        kinds(&events) == ["state"; 6]
            && asked == [None, Some(2), Some(2), Some(2), Some(2), Some(2)],
        "no file for display 1, the row on display 2: display 2 is the one captured from then on (asked for {asked:?})"
    );
}

// --- review round 1 of #198: the fall-back's own failures ---

#[test]
fn a_screencapture_that_does_not_end_or_start() {
    let folders = Rc::new(RefCell::new(vec![]));
    let f = folders.clone();
    let mut frames = Screencapture::new(Box::new(move |command: &[String]| {
        let first = PathBuf::from(command.iter().find(|a| a.ends_with(".bmp")).unwrap());
        let folder = first.parent().unwrap().to_path_buf();
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(&folder).unwrap().permissions().mode() & 0o777;
        f.borrow_mut().push((folder, mode));
        fs::write(&first, b"BM\x36").unwrap(); // a file cut short by the limit
        Err(Unrun::Late)
    }));
    let got = frames.turn(&mut |_| {});
    let (folder, mode) = folders.borrow()[0].clone();
    assert!(
        matches!(got, Err(Unrun::Late)) && !folder.exists(),
        "a screencapture that did not end in its limit is reported, and its files are not read but deleted ({got:?})"
    );
    assert_eq!(
        mode, 0o700,
        "the screenshots' folder is its owner's only (0700, as Python's mkdtemp)"
    );
    let mut frames = Screencapture::new(Box::new(|_: &[String]| {
        Err(Unrun::Start(
            "screencapture could not be started: not found".into(),
        ))
    }));
    assert!(
        matches!(frames.turn(&mut |_| {}), Err(Unrun::Start(_))),
        "a screencapture that cannot be started is reported, not taken for an empty screen"
    );
}

#[test]
fn a_turn_of_the_fall_back_that_failed_is_said_and_counted_as_a_miss() {
    let (clock, out, err) = (Rc::new(Cell::new(0.0)), Buf::default(), Buf::default());
    let mut w = world(&clock, &out, &err);
    w.capture_tool = Box::new(|_| Err("no tool".into()));
    w.sleep = sleep_until(&clock, 1.0);
    w.screencapture = Box::new(|_| Err(Halt::Failed("screencapture gave no image in 15 s".into())));
    follow(&args(&["--json"]), &mut w).unwrap();
    assert!(
        err.text().contains("screencapture gave no image in 15 s")
            && whys(&out.events()) == ["looking for the row", "no row on any display"],
        "a turn of the fall-back that failed is said, and counted as a turn with no row"
    );
}

// --- tests/strip_record_test.py, through the command line ---

/// A capture of the row, 2560 x 4, as tests/strip_record_test.py makes one.
fn shot(seq: u32) -> Bitmap {
    bitmap(&capture(4711, 4, LEVELS, &frame(seq), None, WIDE), WIDE)
}

fn lines(path: &Path) -> Vec<Value> {
    fs::read_to_string(path)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02x}")).collect()
}

/// `watch <argv>` with the real look: the capture tool lists one display, 2560 x 4, and its
/// frames are given here: two looks find nothing, then the row.
fn watch_record(argv: &[&str]) {
    let (clock, out, err) = (Rc::new(Cell::new(5.0)), Buf::default(), Buf::default());
    let mut w = world(&clock, &out, &err);
    w.sleep = Box::new(|_| Ok(()));
    let c = clock.clone();
    let mut looks = vec![blank(), blank(), shot(1), shot(1)].into_iter();
    w.locate = Box::new(move |tool, note| {
        let c = c.clone();
        let mut one_frame = |_: &[String]| {
            c.set(c.get() + 0.1);
            Ok(looks.next())
        };
        look(
            tool,
            Colour::Srgb,
            &[(0, WIDE as i64, 4)],
            &mut one_frame,
            note,
        )
        .map_err(Halt::Failed)
    });
    let c = clock.clone();
    w.stream = Box::new(move |_, _| {
        let c = c.clone();
        lazily(move |n| {
            Some(if n < 2 {
                c.set(c.get() + 0.1);
                Ok(Some(shot(2 + n as u32)))
            } else {
                Err(Halt::Stop)
            })
        })
    });
    follow(&args(argv), &mut w).unwrap();
}

/// The bitmap as a 32-bit BMP file, as screencapture writes one.
fn image_bmp(image: &Bitmap) -> Vec<u8> {
    let (w, h) = (image.width, image.height);
    let mut rows = vec![];
    for y in (0..h).rev() {
        for x in 0..w {
            let [r, g, b] = image.rgb(x as f64, y as f64).unwrap();
            rows.extend([b, g, r, 255]);
        }
    }
    let mut out = b"BM".to_vec();
    for v in [54 + rows.len() as u32, 0, 54] {
        out.extend(v.to_le_bytes());
    }
    out.extend(40u32.to_le_bytes());
    out.extend((w as i32).to_le_bytes());
    out.extend((h as i32).to_le_bytes());
    out.extend(1u16.to_le_bytes());
    out.extend(32u16.to_le_bytes());
    for v in [0, rows.len() as u32, 2835, 2835, 0, 0] {
        out.extend(v.to_le_bytes());
    }
    out.extend(rows);
    out
}

#[test]
fn watch_with_a_record() {
    let dir = folder("record");
    let played = dir.join("watch.jsonl");
    watch_record(&["--json", "--record", &played.to_string_lossy()]);
    let got = lines(&played);
    let palette: Vec<Value> = (0..64)
        .map(|i| json!([85 * (i / 16), 85 * (i / 4 % 4), 85 * (i % 4)]))
        .collect();
    let want = [
        json!({"t": 0.0, "why": "no row"}),
        json!({"t": 0.1, "why": "no row"}),
        json!({"t": 0.2, "frame": hex(&frame(1)), "depth": 4, "levels": [76, 100, null, null], "palette": palette}),
        json!({"t": 0.3, "frame": hex(&frame(2))}),
        json!({"t": 0.4, "frame": hex(&frame(3))}),
    ];
    let header: Vec<&String> = got[0].as_object().unwrap().keys().collect();
    assert!(
        got.len() == 6 && header == ["colour", "record", "started"] && got[1..] == want,
        "watch --record FILE writes a header, every capture of the search, then each capture of the stream ({got:?})"
    );
    let before: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    watch_record(&["--json"]);
    let after: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    assert_eq!(before, after, "watch without --record writes no file");

    // the slow fall-back (no capture tool): every display's image is recorded once
    let slow = dir.join("slow.jsonl");
    let (clock, out, err) = (Rc::new(Cell::new(9.0)), Buf::default(), Buf::default());
    let mut w = world(&clock, &out, &err);
    w.capture_tool = Box::new(|_| Err("no swiftc".into()));
    // two displays, then only the one with the row
    let mut shots = vec![vec![blank(), shot(1)], vec![shot(2)]].into_iter();
    let mut frames = Screencapture::new(Box::new(move |command: &[String]| {
        let images = shots.next().unwrap_or_default();
        for (path, image) in command.iter().filter(|a| a.ends_with(".bmp")).zip(images) {
            fs::write(path, image_bmp(&image)).unwrap();
        }
        Ok(())
    }));
    w.screencapture =
        Box::new(move |note| frames.turn(note).map_err(|e| Halt::Fatal(format!("{e:?}"))));
    let c = clock.clone();
    w.sleep = Box::new(move |_| {
        c.set(c.get() + 0.1);
        if c.get() > 9.15 {
            Err(Halt::Stop)
        } else {
            Ok(())
        }
    });
    follow(
        &args(&["--json", "--record", &slow.to_string_lossy()]),
        &mut w,
    )
    .unwrap();
    let got = lines(&slow)[1..].to_vec();
    let keys: Vec<Vec<&String>> = got
        .iter()
        .map(|l| l.as_object().unwrap().keys().collect())
        .collect();
    assert!(
        keys == [
            vec!["t", "why"],
            vec!["depth", "frame", "levels", "palette", "t"],
            vec!["frame", "t"]
        ] && got[0]["why"] == "no row"
            && got[1]["frame"] == hex(&frame(1))
            && got[2]["frame"] == hex(&frame(2)),
        "the slow fall-back records the image of a display without the row, then the one with it, once each ({got:?})"
    );
    fs::remove_dir_all(&dir).unwrap();
}

// --- the flags of step 2c ---

#[test]
fn the_flags_of_step_2c() {
    let given = args(&["--serve", "8765", "--addons", "/tmp/AddOns"]);
    assert_eq!(given.serve, Some(8765));
    assert_eq!(given.addons, Some(PathBuf::from("/tmp/AddOns")));
    for bad in ["x", "-1", "65536"] {
        let got = parse_watch(&["--serve".to_string(), bad.to_string()]);
        assert!(
            got.is_err_and(|e| e.contains("argument --serve")),
            "--serve {bad}: refused before anything is done"
        );
    }
}

// --- docs/specs/232.md, part C: the capture stream in the display's colour space ---

#[test]
fn the_colour_reaches_every_capture_and_the_record() {
    let words = |w: &[&str]| -> Vec<String> { w.iter().map(|s| s.to_string()).collect() };
    let refused = parse_watch(&words(&["--colour", "p3"]));
    assert!(
        refused.is_err_and(|e| e.contains("argument --colour")),
        "--colour p3: refused before anything is done"
    );
    // the look's captures: `--colour display` before the command; sRGB adds nothing, so a
    // tool given with --capture that has no --colour still runs
    for (colour, extra) in [
        (Colour::Srgb, vec![]),
        (Colour::Display, vec!["--colour", "display"]),
    ] {
        let mut commands = vec![];
        let mut one_frame = |c: &[String]| {
            commands.push(c.to_vec());
            Ok(None)
        };
        let _ = look(
            Path::new("tool"),
            colour,
            &[(0, 2560, 4)],
            &mut one_frame,
            &mut |_| {},
        );
        let mut want = vec!["tool"];
        want.extend(&extra);
        want.extend(["stream", "0", "0", "0", "2560", "64", "30", "1"]);
        assert_eq!(
            commands[0],
            words(&want),
            "the look's capture in {colour:?}"
        );
    }
    // the stream's command and the record's header
    for (n, (argv, extra, name)) in [
        (vec![], vec![], "srgb"),
        (
            vec!["--colour", "display"],
            vec!["--colour", "display"],
            "display",
        ),
        (vec!["--colour=srgb"], vec![], "srgb"),
    ]
    .into_iter()
    .enumerate()
    {
        let record = folder(&format!("colour-{n}")).join("record.jsonl");
        let (clock, out, err) = (Rc::new(Cell::new(0.0)), Buf::default(), Buf::default());
        let mut w = world(&clock, &out, &err);
        let image = display(1, true);
        w.locate = Box::new(move |_, _| Ok(Ok(found(1, &image))));
        let streams = Rc::new(RefCell::new(vec![]));
        let s = streams.clone();
        w.stream = Box::new(move |command, _| {
            s.borrow_mut().push(command.to_vec());
            Box::new(NoProcess(std::iter::once(Err(Halt::Stop))))
        });
        let path = record.to_string_lossy().into_owned();
        let mut argv = argv;
        argv.extend(["--json", "--record", &path]);
        follow(&args(&argv), &mut w).unwrap();
        let mut want = extra;
        want.push("stream");
        assert_eq!(
            streams.borrow()[0][1..=want.len()],
            words(&want),
            "{argv:?}: the stream's command"
        );
        assert_eq!(
            lines(&record)[0]["colour"],
            name,
            "{argv:?}: the record's first line names the colour space"
        );
    }
}

// review of #292: the hour of `--colour display` must be the stream's. With no capture tool,
// `watch --colour display` stops with an error; it never takes screenshots in its place.
#[test]
fn colour_display_with_no_stream_stops_and_takes_no_screenshot() {
    let (clock, out, err) = (Rc::new(Cell::new(1000.0)), Buf::default(), Buf::default());
    let mut w = world(&clock, &out, &err);
    w.capture_tool = Box::new(|_| Err("no swiftc".into()));
    let shots = Rc::new(Cell::new(0));
    let s = shots.clone();
    w.screencapture = Box::new(move |_| {
        s.set(s.get() + 1);
        Err(Halt::Stop)
    });
    let got = follow(&args(&["--colour", "display"]), &mut w);
    assert!(
        got.as_ref()
            .is_err_and(|e| e.contains("--colour display") && e.contains("no swiftc")),
        "{got:?}"
    );
    assert_eq!(shots.get(), 0, "no screenshot in place of the stream");
}

// review of #299: a place remembered by a reader of before the lanes is 3 lines high; started on
// it, the stream would miss lanes 3 and 4. The stream takes at least 6 lines.
#[test]
fn a_remembered_place_of_three_lines_streams_six() {
    let dir = folder("remembered-lines");
    let place = dir.join("place.json");
    fs::write(
        &place,
        r#"{"display": 1, "left": 0, "top": 0, "width": 2560, "lines": 3}"#,
    )
    .unwrap();
    let r = start(Some(&place), StreamOf::Ten);
    assert!(
        r.looks == 0 && r.streams.len() == 1 && r.streams[0][6] == "6",
        "the stream starts on the remembered place, 6 lines high: {:?}",
        r.streams
    );
}
