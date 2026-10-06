import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let image = NSImage(size: NSSize(width:size,height:size)); image.lockFocus()
    let t = AffineTransform(scale:CGFloat(size)/1024); (t as NSAffineTransform).concat()
    let rect = NSRect(x:72,y:72,width:880,height:880)
    NSColor(calibratedRed:0.96,green:0.965,blue:0.98,alpha:1).setFill(); NSBezierPath(roundedRect:rect,xRadius:200,yRadius:200).fill()
    let path = NSBezierPath(); path.move(to:NSPoint(x:300,y:300)); path.curve(to:NSPoint(x:675,y:720),controlPoint1:NSPoint(x:260,y:720),controlPoint2:NSPoint(x:410,y:825)); path.curve(to:NSPoint(x:490,y:435),controlPoint1:NSPoint(x:910,y:600),controlPoint2:NSPoint(x:590,y:295)); path.curve(to:NSPoint(x:704,y:338),controlPoint1:NSPoint(x:405,y:550),controlPoint2:NSPoint(x:620,y:590)); path.lineWidth=64; path.lineCapStyle = .round; path.lineJoinStyle = .round; NSColor(calibratedRed:0.14,green:0.23,blue:0.37,alpha:1).setStroke(); path.stroke()
    NSColor(calibratedRed:0.93,green:0.55,blue:0.30,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:264,y:264,width:72,height:72)).fill()
    image.unlockFocus()
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!; try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
}
