# Blur Composition

![Diagram](https://i.imgur.com/btlm1DZ.png)


## Abstract

For artist directed glow it is critical to have fine grained control over the blurs that make up your glow effect. This way you can finely control the look, strength, adn composition of the blur. This often requires mutliple blur kernels to be combined. Repeated blur kernels do not look so ordering matters.

From a technical side blurs and other convolutions are expensive. However it is shown that you can often utilize bilateral sampling on its own or in conjunction with blur kernels to achieve similar glow effects with less computational cost. Combining blurs at different resolutions greatly hides sampling artifacts.

This class aims to combine both the technical and artistic needs into one easy to use class. The artist creates a list of blurred layers they want to combine into the final glow effect and those instructions are translated into something more technically efficient. A quality knob allows for further enhancements of performance (at the cost of quality)

## How does this work

The blur steps you passed in are turned into an optimal set of steps that minimizes copying, resizing, and blurring but still has the same effect.

Custom shaders are programatically written in order to allow for shaders with dynamic inputs and parameters in the most efficient way.

Currently this class requires MetalPerfornaceShaders to do this glow effect in the most processor effective way.



## How To Use

First create a BlurComposition2 object with a list of your `BlurredLayer`, `ComplexBlurredLayer`, and `SimpleBlurredLayer` objects.

Then call prepareWith() passing in the source and destination texture and parameters like:
- `scaleFactor`: Sort of a resolution parameter. If you scale this down the effect looses quality but potentially performance.
- `width/height`: of passed in texture
- `useBlit`: whether to use Blitting in order to copy textures of same resolution
- `pixelFormat`: The format of the pixels in the texture
- `sampleCount`: Sample count for your renderer
- `finalCombineMode`: An enum defining how all the layers should be combined in the end


Finally call `render()` with a command buffer in order to have all the steps for processing this blur added to it.
