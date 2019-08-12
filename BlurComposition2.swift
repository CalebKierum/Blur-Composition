//
//  BlurComposition2.swift
//
//  Created by Caleb on 1/13/19.
//  Copyright © 2019 Caleb. All rights reserved.
//

import Metal
import Foundation
import MetalPerformanceShaders


// Simply stores a MTL texture with an ID for debugging purposes
fileprivate class IDTexture {
    var texture:MTLTexture
    var id:String
    init (_ tex: MTLTexture) {
        texture = tex
        if let lab = tex.label {
            id = lab
        } else {
            id = "\(Int(arc4random()))"
            texture.label = id
        }
    }
}
fileprivate func == (lhs: IDTexture, rhs: IDTexture) -> Bool {
    return lhs.texture.label! == rhs.texture.label!
}

fileprivate func == (lhs: IDTexture, rhs: MTLTexture) -> Bool {
    return lhs.texture.label! == rhs.label!
}

fileprivate func == (lhs: MTLTexture, rhs: IDTexture) -> Bool {
    return rhs.texture.label! == lhs.label!
}

fileprivate func == (lhs: MTLTexture, rhs: MTLTexture) -> Bool {
    return rhs.label! == lhs.label!
}


@objc class BlurComposition2 : NSObject {
    
    @objc enum BlurCompositionBlendModes:Int {
        case replace
        case additive
        case alpha
        case fakeadd
    }
    
    private var instructions:[Float : [([Float], Float, Float, IDTexture?)]]
    
    
    // Pass in an array of ComplexBlurredLayer or BlurredLayer objects
    init(_ inst:[BlurredLayer]) {
        var buildInst:[Float : [([Float], Float, Float, IDTexture?)]] = [:]
        inst.forEach({layer in
            var steps:[Float] = []
            if let cbl = layer as? ComplexBlurredLayer {
                steps = cbl.pointBlurSteps
            } else if let sbl = layer as? SimpleBlurredLayer {
                steps.append(sbl.pointBlur)
            }
            
            let insert:([Float], Float, Float, IDTexture?) = (steps, layer.opacity, layer.power, nil)
            if let _ = buildInst[layer.scaleFactor] {
                buildInst[layer.scaleFactor]!.append(insert)
            } else {
                buildInst[layer.scaleFactor] = []
                buildInst[layer.scaleFactor]?.append(insert)
            }
        })
        
        instructions = buildInst
        
        super.init();
    }
    
    
    
    private func helperMakeTexture(width:Int, height:Int, device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount:Int) -> IDTexture {
        let descript = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        
        descript.usage = [MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite, MTLTextureUsage.renderTarget]
        descript.sampleCount = sampleCount;
        
        let create = device.makeTexture(descriptor: descript)
        assert(create != nil)
        return IDTexture(create!);
    }
    
    private class EncodingStep { }
    
    private class CopyEncodingStep:EncodingStep {
        var descriptor:MTLRenderPassDescriptor
        var pipeline:MTLRenderPipelineState
        var source:IDTexture
        init(descriptor: MTLRenderPassDescriptor, pipeline:MTLRenderPipelineState, source:IDTexture) {
            self.descriptor = descriptor
            self.pipeline = pipeline
            self.source = source
        }
    }
    private class BlitEncodingStep:EncodingStep {
        var steps:[(IDTexture, IDTexture)] = []
    }
    private class BlurEncodingStep:EncodingStep {
        var sigma:Float
        var steps:[(IDTexture, IDTexture?)] = []
        init (sigma: Float) {
            self.sigma = sigma
        }
    }
    private class LevelObject {
        var bigBlit:BlitEncodingStep = BlitEncodingStep()
        var afterSteps:[EncodingStep] = []
    }
    private var drawingSteps:[EncodingStep] = []
    private var levelObjects:[LevelObject] = []
    private func helperGetLevelObjectOrCreate(level:Int) -> LevelObject {
        if (level < levelObjects.count) {
            return levelObjects[level]
        }
        levelObjects.append(LevelObject())
        return levelObjects.last!
    }
    
    private func helperCopyEncodingStep(from: IDTexture, to: IDTexture) -> CopyEncodingStep {
        let descrip = MTLRenderPassDescriptor()
        descrip.colorAttachments[0].texture = to.texture
        descrip.colorAttachments[0].loadAction = .clear
        descrip.colorAttachments[0].storeAction = .store
        descrip.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        let pipeline = basicCopyPipeline
        let src = from
        return CopyEncodingStep(descriptor: descrip, pipeline: pipeline!, source: src)
    }
    
