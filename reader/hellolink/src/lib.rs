//! The reader of HelloLink's live-state strip, format 1 (docs/STRIP.md), in Rust.
//! A port of tools/strip1.py and the bitmap parts of tools/hellolink_strip.py.
#![forbid(unsafe_code)]

pub mod api;
pub mod assistant;
pub mod bitmap;
pub mod built_from;
pub mod capture;
pub mod depth;
pub mod follow;
pub mod install;
pub mod package;
pub mod record;
pub mod replay;
pub mod rows;
pub mod slots;
pub mod strip1;
pub mod strip2;
pub mod watch;
