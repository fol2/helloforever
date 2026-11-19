//! The tests that wait on processes or a clock, in one test program so that cargo runs them
//! at the same time (each tests/*.rs is a program of its own, and the programs run one after
//! the other): the capture processes, `watch` with a world the test gives, and the parity of
//! `watch` with the Python one.

#[path = "../common/mod.rs"]
mod common;

mod capture;
mod follow;
mod stream_parity;
