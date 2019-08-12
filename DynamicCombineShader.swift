//
//  DynamicCombineShader.swift
//  TrashTestBlurComp
//
//  Created by Caleb Kierum on 8/11/19.
//  Copyright © 2019 Caleb Kierum. All rights reserved.
//

import Foundation

// This class is designed to create shaders that have dynamic inputs and properties
class DynamicTextureCombineShader {
    private let settingsList:[(Float, Float)]
    init (list:[(Float, Float)]) {
        settingsList = list
    }
    static func vertexShader() -> String {
        return "vertex ColorInOut gaussianComp_vertex(uint vid [[vertex_id]]) {\n\tconst float2 coords[] = {float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0)};\n\tconst float2 texc[] = {float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0), float2(1.0, 0.0)};\n\tconst int lu[] = {0, 1, 2, 2, 1, 3};\n\n\tColorInOut out;\n\tout.texCoord = texc[lu[vid]];\n\tout.position = float4(coords[lu[vid]], 0.0, 1.0);\n\treturn out;\n}"
    }
    func fragmentShader() -> String {
        var top:String = "fragment float4 gaussianComp_fragment(ColorInOut texCoord [[stage_in]]"
        var predicate:String = "\tconstexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);\n\n\treturn "
        
        
        for i in 0..<settingsList.count {
            let level = settingsList[i]
            top += ",\n\t\t\ttexture2d<float> texture\(i) [[texture(\(i))]]"
            predicate += "\t\t"
            
            if (i != 0) {
                predicate += "+"
            }
            
            if (level.1 == 1) {
                predicate += "(texture\(i).sample(colorSampler, texCoord.texCoord) * \(level.0))"
            } else {
                predicate += "(pow(texture\(i).sample(colorSampler, texCoord.texCoord), \(level.1)) * \(level.0))"
            }
        }
        
        return top + ") {\n\n\t" + predicate + ";\n}"
    }
    func getShaderString() -> String {
        return DynamicTextureCombineShader.getHeader() + "\n\n" + DynamicTextureCombineShader.getStruct() + "\n\n" + DynamicTextureCombineShader.vertexShader() + "\n\n" + fragmentShader()
    }
    
    
    static private func getHeader() -> String {
        return "using namespace metal;\n#include <metal_stdlib>"
    }
    
    static private func getStruct() -> String {
        return "typedef struct\n{\n\tfloat4 position [[position]];\n\tfloat2 texCoord;\n} ColorInOut;"
    }
}
