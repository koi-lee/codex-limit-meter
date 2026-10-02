import Foundation
import Testing
@testable import CodexMeter

@MainActor @Test func constellationCanReverseAndStopWithoutLosingQuota() {
    var effect=PetConstellation()
    effect.opened=true;effect.advance(0.3,reduced:false)
    #expect(effect.progress > 0 && effect.progress < 1)
    let halfway=effect.progress
    effect.opened=false;effect.advance(0.05,reduced:false)
    #expect(effect.progress < halfway)
    effect.advance(1,reduced:false)
    #expect(effect.progress == 0 && !effect.isAnimating)
    // Quicker reveal retains the approved reference geometry.
    effect.opened=true;effect.advance(1.3,reduced:false)
    #expect(effect.progress == 1 && !effect.isAnimating)
}
@MainActor @Test func constellationReducedMotionShowsAndHidesImmediately() {
    var effect=PetConstellation()
    effect.opened=true;effect.advance(0,reduced:true)
    #expect(effect.progress == 1)
    effect.opened=false;effect.advance(0,reduced:true)
    #expect(effect.progress == 0)
}

@Test func orbitStarsShareExpansionAndReturnToExactTargets() {
    let start = PetOrbitMotion(progress: 0), half = PetOrbitMotion(progress: 0.5), end = PetOrbitMotion(progress: 1)
    #expect(start.scale < half.scale && half.scale < end.scale)
    #expect(end.scale == 1 && end.rotation == 0)
    for index in 0..<3 {
        let point = PetOrbitMotion.star(index)
        #expect(end.position(point) == point)
        #expect(half.position(point) != point)
        let distance = hypot(half.position(point).x-half.center.x, half.position(point).y-half.center.y)
        #expect(abs(distance-hypot(point.x-308, point.y-300)*half.scale) < 0.00001)
    }
    // One progress value drives opening and closing; interruption does not reset phase.
    #expect(PetOrbitMotion(progress: -1).eased == start.eased)
    #expect(PetOrbitMotion(progress: 2).eased == end.eased)
}

@Test func navigationStarsTravelAlongEllipseAndSettle() {
    for index in 0..<3 {
        let fixed = PetOrbitMotion.star(index)
        #expect(PetOrbitMotion.star(index, progress: 1) == fixed)
        #expect(PetOrbitMotion.star(index, progress: 0.5) != fixed)
        for p in [0.0, 0.2, 0.5, 0.8, 1.0] {
            let point = PetOrbitMotion.star(index, progress: p)
            let dx = point.x-308, dy = point.y-300
            let x = dx*cos(0.12)+dy*sin(0.12), y = -dx*sin(0.12)+dy*cos(0.12)
            #expect(abs(x*x/(103*103)+y*y/(69*69)-1) < 0.000001)
        }
    }
}

@MainActor @Test func constellationSettlesWithinInteractionBudget() {
    var effect = PetConstellation()
    effect.opened = true
    effect.advance(0.72, reduced: false)
    #expect(effect.progress == 1)
    effect.opened = false
    effect.advance(0.36, reduced: false)
    #expect(effect.progress == 0)
}
