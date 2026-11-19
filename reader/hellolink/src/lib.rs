//! The reader of HelloLink's live-state strip, format 1 (docs/STRIP.md), in Rust.
//! A port of tools/strip1.py and the bitmap parts of tools/hellolink_strip.py.
#![forbid(unsafe_code)]

pub mod bitmap;
pub mod rows;
pub mod strip1;
