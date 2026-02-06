+++
title = "EBPF"
date = 2025-09-27
[taxonomies]
tags = ["ebpf", "linux"]
+++

## Intro
Recently I have been learning a number of new things, I promise to finish the image and video stuff, I swear! One of the new things I have been learning is something called [ebpf](https://ebpf.io/). It is a very interesting mechanism with which one may add functionality at the kernel-level.

## The Basics
So, why would one need this and how does it work? Well, the answer to the first part of the question is that ultimately, getting changes into the linux kernel take a lot of time... at least several years. When a business needs, say extra tooling or telemetry around monitoring what actions are taken at a syscall level, they can either try to get changes into the kernel and wait, or now, use an expressive interface like ebpf. Ebpf is a virtual machine running in the kernel that can bridge communication to-and-from the kernel and userspace. One may write a modified c-like syntax language to get bytecode that will run within this kernel-level virtual machine.

I can already guess the question or reaction in your mind, "that sounds scary, arbitrary programs running in the kernel?!" and yes, you would be right. The developers of ebpf thought of this predicament though, there is an [ebpf validator](https://docs.kernel.org/bpf/verifier.html) that verifies everything it can to make sure the code is safe to run in the kernel. Though even with this verifier one should make sure the program only does what it needs to!

## Examples
Now that we have spoken about ebpf at a high-level, let's get into some actual code and see what it looks like! The example below, taken from [Aya](https://aya-rs.dev/book/start/hello-xdp/#permit-all), will cover two parts: the actual ebpf program we want to run and then a secondary program that is responsible for loading the program and listening for output. Note the example ebpf program will be shown in both the `rust` and `c` format for the sake of comparison.

The c-format style of an ebpf program, note the use of `SEC` to identify different types of interfaces to have functions interact with; with a full list [here](https://docs.ebpf.io/linux/program-type/)
```c
// A custom header with macros and helper fns for ebpf programs (required)
#include <vmlinux.h>
// Other optional headers depending on program
#include <bpf/bpf_helpers.h>

// Our small xdp program
SEC("xdp")
int xdp_hello(void* ctx) {
    bpf_printk("received a packet");
    return XDP_PASS; // 0
}

char LICENSE[] SEC("license") = "Dual BSD/GPL";
```

This is a simple `Aya` example, that matches the above c-style program, the main difference is a pattern of separating unsafe code from safe code for isolation.
```rust
#![no_std]
#![no_main]

use aya_ebpf::{bindings::xdp_action, macros::xdp, programs::XdpContext};
use aya_log_ebpf::info;

#[xdp]
pub fn xdp_hello(ctx: XdpContext) -> u32 {
    match unsafe { try_xdp_hello(ctx) } {
        Ok(ret) => ret,
        Err(_) => xdp_action::XDP_ABORTED,
    }
}

unsafe fn try_xdp_hello(ctx: XdpContext) -> Result<u32, u32> {
    info!(&ctx, "received a packet");
    Ok(xdp_action::XDP_PASS)
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
```

This is a trimmed down version of what loading an ebpf program looks like, this is also an `Aya` example, but regardless of what programming language you want to use, the flow is the same. Specify the ebpf program you want to load into the kernel, setup any readers for events, then run the ebpf program.
```rust
let mut bpf = aya::Ebpf::load(aya::include_bytes_aligned!(concat!(
    env!("OUT_DIR"),
    "/xdp-hello"
)))?;
match EbpfLogger::init(&mut bpf) {
    Err(e) => {
        // This can happen if you remove all log statements from your eBPF program.
        warn!("failed to initialize eBPF logger: {e}");
    }
    Ok(logger) => {
        let mut logger = tokio::io::unix::AsyncFd::with_interest(
            logger,
            tokio::io::Interest::READABLE,
        )?;
        tokio::task::spawn(async move {
            loop {
                let mut guard = logger.readable_mut().await.unwrap();
                guard.get_inner_mut().flush();
                guard.clear_ready();
            }
        });
    }
}

let program: &mut Xdp = bpf.program_mut("xdp_hello").unwrap().try_into()?;
program.load()?;
program.attach(&opt.iface, XdpFlags::default())
    .context("failed to attach the XDP program with default flags - try changing XdpFlags::default() to XdpFlags::SKB_MODE")?;
}
```

## The End
Hopefully this provided a short summary for ebpf that is insightful and gets more people interested in learning about it :smile:.
