+++
title = "Video Compression"
date = 2025-10-27
[taxonomies]
tags = ["video", "codec"]
+++

## Intro
This is the (probably) final article in my compression series, which has been a fun deep dive into a part of a lot people's lives that isn't thought about, as this technology is used for almost all videos you have ever watched. Previous articles were about lossless and lossy image compression and this article assumes readers have read them and are familiar with the concepts discussed. This time, I will cover video compression. I want to highlight that video compression has a number of algorithms out there like H.264, H.265, VP9, AV1, etc. This doesn't cover any specific algorithm but rather the concepts and learnings that are common across most video compression techniques. I also won't be putting lengthy code blocks this time around as it will be just too much... Though the link to the GitHub repo is [here](https://github.com/nyanzebra/vidoc).

## High-Level Overview
Just like with images, video compression can be thought of as a pipeline of steps that transform raw video data into a compressed format. Before going into depth, here is a high-level overview of the main components involved in video compression:

<div class="section">
    <h2>Encoding video</h2>
    <div class="flex-grid">
        <img src="/imgs/video-encode.svg" alt="video encode" style="max-width: 100%; height: auto;"/>
    </div>
</div>

Where the main components are:
1. **Frames**: Video is a sequence of images/pictures called frames. There are several types of frames each with different techniques for compression.
  * I-frames (Intra-coded frames): This is the technique discussed about in [lossy image compression](@/lossy-image-codec.md). The important part about I-frames is that they are independent of other frames and act as 'anchors' for future frames.
  * P-frames (Inter-coded frames): This is a frame that uses something called [motion vectors](https://www.sciencedirect.com/topics/engineering/motion-vector) to describe how pixels move between frames. Additionally, the residual difference between the predicted frame and the actual frame is stored, simply put, subtracting the predicted/reconstructed image from the actual image. P-frames depend on previous 'anchor' frames (I-frames or other P-frames).
  * B-frames (Bi-directional frames): These frames use both previous and future frames to predict the current frame. These operate just like P-frames but can rely on both past and future frames for motion estimation.
2. **Group of Pictures (GOP)**: A [GOP](https://en.wikipedia.org/wiki/Group_of_pictures) is a collection of frames that starts with an I-frame followed by a series of P-frames and B-frames. This structure allows for trading between compression and quality, more B-frames is going to result in better compression but worse quality, and vice-versa for the inverse.
3. **Encoding & Streaming**: After compressing into frames, the data needs an efficient way to transmit the data, which includes entropy coding (like Huffman coding) and optimizing io for streaming.

There are many other aspects to consider, like switching quality levels, etc., but this is the high-level overview and other topics will be left as exercises for the reader.

## Encoding Steps
I have broken down the article into the main steps involved in encoding, decoding is just the reverse of these steps. Making smaller sections made sense as digesting the content as whole can be a bit much. To get things started, we will first look at the frame types.

## Frames
The fundamental part of video: an image. As mentioned earlier, there are three types of frames: I-frames, P-frames, and B-frames.

### Intra-coded Frames (I-frames)
I-frames are almost 1-to-1 to the lossy image compression technique discussed in the previous article. The two differences from image compression are that I-frames need to be stored to be used for reference by other frames, as motion vectors will point to them. Additionally, or at least from what I have found, I-frames can use [Macroblocks](https://en.wikipedia.org/wiki/Macroblock) too. These will be discovered by looking at adjacent blocks of pixels and grouping them together if they are mathematically similar. For example, a block of blue sky likely has more blocks of blue sky around it. By grouping these, entropy coding can sometimes compress better.

### Inter-coded Frames (P-frames and B-frames)
Before getting into P-frames and B-frames, we need to understand motion estimation and residuals.

#### Motion Estimation
The core of intra-frame compression is looking at pixels and seeing where those pixels are being moved to in the following frames. This is done by a number of algorithms, but we will just talk about the simplest option: [LDSP and SDSP (Large and Small Diamond Search Pattern).](https://www.researchgate.net/figure/Large-Diamond-Search-Pattern-LDSP-and-Small-Diamond-Search-Pattern-SDSP_fig1_287313306) The idea is to look around a block of pixels and do some math to see how similar the pixels are compared to the original image/anchor block. The block with the lowest/smallest score/difference is chosen as the best match for the motion vector. Later on, during reassembly, the motion vector is used to copy pixels from the reference frame to the current one.

#### Residuals
After performing motion estimation, we will have a predicted frame that we can create using the motion vectors and the reference frame(s). However, it will not be as accurate as the original. In order to better approximate we need residuals. Residuals are literally subtracting the predicted frame created from the original reference frame. This can then be compressed along with the motion vectors to better recover the original frame during decoding.

#### P-frames
If we only ever had I-frames, we would have less data, but it would be nowhere near efficient enough for video as we see today. P-frames are the first step to accomplishing this. The primary idea is that when watching a video, most of the image is the same as the last one. For example, if there is a dinosaur on the screen now, there will probably be a dinosaur on the screen in the next frame too. The only difference is that it might have moved a bit. Instead of storing the entire image again, we can store just the changes. This is done using motion vectors and residuals.

#### B-frames
These work almost exactly like P-frames, except they can choose between referencing past frames, future frames, or both. The code difference between P-frames and B-frames is minimal and one could just implement code for B-frames and just make it so that P-frames are 'backwards'-looking only.

## GOP
A group of pictures is merely a logical abstraction over the frames we just covered. It has two important parts to it, one is how often an anchor point should be and the other is when should there be an I-frame. These knobs control the compression over a set of pictures and overall quality. These can be dynamically changed while streaming to save bandwidth if needed. For example, if you are doing a video call, having an I-frame every 12 frames is potentially overkill as people will rarely make big movements, so adjusting to larger windows of where expensive I-frame calculations occur can save the user on total amount of traffic to send for video conferencing.

Now, I know I just said there are two knobs, but there is one last thing the GOP should handle: holding onto anchor frames and delaying B-frames. As B-frame decoding can reference future frames, the GOP needs to sometimes delay decoding until the frame that is referenced arrives and then decode all the frames in-between together. This is one of the downsides of optimizing for compression, there is buffering on the decoder side and the longer the width between anchors the more buffering that is required and the more frames that get decoded in a bunch instead of one by one.

## Encoding
Encoding is where I saw some of my first performance issues. Huffman encoding, while functional, was too slow by my benchmarks, taking the majority of the time in the decoding process. Eventually I came across [Asymmetric Numeral Systems](https://en.wikipedia.org/wiki/Asymmetric_numeral_systems) and oh wow, it was so much better. While maybe not the best for compression based on entropy levels, it was an order of magnitude faster in my local testing.

If you are considering a bit-level encoder and don't care about the time to compress or decompress, then using Huffman will be perfectly fine, but if you plan to use bit-level encoding in a timely manner then just use ANS, it will save you a lot of time and hassle :smile:.

## Performance
While not mentioned above, this is a very important callout. If one naively puts together their own video codec you will not get great speeds, even my own codec referenced above is probably not great for hitting 60fps of high-quality streaming content, maybe not even normal streaming... There are a few ways to achieve better performance however:

1. Parallelism, if you add threads to do the calculations of multiple frames and multiple blocks within a frame you will easily get # of cpus more performance. This is one of, if not the biggest win. With a library like rayon, if using rust, you can easily just switch to a `par_iter` in parts of your code and get better FPS.
2. SIMD, this is that fancy cpu math that a lot of people know about but never use, turns out telling the cpu to do more calculations in a single instruction makes things faster :P!
3. Something I haven't done, but is common elsewhere is [hardware acceleration](https://en.wikipedia.org/wiki/Codec_acceleration), this is where one uses specialized hardware to do some of the heavy computations for you.

## Conclusion
I hope this has been an edifying overview of video compression and that the reference code is useful for others. I might continue this series if I decide to make my own zoom / discord implementation as a side project. Anyways, thanks for reading!