    private func helperTransformSigma(pointBlur: Float, globalScaleFactor: Float, treeScaleFactor: Float) -> Float {
        return pointBlur * globalScaleFactor * treeScaleFactor
    }
    
    
    private func helperProcessTree(trees:[(IDTexture, [Float])], level:Int, blitting:Bool, globalScaleFactor:Float, treeScaleFactor:Float) {
        var groups:[Float : [(IDTexture, [Float])]] = [:]
        
        let writeTo:LevelObject = helperGetLevelObjectOrCreate(level: level)
        
        // Get the master level
        var master = trees.first!
        var masterLevel:Float = 0
        if (level < master.1.count) {
            masterLevel = master.1[level]
        }
        
        // Break up into distinct trees
        for tree in trees {
            var personalLevel:Float = 0
            if (level < tree.1.count) {
                personalLevel = tree.1[level]
            }
            
            
            // insert into groups
            if let _ = groups[personalLevel] {
                groups[personalLevel]!.append(tree)
            } else {
                groups[personalLevel] = []
                groups[personalLevel]!.append(tree)
            }
        }
        
        let masterTex = groups[masterLevel]!.first!.0
        
        for group in groups.keys {
            if (group != masterLevel) {
                let minorMasterTex = groups[group]!.first!.0
                // It needs the source material
                if (group == 0) {
                    // Add it to be copied
                    if (blitting) {
                        writeTo.bigBlit.steps.append((masterTex, minorMasterTex))
                    } else {
                        writeTo.afterSteps.append(helperCopyEncodingStep(from: masterTex, to: minorMasterTex))
                    }
                } else {
                    
                    let bes = BlurEncodingStep(sigma: group)
                    checkAddSigma(sigma: group)
                    bes.steps.append((masterTex, minorMasterTex))
                    writeTo.afterSteps.append(bes)
                    helperProcessTree(trees: groups[group]!, level: level + 1, blitting: blitting, globalScaleFactor: globalScaleFactor, treeScaleFactor: treeScaleFactor)
                }
            }
        }
        
        // Do whatever has to be done to this texture
        if (masterLevel != 0) {
            let bes = BlurEncodingStep(sigma: masterLevel)
            checkAddSigma(sigma: masterLevel)
            bes.steps.append((masterTex, nil))
            writeTo.afterSteps.append(bes)
            helperProcessTree(trees: groups[masterLevel]!, level: level + 1, blitting: blitting, globalScaleFactor: globalScaleFactor, treeScaleFactor: treeScaleFactor)
        } else {
            // Copy to all of them
            for i in 1..<groups[masterLevel]!.count {
                let minorMasterTex = groups[masterLevel]![i].0
                if (blitting) {
                    writeTo.bigBlit.steps.append((masterTex, minorMasterTex))
                } else {
                    writeTo.afterSteps.append(helperCopyEncodingStep(from: masterTex, to: minorMasterTex))
                }
            }
        }
    }
    
    private var basicCopyPipeline:MTLRenderPipelineState? = nil
    
    private var combiningPipeline:MTLRenderPipelineState? = nil
    private var combiningPassDecriptor:MTLRenderPassDescriptor = MTLRenderPassDescriptor()
    private var combiningPieces:[IDTexture] = []
    
    private var sigmas:[Float : MPSImageGaussianBlur] = [:]
    private var cheatSigmaDevice:MTLDevice? = nil
    private func checkAddSigma(sigma: Float) {
        if let _ = sigmas[sigma] {
            
        } else {
            sigmas[sigma] = MPSImageGaussianBlur(device: cheatSigmaDevice!, sigma: sigma)
        }
    }
    
    private var debugSource:IDTexture? = nil
    private var debugDestination:IDTexture? = nil
    
