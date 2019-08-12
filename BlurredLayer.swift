//
//  BlurredLayer.swift
//  TrashTestBlurComp
//
//  Created by Caleb Kierum on 8/11/19.
//  Copyright © 2019 Caleb Kierum. All rights reserved.
//

import Foundation

// For single blur instructions
class BlurredLayer: NSObject {
    let scaleFactor:Float
    let opacity:Float
    let power:Float
    init (scaleFactor:Float, opacity: Float, power:Float = 1.0) {
        self.scaleFactor = scaleFactor
        self.opacity = opacity
        self.power = power
    }
}

// For multiple blur instructions
class ComplexBlurredLayer : BlurredLayer {
    var pointBlurSteps:[Float]
    init (scaleFactor:Float, opacity: Float, steps: [Float], power:Float = 1.0) {
        pointBlurSteps = steps;
        super.init(scaleFactor: scaleFactor, opacity: opacity, power: power)
    }
    
    
    func afterScale(by: Float) -> ComplexBlurredLayer {
        for i in 0..<pointBlurSteps.count {
            pointBlurSteps[i] *= by
        }
        return self
    }
}

// For single blur instruction
class SimpleBlurredLayer : BlurredLayer {
    var pointBlur:Float
    init (scaleFactor:Float, opacity: Float, points: Float, power:Float = 1.0) {
        pointBlur = points
        super.init(scaleFactor: scaleFactor, opacity: opacity, power:power)
    }
    
    func afterScale(by: Float) -> SimpleBlurredLayer {
        pointBlur *= by
        return self
    }
}
