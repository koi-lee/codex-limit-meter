import Testing
import AppKit
@testable import CodexMeter
@Test func companionCardFollowsAndChangesSides() {
 let screen = NSRect(x:0,y:0,width:1440,height:900)
 let size = NSSize(width:320,height:280)
 let anchor = NSRect(x:200,y:300,width:256,height:286)
 let first = companionCardFrame(anchor:anchor,size:size,screen:screen)
 let moved = companionCardFrame(anchor:anchor.offsetBy(dx:80,dy:30),size:size,screen:screen)
 #expect(moved.origin == first.offsetBy(dx:80,dy:30).origin)
 let edge = NSRect(x:1150,y:30,width:256,height:286)
 #expect(companionCardFrame(anchor:edge,size:size,screen:screen).maxX == edge.minX-12)
 let external = NSRect(x:-1440,y:0,width:1440,height:900)
 #expect(external.contains(companionCardFrame(anchor:NSRect(x:-300,y:0,width:256,height:286),size:size,screen:external)))
}