    //*
    //  scaleFactor converts points to pixels
    //  width, height are screen dimensions in points
    //  device is the metal device, use this to create textures etc
    //  useBlit is for times where
    @objc func prepareWith(source: MTLTexture, destination: MTLTexture, scaleFactor: Float, width: Int, height: Int, device:MTLDevice, useBlit:Bool, pixelFormat:MTLPixelFormat, sampleCount:Int, finalCombineMode:BlurCompositionBlendModes) {
        
        if (finalCombineMode != BlurCompositionBlendModes.replace) {
            print("We only know how to do replace blend mode")
            assert(false)
        }
        
        debugSource = IDTexture(source)
        debugDestination = IDTexture(destination)
        
        // Create textures for everything
        for key in instructions.keys {
            let array = instructions[key]!
            for i in 0..<array.count {
                var copy = array[i]
                let create = helperMakeTexture(width: (Int(Float(width) * scaleFactor * key)), height: (Int(Float(height) * scaleFactor * key)), device: device, pixelFormat: pixelFormat, sampleCount: sampleCount)
                copy.3 = create
                instructions[key]![i] = copy
            }
        }
        
        //***Setup Stage
        //  For now we arent over-engineering this
        //       |Create a pipeline state for copy
        //          Create objects to be encoded for all of these things
        // IF BLITTING
        //          finish encoding
        //       |Go through all the blit objects
        // If NOT BLITTING
        //          Create objects to be encoded for all these things
        //          finish encoding
        //
        //***Finishing Stage (ASSERT: All objects have the latest frame)
        //      |Go through and create all the blur instructions
        //
        //***Combining Stage
        //      |Create a pipeline for the combine
        //          Create object for the encoding
        //          finish encoding
        
        // Setup Stage
        // Get images to all sizes (source->[keySet])
        
        // Initialize basic copy pipeline
        basicCopyPipeline = basicCopyPipelineMake(device: device, sampleCount: sampleCount, pixelFormat: pixelFormat)
        cheatSigmaDevice = device
        levelObjects = []
        // Copy to the first layer of each
        for key in instructions.keys {
            drawingSteps.append(helperCopyEncodingStep(from: IDTexture(source), to: instructions[key]!.first!.3!))
            
            var trees:[(IDTexture, [Float])] = []
            for el in instructions[key]! {
                var build = el.0
                for i in 0..<build.count {
                    build[i] = helperTransformSigma(pointBlur: build[i], globalScaleFactor: scaleFactor, treeScaleFactor: key)
                }
                trees.append((el.3!, build))
            }
            helperProcessTree(trees: trees, level: 0, blitting:useBlit, globalScaleFactor: scaleFactor, treeScaleFactor: key)
        }
        for level in levelObjects {
            if (level.bigBlit.steps.count > 0) {
                drawingSteps.append(level.bigBlit)
            }
            drawingSteps.append(contentsOf: level.afterSteps)
        }
        
        
        // Combining stage
        var instructionBuild:[(Float, Float)] = []
        for key in instructions.keys {
            for value in instructions[key]! {
                combiningPieces.append(value.3!)
                instructionBuild.append((value.1, value.2))
            }
        }
        if (finalCombineMode == .fakeadd) {
            combiningPieces.append(IDTexture(destination))
            instructionBuild.append((Float(1.0), Float(1.0)))
        }
        combiningPieces.append(IDTexture(source))
        instructionBuild.append((Float(1.0), Float(1.0)))
        
        combiningPassDecriptor.colorAttachments[0].texture = destination
        if (finalCombineMode == .replace || finalCombineMode == .fakeadd) {
            combiningPassDecriptor.colorAttachments[0].loadAction = .clear
        } else {
            combiningPassDecriptor.colorAttachments[0].loadAction = .load
        }
        combiningPassDecriptor.colorAttachments[0].storeAction = .store
        combiningPassDecriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        
        let shader = DynamicTextureCombineShader(list: instructionBuild);
        do {
            let library = try device.makeLibrary(source: shader.getShaderString(), options: nil)
            let vertex = library.makeFunction(name: "gaussianComp_vertex")!
            let fragment = library.makeFunction(name: "gaussianComp_fragment")!
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.fragmentFunction = fragment
            descriptor.vertexFunction = vertex
            // Sample count, pixel format, blend function
            descriptor.sampleCount = sampleCount
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            if (finalCombineMode == .replace) {
                descriptor.colorAttachments[0].isBlendingEnabled = false
            } else if (finalCombineMode == .alpha) {
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
                descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.sourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
            } else if (finalCombineMode == .additive) {
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
                descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.one
            }
            
            combiningPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Couldnt create the combining pipeline")
            print(shader.getShaderString())
        }
        
        assert(combiningPipeline != nil)
    }
    
    
    private func debugNameTexture(tex: MTLTexture) -> String {
        var build = ""
        
        for i in 0..<combiningPieces.count {
            if (tex == combiningPieces[i]) {
                build += "\(i)"
            }
        }
        
        if (safeEqualCheck(tex1: tex, tex2: debugSource)) {
            build += " Source"
        }
        if (safeEqualCheck(tex1: tex, tex2: debugDestination)) {
            build += " Destination"
        }
        
        return build
    }
    private func safeEqualCheck(tex1: MTLTexture?, tex2: IDTexture?) -> Bool {
        if (tex1 == nil || tex2 == nil) {
            return false;
        } else if (tex1! == nil || tex2!.texture == nil) {
            return false
        } else {
            return tex1! == tex2!
        }
    }
    private func safeEqualCheck(tex1: IDTexture?, tex2: IDTexture?) -> Bool {
        if (tex1 == nil || tex2 == nil) {
            return false;
        } else if (tex1!.texture == nil || tex2!.texture == nil) {
            return false
        } else {
            return tex1! == tex2!
        }
    }
    private func debugNameTexture(tex: IDTexture) -> String {
        var build = ""
        
        for i in 0..<combiningPieces.count {
            if (tex == combiningPieces[i]) {
                build += "\(i)"
            }
        }
        if (safeEqualCheck(tex1: tex, tex2: debugSource)) {
            build += " Source"
        }
        if (safeEqualCheck(tex1: tex, tex2: debugDestination)) {
            build += " Destination"
        }
        
        
        return build
    }
    
