+++
title = "Lossy Image Codec"
date = 2025-08-10
[taxonomies]
tags = ["image", "video", "codec"]
+++

## Intro
This is the follow-up to the previous [post](@/lossless-image-codec.md). In this post we will explore what it takes to get lossy (meaning data loss) encoding and decoding to work. Let's get started!

## Prerequisites
I know I just said let's get started... but, let's go through a few things before do that. The first is that there is going to be some math, I will be linking articles and references to these. Also this article is going to be longer than the previous so be prepared for a read.

As for the math part, we need to discuss DCT, or discrete cosine transforms. These are really similar to fourier transforms (sine-based) and if you have ever explored those before then this will be a breeze. If not, here is a really good introduction to [DCT](https://youtu.be/0me3guauqOU?t=592) called `The Unreasonable Effectiveness of JPEG: A Signal Processing Approach` on the channel `Reducible`. The breakdown is this: cosine waves have some neat properties when it comes to scaling waves, overlapping waves, and sampling waves. Which is just a fancy way of saying that given functions of say `cos(x)` and `cos(y)` one can get `cos(z)` as the final waveform and also get back `cos(x)` and `cos(y)` later. Which to the keen observer doesn't sound 'lossy'; which is because it isn't, the DCT is reversible completely and is not where the lossy-ness comes in, but we will explore that later. Through treating channels of data, like RGB, as a set of points that represent a wave function we can combine and breakdown these channels into forms that are compressible.

We also need to cover a new format: [Ycbcr](https://en.wikipedia.org/wiki/YCbCr). This is a mathematical space of color representation that will allow us to separate data into luminance, or how bright things are, and chrominance, or how much color there is somewhere. This is really important because humans see light differences much better than color differences. In fact, we will be able to throw away most of the color values and keep all the light values and there is no discernable difference. Here are the same hummingbirds I mentioned in the previous [post](@/lossless-image-codec.md) for a reminder on this:

<div class="section">
    <h2>Encoded then Decoded (left to right [411, 420, 422, 444])</h2>
    <div class="flex-grid">
        <img src="/imgs/hummingbird_Sample411.jpg", alt="411"/>
        <img src="/imgs/hummingbird_Sample420.jpg", alt="420"/>
        <img src="/imgs/hummingbird_Sample422.jpg", alt="422"/>
        <img src="/imgs/hummingbird_Sample444.jpg", alt="444"/>
    </div>
</div>

## Coding Lossy Implementation
### Encoding
The encoding process is relatively similar to before, though there are some big differences. First we need all our data to be in Ycbcr and not in RGB.

```rust
// https://en.wikipedia.org/wiki/YCbCr
// BT.2020 luma coefficients (Rec. ITU-R BT.2020)
pub mod bt2020 {
    pub const KR: f64 = 0.2627; // Red coefficient
    pub const KG: f64 = 0.6780; // Green coefficient
    pub const KB: f64 = 0.0593; // Blue coefficient

    // Derived coefficients for Cb (Blue-Yellow chroma)
    pub const CB_R: f64 = -KR / (2.0 * (1.0 - KB)); // -0.2215
    pub const CB_G: f64 = -KG / (2.0 * (1.0 - KB)); // -0.3607
    pub const CB_B: f64 = 0.5; // 0.5000

    // Derived coefficients for Cr (Red-Cyan chroma)
    pub const CR_R: f64 = 0.5; // 0.5000
    pub const CR_G: f64 = -KG / (2.0 * (1.0 - KR)); // -0.4598
    pub const CR_B: f64 = -KB / (2.0 * (1.0 - KR)); // -0.0402

    // Inverse transformation coefficients (for YCbCr to RGB)
    pub const Y_TO_R_CR: f64 = 2.0 * (1.0 - KR); // 1.4746
    pub const Y_TO_G_CB: f64 = -2.0 * KB * (1.0 - KB) / KG; // -0.1645
    pub const Y_TO_G_CR: f64 = -2.0 * KR * (1.0 - KR) / KG; // -0.5713
    pub const Y_TO_B_CB: f64 = 2.0 * (1.0 - KB); // 1.8814
}

pub(crate) fn rgba_to_ycbcr<T>(rgba: &Rgba<T>) -> Ycbcr
where
    T: Copy + Bounded + NumCast + Unsigned,
{
    let Rgba { r, g, b, a } = rgba;
    let r = r.to_f64().expect("f64");
    let g = g.to_f64().expect("f64");
    let b = b.to_f64().expect("f64");
    let a = a.to_f64().expect("f64");

    let center = (T::max_value().to_f64().expect("f64") + 1.0) / 2f64;

    let y = bt2020::KR * r + bt2020::KG * g + bt2020::KB * b;
    let cb = center + bt2020::CB_R * r + bt2020::CB_G * g + bt2020::CB_B * b;
    let cr = center + bt2020::CR_R * r + bt2020::CR_G * g + bt2020::CR_B * b;

    Ycbcr { y, cb, cr, a }
}

pub(crate) fn ycbcr_to_rgba<T>(ycbcr: &Ycbcr) -> Rgba<T>
where
    T: Bounded + FromPrimitive + ToPrimitive,
{
    let Ycbcr { y, cb, cr, a } = ycbcr;
    let center = (T::max_value().to_f64().expect("f64") + 1.0) / 2f64;

    let cb = cb - center;
    let cr = cr - center;

    let r = y + bt2020::Y_TO_R_CR * cr;
    let g = y + bt2020::Y_TO_G_CB * cb + bt2020::Y_TO_G_CR * cr;
    let b = y + bt2020::Y_TO_B_CB * cb;

    Rgba {
        r: clamp(r),
        g: clamp(g),
        b: clamp(b),
        a: clamp(*a),
    }
}
```

This looks really scary but the values are all constants that other people have already worked out for mapping RGB into the Ycbcr color-space and back. The alpha value isn't used in any of these examples and I might remove it in my own code later, it is a common struct I use elsewhere. So just ignore all the alpha mentions in these code snippets.

Now that we are working in the correct color-space it is time to start saving space. The first place is with [subsampling](https://en.wikipedia.org/wiki/Chroma_subsampling). This is where we just throw away some color information and go with degraded accuracy. For a lot of cases one can probably go with 420 or 411 and just throw away about half of all the color information with no noticeable difference from the original image.

```rust
pub(crate) fn subsample_ycbcr(
    dimensions: PixelDimensions,
    ycbcr: &[Ycbcr],
    subsampling: Subsampling,
) -> SubSampleGroup<f64> {
    let y = ycbcr
        .iter()
        .copied()
        .map(|Ycbcr { y, .. }| y)
        .collect::<Vec<_>>();
    let cb = ycbcr
        .iter()
        .copied()
        .map(|Ycbcr { cb, .. }| cb)
        .collect::<Vec<_>>();
    let cr = ycbcr
        .iter()
        .copied()
        .map(|Ycbcr { cr, .. }| cr)
        .collect::<Vec<_>>();

    match subsampling {
        // 420:
        // - half horizontal
        // - half vertical
        Subsampling::Sample420 => {
            let mut sampled_cb = vec![];
            let mut sampled_cr = vec![];
            let PixelDimensions { width, height } = dimensions;

            for r in (0..height).step_by(2) {
                for c in (0..width).step_by(2) {
                    let idx1 = sample_idx((r, c), width).expect("within width");
                    let idx2 = sample_idx((r, c + 1), width).unwrap_or(idx1);
                    let idx3 = sample_idx((r + 1, c), width).unwrap_or(idx1);
                    let idx4 = sample_idx((r + 1, c + 1), width).unwrap_or(idx1);

                    if idx1 < cb.len() && idx2 < cb.len() && idx3 < cb.len() && idx4 < cb.len() {
                        sampled_cb.push((cb[idx1] + cb[idx2] + cb[idx3] + cb[idx4]) / 4.0);
                        sampled_cr.push((cr[idx1] + cr[idx2] + cr[idx3] + cr[idx4]) / 4.0);
                    }
                }
            }

            SubSampleGroup {
                dimensions,
                y,
                cb: sampled_cb,
                cr: sampled_cr,
            }
        }
        // 411:
        // - quarter horizontal
        // - full vertical
        Subsampling::Sample411 => {
            let PixelDimensions { width, height } = dimensions;
            let mut sampled_cb = vec![];
            let mut sampled_cr = vec![];

            for r in 0..height {
                for c in (0..width).step_by(4) {
                    let idx1 = sample_idx((r, c), width).expect("within width");
                    let idx2 = sample_idx((r, c + 1), width).unwrap_or(idx1);
                    let idx3 = sample_idx((r, c + 2), width).unwrap_or(idx1);
                    let idx4 = sample_idx((r, c + 3), width).unwrap_or(idx1);

                    if idx1 < cb.len() && idx2 < cb.len() && idx3 < cb.len() && idx4 < cb.len() {
                        sampled_cb.push((cb[idx1] + cb[idx2] + cb[idx3] + cb[idx4]) / 4.0);
                        sampled_cr.push((cr[idx1] + cr[idx2] + cr[idx3] + cr[idx4]) / 4.0);
                    }
                }
            }

            SubSampleGroup {
                dimensions,
                y,
                cb: sampled_cb,
                cr: sampled_cr,
            }
        }
        // 422:
        // - half horizontal
        // - full vertical
        Subsampling::Sample422 => {
            let PixelDimensions { width, height } = dimensions;

            let mut sampled_cb = vec![];
            let mut sampled_cr = vec![];

            for r in 0..height {
                for c in (0..width).step_by(2) {
                    let idx1 = sample_idx((r, c), width).expect("within width");
                    let idx2 = sample_idx((r, c + 1), width).unwrap_or(idx1);

                    if idx1 < cb.len() && idx2 < cb.len() {
                        sampled_cb.push((cb[idx1] + cb[idx2]) / 2.0);
                        sampled_cr.push((cr[idx1] + cr[idx2]) / 2.0);
                    }
                }
            }

            SubSampleGroup {
                dimensions,
                y,
                cb: sampled_cb,
                cr: sampled_cr,
            }
        }
        // 444:
        // - full horizontal
        // - full vertical
        Subsampling::Sample444 => SubSampleGroup {
            dimensions,
            y,
            cb,
            cr,
        },
    }
}
```

At this point we have the data we are concerned with, but it still isn't in a form we can pass to a DCT... We must first convert our channels into blocks which could look like this:

```rust
const BLOCK_COLS: usize = 8;
const BLOCK_ROWS: usize = 8;

pub struct Block<T>(pub [[T; BLOCK_COLS]; BLOCK_ROWS]);
```

Be aware the implementation either needs to convert between signed integers and floats and then back again or one has to accept a modified DCT implementation that works on integers and not floats. If you go with an integer version then be careful, one will need to scale numbers to add back precision.

With our `Block` type we can now convert our flat array into a set of blocks to encode. Our array of bytes will represent some dimensions, maybe 3333 x 5000, or some other ratio. Our blocks need to represent a reduction of 8 times in both dimensions.

```rust
let mut y_blocks = vec![];
for r in (0..height).step_by(Block::<f64>::rows()) {
    for c in (0..width).step_by(Block::<f64>::cols()) {
        y_blocks.push(build_block(&y, r, c, width));
    }
}
```

where blocks are built with

```rust
#[inline]
pub(crate) fn build_block<T>(pixels: &[T], x: usize, y: usize, width: usize) -> Block<T>
where
    T: Copy + Default,
{
    let x_start = x;
    let x_end = x_start + Block::<T>::rows();
    let y_start = y;
    let y_end = y_start + Block::<T>::cols();

    let mut block = Block::<T>::default();
    for x in x_start..x_end {
        for y in y_start..y_end {
            let r = x - x_start;
            let c = y - y_start;
            let pixel_index = x * width + y;
            if pixel_index < pixels.len() {
                block[r][c] = pixels[pixel_index];
            }
        }
    }

    block
}
```

The next step is performing the DCT and quantization. The second part we haven't discussed before, but it is pretty straightforward. We can use a simple quantization matrix to reduce the precision of the coefficients. By this, what is meant is that we will remove (or reduce to 0) all coefficients in our matrix/block that are less important to the overall image.

```rust
let lumi_quantizor = Quantizor::<Q>::luminance();
let y_dct = y
    .iter()
    .flat_map(|y| {
        lumi_quantizor
            .quantize(y.dct().convert_to())
            .zigzag()
            .iter()
            .collect::<Vec<_>>()
    })
    .collect::<Vec<_>>();
```

I found [this](https://unix4lyfe.org/dct-1d/) for describing a fast DCT implementation which will be put in full below, the goal with these fast versions is to lower the amount of addition and multiplication operations as much as possible. There seem to be two good fast options out there, Loeffler, Ligtenberg, and Moschytz algorithm and Arai, Agui and Nakajima algorithm. Both seem to work well and both are equally inscrutable at first glance so pick your poison for implementation. I did the first one because I saw it first. FYI I do not claim to own this implementation at all and I couldn't find any license information for it.

#### FULL DCT & IDCT
```rust
// https://en.wikipedia.org/wiki/Discrete_cosine_transform
impl Block<f64> {
    pub fn dct(self) -> Self {
        let mut next = self.0;

        // horizontal
        for r in &mut next {
            *r = dct1_fast(*r);
        }
        // vertical
        for c in 0..8 {
            let line = [
                next[0][c], next[1][c], next[2][c], next[3][c], next[4][c], next[5][c], next[6][c],
                next[7][c],
            ];
            let col = dct1_fast(line);
            next[0][c] = col[0];
            next[1][c] = col[1];
            next[2][c] = col[2];
            next[3][c] = col[3];
            next[4][c] = col[4];
            next[5][c] = col[5];
            next[6][c] = col[6];
            next[7][c] = col[7];
        }

        Self(next)
    }

    pub fn idct(self) -> Self {
        let mut next = self.0;

        // horizontal
        for r in next.iter_mut().take(Block::<f64>::rows()) {
            *r = idct1_fast(*r);
        }
        // vertical
        for c in 0..Block::<f64>::cols() {
            let line = [
                next[0][c], next[1][c], next[2][c], next[3][c], next[4][c], next[5][c], next[6][c],
                next[7][c],
            ];
            let col = idct1_fast(line);
            next[0][c] = col[0];
            next[1][c] = col[1];
            next[2][c] = col[2];
            next[3][c] = col[3];
            next[4][c] = col[4];
            next[5][c] = col[5];
            next[6][c] = col[6];
            next[7][c] = col[7];
        }

        Self(next)
    }
}

// 8.sqrt()
const SQRT_8: f64 = 2.8284271247461903;
const LLM_C1_COSINE: f64 = 0.9807852804032304;
const LLM_C1_SINE: f64 = 0.19509032201612825;
const LLM_C3_COSINE: f64 = 0.8314696123025452;
const LLM_C3_SINE: f64 = 0.5555702330196022;
const LLM_C6_COSINE: f64 = 0.38268343236508984;
const LLM_C6_SINE: f64 = 0.9238795325112867;

/// REF:
/// https://unix4lyfe.org/dct-1d/
/// See LLM section
#[inline]
fn dct1_fast(line: [f64; 8]) -> [f64; 8] {
    let s1 = dct1_fast_stage1(line);
    let s2 = dct1_fast_stage2(s1);
    let s3 = dct1_fast_stage3(s2);
    let s4 = dct1_fast_stage4(s3);
    dct1_fast_shuffle(s4)
}

#[inline]
fn dct1_fast_stage1(line: [f64; 8]) -> [f64; 8] {
    let c0 = line[0] + line[7];
    let c1 = line[1] + line[6];
    let c2 = line[2] + line[5];
    let c3 = line[3] + line[4];
    let c4 = -line[4] + line[3];
    let c5 = -line[5] + line[2];
    let c6 = -line[6] + line[1];
    let c7 = -line[7] + line[0];
    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn dct1_fast_stage2(line: [f64; 8]) -> [f64; 8] {
    let c0 = line[0] + line[3];
    let c1 = line[1] + line[2];
    let c2 = -line[2] + line[1];
    let c3 = -line[3] + line[0];

    // c4 and c7 are pairs
    let c4 = twist1(line[4], line[7], LLM_C3_COSINE, LLM_C3_SINE, 1.0);
    let c7 = twist2(line[4], line[7], LLM_C3_COSINE, LLM_C3_SINE, 1.0);
    // c5 and c6 are pairs
    let c5 = twist1(line[5], line[6], LLM_C1_COSINE, LLM_C1_SINE, 1.0);
    let c6 = twist2(line[5], line[6], LLM_C1_COSINE, LLM_C1_SINE, 1.0);
    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn dct1_fast_stage3(line: [f64; 8]) -> [f64; 8] {
    let c0 = line[0] + line[1];
    let c1 = -line[1] + line[0];
    let c2 = twist1(line[2], line[3], LLM_C6_COSINE, LLM_C6_SINE, SQRT_2);
    let c3 = twist2(line[2], line[3], LLM_C6_COSINE, LLM_C6_SINE, SQRT_2);
    let c4 = line[4] + line[6];
    let c5 = -line[5] + line[7];
    let c6 = -line[6] + line[4];
    let c7 = line[7] + line[5];
    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn dct1_fast_stage4(line: [f64; 8]) -> [f64; 8] {
    let c0 = line[0];
    let c1 = line[1];
    let c2 = line[2];
    let c3 = line[3];
    let c4 = -line[4] + line[7];
    let c5 = line[5] * SQRT_2;
    let c6 = line[6] * SQRT_2;
    let c7 = line[7] + line[4];

    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn dct1_fast_shuffle(line: [f64; 8]) -> [f64; 8] {
    [
        line[0] / SQRT_8, // 0
        line[7] / SQRT_8, // 1
        line[2] / SQRT_8, // 2
        line[5] / SQRT_8, // 3
        line[1] / SQRT_8, // 4
        line[6] / SQRT_8, // 5
        line[3] / SQRT_8, // 6
        line[4] / SQRT_8, // 7
    ]
}

#[inline]
fn twist1(x: f64, y: f64, c: f64, s: f64, scale: f64) -> f64 {
    scale * ((x * c) + (y * s))
}

#[inline]
fn twist2(x: f64, y: f64, c: f64, s: f64, scale: f64) -> f64 {
    scale * ((-x * s) + (y * c))
}

/// This is just the reverse of `dct1_fast`
fn idct1_fast(line: [f64; 8]) -> [f64; 8] {
    let s0 = idct1_fast_unshuffle(line);
    let s1 = idct1_fast_stage1(s0);
    let s2 = idct1_fast_stage2(s1);
    let s3 = idct1_fast_stage3(s2);
    idct1_fast_stage4(s3)
}

#[inline]
fn idct1_fast_unshuffle(line: [f64; 8]) -> [f64; 8] {
    [
        line[0] * SQRT_8,
        line[4] * SQRT_8,
        line[2] * SQRT_8,
        line[6] * SQRT_8,
        line[7] * SQRT_8,
        line[3] * SQRT_8,
        line[5] * SQRT_8,
        line[1] * SQRT_8,
    ]
}

#[inline]
fn idct1_fast_stage1(line: [f64; 8]) -> [f64; 8] {
    let c0 = line[0];
    let c1 = line[1];
    let c2 = line[2];
    let c3 = line[3];
    let c4 = (line[7] - line[4]) / 2.0;
    let c5 = line[5] / SQRT_2;
    let c6 = line[6] / SQRT_2;
    let c7 = (line[7] + line[4]) / 2.0;

    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn idct1_fast_stage2(line: [f64; 8]) -> [f64; 8] {
    let c0 = (line[0] + line[1]) / 2.0;
    let c1 = (-line[1] + line[0]) / 2.0;
    let c2 = untwist1(line[2], line[3], LLM_C6_COSINE, LLM_C6_SINE, SQRT_2);
    let c3 = untwist2(line[2], line[3], LLM_C6_COSINE, LLM_C6_SINE, SQRT_2);
    let c4 = (line[4] + line[6]) / 2.0;
    let c5 = (line[7] - line[5]) / 2.0;
    let c6 = (line[4] - line[6]) / 2.0;
    let c7 = (line[7] + line[5]) / 2.0;

    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn idct1_fast_stage3(line: [f64; 8]) -> [f64; 8] {
    let c0 = (line[0] + line[3]) / 2.0;
    let c1 = (line[1] + line[2]) / 2.0;
    let c2 = (line[1] - line[2]) / 2.0;
    let c3 = (line[0] - line[3]) / 2.0;

    // c4 and c7 are pairs
    let c4 = untwist1(line[4], line[7], LLM_C3_COSINE, LLM_C3_SINE, 1.0);
    let c7 = untwist2(line[4], line[7], LLM_C3_COSINE, LLM_C3_SINE, 1.0);
    // c5 and c6 are pairs
    let c5 = untwist1(line[5], line[6], LLM_C1_COSINE, LLM_C1_SINE, 1.0);
    let c6 = untwist2(line[5], line[6], LLM_C1_COSINE, LLM_C1_SINE, 1.0);

    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn idct1_fast_stage4(line: [f64; 8]) -> [f64; 8] {
    let c0 = (line[0] + line[7]) / 2.0;
    let c1 = (line[1] + line[6]) / 2.0;
    let c2 = (line[2] + line[5]) / 2.0;
    let c3 = (line[3] + line[4]) / 2.0;
    let c4 = (line[3] - line[4]) / 2.0;
    let c5 = (line[2] - line[5]) / 2.0;
    let c6 = (line[1] - line[6]) / 2.0;
    let c7 = (line[0] - line[7]) / 2.0;

    [c0, c1, c2, c3, c4, c5, c6, c7]
}

#[inline]
fn untwist1(x: f64, y: f64, c: f64, s: f64, scale: f64) -> f64 {
    // x and y are the results of a twist 1 or 2
    // x = (a * c) + (b * s)
    // y = (-a * s) + (b * c)
    // ->
    // x / s = (a * c / s) + b
    // y / c = (-a * s / c) + b
    // ->
    // (x / s) - (y / c) = (a * c / s) + (a * s / c)
    // ... = a * ((c / s) + (s / c))
    let x = x / (s * scale);
    let y = y / (c * scale);
    (x - y) / ((s / c) + (c / s))
}

#[inline]
fn untwist2(x: f64, y: f64, c: f64, s: f64, scale: f64) -> f64 {
    // same as `untwist1` but solve for b
    let x = x / (c * scale);
    let y = y / (s * scale);
    (x + y) / ((s / c) + (c / s))
}
```

Whew, we made it! We are past the hard part and can now finish the rest of the algorithm which is just quantization and zigzag before huffman encoding.

Quantization is where some of the magic happens, one needs to create a matrix/block of values that are "good enough" at reducing coefficient terms that resulted from DCT transformation. Best advice, find some example somewhere and start with that. I will share one of mine, but I am not confident in how good/bad it is really, only that it does a decent enough job. Anyways, find a good matrix and then for each entry in your DCT divide it by the corresponding entry in the matrix you found.

```rust
#[rustfmt::skip]
pub(super) const LUMINANCE_QUANTIZATION:  Block<i32> = Block([
    [16, 12, 14, 14, 18, 24, 49, 72],
    [11, 12, 13, 17, 22, 35, 64, 92],
    [10, 14, 16, 22, 37, 55, 78, 95],
    [16, 19, 24, 29, 56, 64, 87, 98],
    [24, 26, 40, 51, 68, 81, 103, 112],
    [40, 58, 57, 87, 109, 104, 121, 100],
    [51, 60, 69, 80, 103, 113, 120, 103],
    [61, 55, 56, 62, 77, 92, 101, 99],
]);

/// In a `Quantization` type to wrap different blocks for quantization.
pub(crate) fn quantize(&self, mut block: Block<T>) -> Block<T> {
    for r in 0..Block::<T>::rows() {
        for c in 0..Block::<T>::cols() {
            block.0[r][c] /= self.0[r][c];
        }
    }
    block
}
```

Lastly we zigzag to make [huffman encoding](https://en.wikipedia.org/wiki/Huffman_coding) better at producing smaller bit streams and write each one of our channels we transformed.

### Decoding
Decoding will just be the exact reverse process as encoding. I will include a full decode method I am using and how I go about reconstructing the image.

```rust
fn decompress_from_stream<const N: usize, Q, R, T>(
    &self,
    dimensions: PixelDimensions,
    stream: &mut BitStreamReader<R>,
) -> Result<Vec<T>>
where
    Q: Copy
        + Default
        + DivAssign
        + MulAssign
        + Hash
        + NumCast
        + PrimInt
        + ToBytes<Bytes = [u8; N]>
        + FromBytes<Bytes = [u8; N]>,
    R: Read,
    T: Bounded + FromPrimitive + ToPrimitive,
{
    let lumi_quantizor = Quantizor::<Q>::luminance();
    let chroma_quantizor = Quantizor::<Q>::chrominance();

    let y_dct = {
        let mut decoder = Decoder::new(stream);
        decoder.decode()?
    };

    let cb_dct = {
        let mut decoder = Decoder::new(stream);
        decoder.decode()?
    };

    let cr_dct = {
        let mut decoder = Decoder::new(stream);
        decoder.decode()?
    };

    let y = y_dct
        .chunks(Block::<Q>::size())
        .map(|chunk| {
            lumi_quantizor
                .dequantize(Block::<Q>::from(chunk).zagzig())
                .convert_to::<f64>()
                .idct()
        })
        .collect::<Vec<_>>();

    let cb = cb_dct
        .chunks(Block::<Q>::size())
        .map(|chunk| {
            chroma_quantizor
                .dequantize(Block::<Q>::from(chunk).zagzig())
                .convert_to::<f64>()
                .idct()
        })
        .collect::<Vec<_>>();

    let cr = cr_dct
        .chunks(Block::<Q>::size())
        .map(|chunk| {
            chroma_quantizor
                .dequantize(Block::<Q>::from(chunk).zagzig())
                .convert_to::<f64>()
                .idct()
        })
        .collect::<Vec<_>>();

    // Reconstruct image from pixel data
    Ok(reconstruct_pixels(
        dimensions,
        &y,
        &cb,
        &cr,
        None,
        self.subsampling,
    ))
}


#[inline]
pub(crate) fn reconstruct_pixels<T>(
    dimensions: PixelDimensions,
    y_blocks: &[Block<f64>],
    cb_blocks: &[Block<f64>],
    cr_blocks: &[Block<f64>],
    _a_blocks: Option<&[Block<f64>]>,
    subsampling: Subsampling,
) -> Vec<T>
where
    T: Bounded + FromPrimitive + ToPrimitive,
{
    let PixelDimensions { width, height } = dimensions;
    let mut ys = vec![0.0; height * width];
    let mut _alphas = vec![0.0; height * width];

    let (chroma_width, chroma_height) =
        calculate_subsampled_dimensions(dimensions.into(), subsampling);

    // Initialize chroma arrays with subsampled dimensions
    let mut cbs = vec![0.0; chroma_height * chroma_width];
    let mut crs = vec![0.0; chroma_height * chroma_width];

    {
        let mut i = 0;
        for r in (0..height).step_by(Block::<T>::rows()) {
            for c in (0..width).step_by(Block::<T>::cols()) {
                if i < y_blocks.len() {
                    let y_block = &y_blocks[i];

                    break_block(&mut ys, y_block, r, c, width);

                    i += 1;
                }
            }
        }
    }

    {
        let mut i = 0;
        for r in (0..chroma_height).step_by(Block::<T>::rows()) {
            for c in (0..chroma_width).step_by(Block::<T>::cols()) {
                if i < cb_blocks.len() {
                    let cb_block = &cb_blocks[i];

                    break_block(&mut cbs, cb_block, r, c, chroma_width);

                    i += 1;
                }
            }
        }
    }

    {
        let mut i = 0;
        for r in (0..chroma_height).step_by(Block::<T>::rows()) {
            for c in (0..chroma_width).step_by(Block::<T>::cols()) {
                if i < cr_blocks.len() {
                    let cr_block = &cr_blocks[i];

                    break_block(&mut crs, cr_block, r, c, chroma_width);

                    i += 1;
                }
            }
        }
    }

    let UpSampleGroup {
        dimensions: _,
        y,
        cb,
        cr,
    } = upsample_ycbcr(dimensions, ys, cbs, crs, subsampling);

    y.iter()
        .zip(cb.iter())
        .zip(cr.iter())
        .map(|((y, cb), cr)| {
            ycbcr_to_rgba(&Ycbcr {
                y: *y,
                cb: *cb,
                cr: *cr,
                a: 0.0,
            })
        })
        .flat_map(|Rgba { r, g, b, a: _ }| {
            [
                r, g, b,
                // T::from_f64(a),
            ]
        })
        .collect::<Vec<_>>()
}

#[inline]
pub(crate) fn break_block<T>(
    channel: &mut [T],
    block: &Block<f64>,
    row: usize,
    col: usize,
    width: usize,
) where
    T: Bounded + FromPrimitive + ToPrimitive,
{
    let row_start = row;
    let row_end = row_start + Block::<f64>::rows();
    let col_start = col;
    let col_end = col_start + Block::<f64>::cols();

    for x in row_start..row_end {
        for y in col_start..col_end {
            let r = x - row_start;
            let c = y - col_start;
            let pixel_index = x * width + y;

            if pixel_index < channel.len() {
                channel[pixel_index] = clamp(block[r][c]);
            }
        }
    }
}
```

There is a lot of code shared here, but it should all look familiar to what we already covered. The only thing at the end is making sure one deconstructs blocks correctly by placing pixels in the correct *subsampled* dimensions and then upsampling back. Once that is done you should have a recovered image!
