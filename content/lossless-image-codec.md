+++
title = "Lossless Image Codec"
date = 2025-08-09
[taxonomies]
tags = ["image", "video", "codec"]
+++

## Intro
Not too long ago I decided to get into learning about image and video codecs. This is a rather ubiquitous area, with everything from streaming on apps like zoom to taking a picture with your phone using this technology. I am going to outline how I learned about this and what I think is additional useful teachings and information.

## Useful Starting Points
Firstly, one of my friends wrote this great [article](https://blog.tempus-ex.com/hello-video-codec/) a while back that covers much of this topic and is a highly recommended read for anyone who might be interested. The important take away is that compression is the fundamental goal for both storage and streaming over the network, with a number of different techniques to do so: [jpg](https://en.wikipedia.org/wiki/Lossless_JPEG), [png](https://en.wikipedia.org/wiki/PNG), [qoi](https://qoiformat.org/), are just to name some of the image formats alone.

Secondly, before getting started, find some good test images to work with! If you can find some images with lots of colors and changes in light that will help detecting issues manually, for example [here](https://www.freepik.com/free-ai-image/vividly-colored-hummingbird-nature_186503803.htm#fromView=search&page=1&position=2&uuid=b0b17c34-8ecf-4a2c-96da-fde30353242a&query=Jpg). You should also make sure as you go through your own codec or exercises that you try at different subsampling levels, here are some of my examples:

<div class="section">
    <h2>Encoded then Decoded (left to right [411, 420, 422, 444])</h2>
    <div class="flex-grid">
        <img src="/imgs/hummingbird_Sample411.jpg", alt="411"/>
        <img src="/imgs/hummingbird_Sample420.jpg", alt="420"/>
        <img src="/imgs/hummingbird_Sample422.jpg", alt="422"/>
        <img src="/imgs/hummingbird_Sample444.jpg", alt="444"/>
    </div>
</div>

## Coding Lossless Implementation
### Encoding
As aforementioned [this](https://blog.tempus-ex.com/hello-video-codec/) has a lot of the starting points that will be repeated here. But let's start with the high level process.

Lossless encoding of images utilize algorithms like [Rice](https://unix4lyfe.org/rice-coding/?ref=blog.tempus-ex.com) to acheive compression, in fact all the other stuff in the code that will be shown are just way to prepare data to go into the Rice encoder! So what does the encoder look like and what does it require?

```rust
pub(crate) fn encode<W>(k: u16, x: i16, stream: &mut BitStreamWriter<W>) -> Result<()>
where
    W: Write,
{
    let x = ((x >> 14) ^ (2 * x)) as u16;
    let high_bits = x >> k;
    stream.write_bits(1, (high_bits + 1) as _)?;
    stream.write_bits((x & ((1 << k) - 1)) as _, k as _)?;

    Ok(())
}
```

Okay, so we have 3 parameters to be concerned with, `k` the amount of bits we want to write, `x` the residual calculated and finally `stream` a sink to write the bits into, and yes, one will require a bit-level writer. The variable needing the most explanation will be `k`, so let's show how we got that next.

```rust
pub(crate) fn k(a: u8, c: u8, b: u8, d: u8) -> u16 {
    let activity =
        (d as i16 - b as i16).abs() + (b as i16 - c as i16).abs() + (c as i16 - a as i16).abs();
    let mut k = 0;
    while 3 << k < activity {
        k += 1;
    }
    k
}
```

This is taken from the article before on lossless encoding. The main idea is to look at adjacent pixels to see how much change there is between them, as less change requires less information.

Now we need to discuss the `x` part and how residuals are made.

```rust
pub(crate) fn sample_prediction(a: u8, c: u8, b: u8) -> i16 {
    if c >= max(a, b) {
        min(a, b) as i16
    } else if c <= min(a, b) {
        max(a, b) as i16
    } else {
        a as i16 + b as i16 - c as i16
    }
}
```

```rust
let prediction = sample_prediction(sample_group.a, sample_group.c, sample_group.b);
let residual = x as i16 - prediction;

encode(
    k(
        sample_group.a,
        sample_group.c,
        sample_group.b,
        sample_group.d,
    ),
    residual,
    stream,
)?;
```

Again we look at adjacent pixels and want to see how far away our 'guess' is from reality and pass that along for encoding. Our 'guess' will usually be pretty close so we shouldn't be needing to encode any big numbers a lot of the time.

So far, there has been some math, and maybe some obscure or slightly confusing pieces being put together, but overall this has hopefully helped cover the parts one hasn't seen before. Now we can put it all together! BTW, we need to perform all these operations for every channel... if one is encoding RGB, that is 3 channels `[r,g,b]` and the code below will take into account however many channels provided.

```rust
fn compress<W>(
    dimensions: PixelDimensions,
    pixels: &[u8],
    depth: usize,
    stride: usize,
    stream: &mut BitStreamWriter<W>,
) -> Result<()>
where
    W: Write,
{
    let PixelDimensions { width, height } = dimensions;
    let mut sample_groups = vec![];
    for _ in 0..depth {
        sample_groups.push(SampleGroup {
            a: 0,
            b: 0,
            c: 0,
            d: 0,
        });
    }

    for row in 0..height {
        for sample_group in sample_groups.iter_mut() {
            sample_group.a = 0;
            sample_group.c = 0;
        }

        for col in 0..(width * depth) {
            let sample_group = &mut sample_groups[col % depth];
            let x = pixels[(row * stride) + col];
            sample_group.d = if row > 0 && (col + depth) < (width * depth) {
                let prev_row = (row - 1) * stride;
                let next_col = col + depth;
                pixels[prev_row + next_col]
            } else {
                0
            };

            let prediction = sample_prediction(sample_group.a, sample_group.c, sample_group.b);
            let residual = x as i16 - prediction;

            encode(
                k(
                    sample_group.a,
                    sample_group.c,
                    sample_group.b,
                    sample_group.d,
                ),
                residual,
                stream,
            )?;

            sample_group.c = sample_group.b;
            sample_group.b = sample_group.d;
            sample_group.a = x;
        }
        for (i, sample_group) in sample_groups.iter_mut().enumerate() {
            sample_group.b = pixels[(row * stride) + i];
        }
    }

    stream.flush()
}
```

The breakdown is pretty straightforward; first we set up the sample groups for all our channels (updating as we loop through pixels), then we just pass the sample information to get our `k`, `x` and start encoding.

### Decoding
Okay, so we have encoded our image and now we want it back... what do we do? We need just do the inverse!

The inverse of our `encode` is this:
```rust
pub(crate) fn decode<R>(k: u16, stream: &mut BitStreamReader<R>) -> Result<i16>
where
    R: Read,
{
    let mut high_bits = 0;
    while stream.read_bits(1)? == 0 {
        high_bits += 1;
    }

    let x = (high_bits << k) | stream.read_bits(k as _)? as u16;
    Ok((x as i16 >> 1) ^ ((x << 15) as i16 >> 15))
}
```

We just read out the high bits and then do some bit math to get the lower bits from the `k` bits read after the high bits. Scariest part here is the bit math.

What now? Well, actually we have already covered everything... As proof, here is the full algorithm:
```rust
fn decompress<R>(
    dimensions: PixelDimensions,
    pixels: &mut [u8],
    depth: usize,
    stride: usize,
    stream: &mut BitStreamReader<R>,
) -> Result<()>
where
    R: Read,
{
    let PixelDimensions { width, height } = dimensions;
    let mut sample_groups = vec![];
    for _ in 0..depth {
        sample_groups.push(SampleGroup {
            a: 0,
            b: 0,
            c: 0,
            d: 0,
        });
    }

    for row in 0..height {
        for sample_group in sample_groups.iter_mut() {
            sample_group.a = 0;
            sample_group.c = 0;
        }

        for col in 0..(width * depth) {
            let sample_group = &mut sample_groups[col % depth];
            sample_group.d = if row > 0 && (col + depth) < (width * depth) {
                let prev_row = (row - 1) * stride;
                let next_col = col + depth;
                pixels[prev_row + next_col]
            } else {
                0
            };

            let prediction = sample_prediction(sample_group.a, sample_group.c, sample_group.b);
            let residual = decode(
                k(
                    sample_group.a,
                    sample_group.c,
                    sample_group.b,
                    sample_group.d,
                ),
                stream,
            )?;
            let x = (prediction + residual) as u8;
            pixels[(row * stride) + (col)] = x;

            sample_group.c = sample_group.b;
            sample_group.b = sample_group.d;
            sample_group.a = x;
        }
        for (i, sample_group) in sample_groups.iter_mut().enumerate() {
            sample_group.b = pixels[row * stride + i];
        }
    }

    Ok(())
}
```

I will even be super nice and show a test for copying to verify personall. :)

```rust
#[test]
fn encode_decode_jpeg() {
    let image = image::open("./test_imgs/input/rgb8/hummingbird.jpg").expect("open img");
    let dimensions = image.dimensions().into();
    match image.color() {
        image::ColorType::Rgb8 => {
            let image = image.as_rgb8().unwrap().clone();

            let size = image.len();
            let data = image.to_vec();
            let img = ImageRgb8::new(dimensions, Rgb8::new(data));

            let codec = Jpg;
            let mut writer = BitStreamWriter::new(VecDeque::with_capacity(size));
            codec
                .compress(&img.borrow(), &mut writer)
                .expect("compress");

            let inner = writer.into_inner();

            assert!(
                inner.len() < size,
                "compressed size should be less than original size"
            );

            let mut reader = BitStreamReader::new(inner);

            let mut decoded = ImageRgb8::new(dimensions, Rgb8::new(vec![0; size]));
            codec
                .decompress(&mut decoded, &mut reader)
                .expect("decompress");

            assert_eq!(img.pixels().as_slice(), decoded.pixels().as_slice());

            assert_eq!(decoded.borrow(), img.borrow());
        }
        _ => panic!("unsupported color type"),
    }
}
```

Lossless encoding is a very different story and will be a separate [post](@/lossy-image-codec.md).