    @objc func render(buffer: MTLCommandBuffer) {
        let debug:Bool = false
        
        
        for step in drawingSteps {
            if let ces = step as? CopyEncodingStep {
                var debugLabel:String? = nil
                if (debug) {
                    let to = debugNameTexture(tex: ces.descriptor.colorAttachments[0]!.texture!)
                    let from = debugNameTexture(tex: ces.source.texture)
                    debugLabel = "Copying \(from) onto \(to) via shader"
                    print(debugLabel!)
                }
                let encoder = buffer.makeRenderCommandEncoder(descriptor: ces.descriptor)!
                encoder.setRenderPipelineState(ces.pipeline)
                encoder.label = debugLabel
                encoder.setFragmentTexture(ces.source.texture, index: 0)
                encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            } else if let bes = step as? BlitEncodingStep {
                if (debug) {
                    print("Creating blit")
                }
                let encoder = buffer.makeBlitCommandEncoder()!
                let origin = MTLOriginMake(0, 0, 0)
                for step in bes.steps {
                    if (debug) {
                        let to = debugNameTexture(tex: step.1)
                        let from = debugNameTexture(tex: step.0)
                        print("Copying \(from) onto \(to) via blit")
                    }
                    let size = MTLSizeMake(step.0.texture.width, step.0.texture.height, 1)
                    encoder.copy(from: step.0.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size, to: step.1.texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
                }
                encoder.endEncoding()
            } else if let bes = step as? BlurEncodingStep {
                let encoder = sigmas[bes.sigma]!
                encoder.label = "Glow encoder sigma: \(bes.sigma)"
                for step in bes.steps {
                    if (step.1 == nil) {
                        if (debug) {
                            let from = debugNameTexture(tex: step.0)
                            print("Glowing \(from) onto itself with kernel \(bes.sigma)")
                        }
                        var copy = step.0.texture
                        encoder.encode(commandBuffer: buffer, inPlaceTexture: &copy, fallbackCopyAllocator: nil)
                    } else {
                        if (debug) {
                            let to = debugNameTexture(tex: step.1!)
                            let from = debugNameTexture(tex: step.0)
                            print("Glowing \(from) onto \(to) with kernel \(bes.sigma)")
                        }
                        encoder.encode(commandBuffer: buffer, sourceTexture: step.0.texture, destinationTexture: step.1!.texture)
                    }
                }
                
            }
        }
        
        if (debug) {
            print("FINAL STEP")
        }
        
        if (debug) {
            if (combiningPassDecriptor.colorAttachments[0]!.texture != nil) {
                print("Drawing onto \(debugNameTexture(tex: combiningPassDecriptor.colorAttachments[0]!.texture!))")
            }
        }
        // Finally copy it onto the destination
        let encoder = buffer.makeRenderCommandEncoder(descriptor: combiningPassDecriptor)!
        encoder.setRenderPipelineState(combiningPipeline!)
        for i in 0..<combiningPieces.count {
            if (debug) {
                let to = debugNameTexture(tex: combiningPieces[i])
                print("Adding in \(to)")
            }
            encoder.setFragmentTexture(combiningPieces[i].texture, index: i)
        }
        
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        
        if (debug) {
            print("DONE!")
        }
    }
    
    private func basicCopyPipelineMake(device: MTLDevice, sampleCount: Int, pixelFormat:MTLPixelFormat) -> MTLRenderPipelineState {
        var list:[(Float, Float)] = []
        list.append((1.0, 1.0));
        let shader = DynamicTextureCombineShader(list: list)
        do {
            let library = try device.makeLibrary(source: shader.getShaderString(), options: nil)
            let vertex = library.makeFunction(name: "gaussianComp_vertex")!
            let fragment = library.makeFunction(name: "gaussianComp_fragment")!
            
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.fragmentFunction = fragment
            descriptor.vertexFunction = vertex
            // Sample count, pixel format, blend function
            descriptor.sampleCount = sampleCount
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Couldnt compile basic pipeline shader")
            print(shader.getShaderString())
        }
        exit(1)
    }
}
