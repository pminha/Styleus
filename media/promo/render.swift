// Styleus — original illustrated product film. Copyright (c) Styleus contributors.
// Reproduce with media/promo/render.sh. Requires macOS, Swift, and FFmpeg.
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let W = 1920, H = 1080
let fps = 60
let duration = 30.0
let teal = NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.53, alpha: 1)
let ink = NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.17, alpha: 1)
let orange = NSColor(calibratedRed: 0.90, green: 0.47, blue: 0.24, alpha: 1)
let muted = NSColor(calibratedRed: 0.39, green: 0.43, blue: 0.45, alpha: 1)
let showAppIcons = CommandLine.arguments.contains("--icons")
func loadIcon(_ file:String)->CGImage? {
    guard showAppIcons, let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:file) as CFURL,nil) else{return nil}
    return CGImageSourceCreateImageAtIndex(source,0,nil)
}
let ipadIcon=loadIcon("media/branding/styleus-ipad-1024.png")
let macIcon=loadIcon("media/branding/styleus-mac-1024.png")
func drawImage(_ c:CGContext,_ image:CGImage,_ r:CGRect){
    c.saveGState();c.addPath(CGPath(roundedRect:r,cornerWidth:21,cornerHeight:21,transform:nil));c.clip();c.translateBy(x:r.minX,y:r.maxY);c.scaleBy(x:1,y:-1);c.draw(image,in:CGRect(origin:.zero,size:r.size));c.restoreGState()
}
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red:r,green:g,blue:b,alpha:a) }
func alpha(_ c: NSColor, _ a: Double) -> CGColor { c.withAlphaComponent(a).cgColor }
func clamp(_ x: Double) -> Double { max(0,min(1,x)) }
func smooth(_ x: Double) -> Double { let v=clamp(x);return v*v*(3-2*v) }
func ease(_ x: Double) -> Double { let v=clamp(x); return v < 0.5 ? 4*v*v*v : 1-pow(-2*v+2,3)/2 }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a+(b-a)*t }
func point(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x:lerp(a.x,b.x,t),y:lerp(a.y,b.y,t)) }
func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { smooth((t-a)/(b-a)) }
func rect(_ c: CGContext, _ r: CGRect, _ fill: CGColor, radius: CGFloat=0) { c.setFillColor(fill);c.addPath(CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil));c.fillPath() }
func stroke(_ c: CGContext, _ r: CGRect, _ col: CGColor, width:CGFloat=1, radius:CGFloat=0) {c.setStrokeColor(col);c.setLineWidth(width);c.addPath(CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil));c.strokePath()}
func line(_ c: CGContext, _ a: CGPoint, _ b: CGPoint, _ col: CGColor, _ width: CGFloat=1) {c.setStrokeColor(col);c.setLineWidth(width);c.setLineCap(.round);c.move(to:a);c.addLine(to:b);c.strokePath()}
func circle(_ c:CGContext, _ p:CGPoint, _ r:CGFloat,_ fill:CGColor){c.setFillColor(fill);c.fillEllipse(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))}
func text(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ col: NSColor = ink, tracking: CGFloat=0) {
    let font=NSFont.systemFont(ofSize:size,weight:weight)
    let a=NSAttributedString(string:s,attributes:[.font:font,.foregroundColor:col,.kern:tracking])
    let l=CTLineCreateWithAttributedString(a)
    c.saveGState();c.translateBy(x:x,y:y+font.ascender);c.scaleBy(x:1,y:-1);c.textMatrix = .identity;CTLineDraw(l,c);c.restoreGState()
}
func textWidth(_ s:String,_ size:CGFloat,_ weight:NSFont.Weight = .regular)->CGFloat {(s as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight)]).width}
func centerText(_ c:CGContext,_ s:String,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ col:NSColor = ink){text(c,s,(CGFloat(W)-textWidth(s,size,weight))/2,y,size,weight,col)}
func gradient(_ c:CGContext,_ r:CGRect,_ colors:[CGColor],_ start:CGPoint,_ end:CGPoint,radius:CGFloat=0){c.saveGState();c.addPath(CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil));c.clip();let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:nil)!;c.drawLinearGradient(g,start:start,end:end,options:[.drawsBeforeStartLocation,.drawsAfterEndLocation]);c.restoreGState()}
func poly(_ c:CGContext,_ points:[CGPoint],_ fill:CGColor){guard let p=points.first else{return};c.beginPath();c.move(to:p);for q in points.dropFirst(){c.addLine(to:q)};c.closePath();c.setFillColor(fill);c.fillPath()}
func shadow(_ c:CGContext,_ opacity:CGFloat=0.16,_ blur:CGFloat=35,_ y:CGFloat=18){c.setShadow(offset:CGSize(width:0,height:y),blur:blur,color:color(0.08,0.14,0.17,opacity))}

let screen=CGRect(x:865,y:220,width:900,height:530)
let paper=CGRect(x:screen.minX+32,y:screen.minY+70,width:screen.width-64,height:screen.height-95)
let padArea=CGRect(x:54,y:104,width:634,height:634*435/836)
func inRect(_ r:CGRect,_ uv:CGPoint)->CGPoint {CGPoint(x:r.minX+uv.x*r.width,y:r.minY+uv.y*r.height)}
func trackPoint(_ t:Double)->CGPoint {
    if t<3.5{return CGPoint(x:0.29,y:0.67)}
    if t<5.4{return point(CGPoint(x:0.29,y:0.67),CGPoint(x:0.65,y:0.32),ease((t-3.5)/1.9))}
    if t<5.9{return point(CGPoint(x:0.65,y:0.32),CGPoint(x:0.30,y:0.54),ease((t-5.4)/0.5))}
    if t<7.2{return point(CGPoint(x:0.30,y:0.54),CGPoint(x:0.48,y:0.42),ease((t-5.9)/1.3))}
    return CGPoint(x:0.48,y:0.42)
}
func remotePoint(_ t:Double)->CGPoint {
    if t<3.5{return CGPoint(x:0.24,y:0.72)}
    if t<5.4{return point(CGPoint(x:0.24,y:0.72),CGPoint(x:0.64,y:0.36),ease((t-3.5)/1.9))}
    if t<5.9{return CGPoint(x:0.64,y:0.36)}
    return point(CGPoint(x:0.64,y:0.36),CGPoint(x:0.79,y:0.25),ease((t-5.9)/1.3))
}
func dragPoint(_ t:Double)->CGPoint {point(CGPoint(x:0.36,y:0.62),CGPoint(x:0.69,y:0.32),ease((t-10.6)/3.2))}
func firstInk(_ p:Double)->CGPoint {CGPoint(x:0.21+0.37*p,y:0.405+0.006*sin(p*Double.pi*3))}
func secondInk(_ p:Double)->CGPoint {
    if p<0.34{return point(CGPoint(x:0.65,y:0.59),CGPoint(x:0.69,y:0.68),p/0.34)}
    return point(CGPoint(x:0.69,y:0.68),CGPoint(x:0.81,y:0.48),(p-0.34)/0.66)
}
func drawingPoint(_ t:Double)->CGPoint {
    if t<18.35{return firstInk(clamp((t-16.0)/1.9))}
    if t<18.8{return point(firstInk(1),secondInk(0),ease((t-18.35)/0.45))}
    return secondInk(clamp((t-18.8)/1.8))
}
func isContact(_ t:Double)->Bool {
    if t<3.5{return t>2.4}
    if t<9.4{return !(t>5.4 && t<5.9) && !(t>7.2 && t<7.62) && t<7.83}
    if t<15.4{return t>9.9 && t<14.4}
    if t<22.4{return (t>=16.0 && t<=17.9)||(t>=18.8 && t<=20.6)}
    return false
}
func pressure(_ t:Double)->Double {
    if t>10.5 && t<14.1{return 0.64}
    if (t>=16 && t<=17.9)||(t>=18.8 && t<=20.6){return 0.55}
    return isContact(t) ? 0.10 : 0
}
func cursor(_ c:CGContext,_ p:CGPoint,dragging:Bool=false,scale:Double=1){
    c.saveGState();c.translateBy(x:p.x,y:p.y);c.scaleBy(x:scale,y:scale)
    shadow(c,0.2,4,2)
    let path=CGMutablePath();path.move(to:.zero);path.addLine(to:CGPoint(x:0,y:28));path.addLine(to:CGPoint(x:7,y:21));path.addLine(to:CGPoint(x:12,y:32));path.addLine(to:CGPoint(x:18,y:29));path.addLine(to:CGPoint(x:13,y:19));path.addLine(to:CGPoint(x:23,y:19));path.closeSubpath()
    c.addPath(path);c.setFillColor(ink.cgColor);c.setStrokeColor(NSColor.white.cgColor);c.setLineWidth(2.2);c.drawPath(using:.fillStroke)
    c.restoreGState()
}
func pencil(_ c:CGContext,_ p:CGPoint,_ contact:Bool,_ t:Double,opacity:Double=1){
    c.saveGState();c.setAlpha(opacity)
    if contact{circle(c,p,15,alpha(pressure(t)>0.2 ? orange:teal,0.08));circle(c,p,4,alpha(pressure(t)>0.2 ? orange:teal,0.75))}
    let lift=contact ? 0.0:18.0
    c.translateBy(x:p.x+lift*0.45,y:p.y-lift);c.rotate(by:0.53)
    c.saveGState();shadow(c,contact ? 0.22:0.15,contact ? 5:15,contact ? 4:13)
    gradient(c,CGRect(x:-8,y:-232,width:16,height:214),[color(0.78,0.80,0.80),color(1,1,1),color(0.91,0.92,0.91)],CGPoint(x:-8,y:-100),CGPoint(x:8,y:-100),radius:8)
    c.restoreGState()
    gradient(c,CGRect(x:-8,y:-232,width:16,height:214),[color(0.81,0.83,0.82),color(1,1,1),color(0.92,0.94,0.93)],CGPoint(x:-8,y:-100),CGPoint(x:8,y:-100),radius:8)
    poly(c,[CGPoint(x:-7,y:-21),CGPoint(x:7,y:-21),CGPoint(x:2,y:-3),CGPoint(x:0,y:0),CGPoint(x:-2,y:-3)],color(0.96,0.97,0.96))
    line(c,CGPoint(x:-4,y:-223),CGPoint(x:4,y:-223),color(0.82,0.84,0.84),0.7)
    c.restoreGState()
}
func drawPaper(_ c:CGContext,_ t:Double,scrolling:Double=0){
    c.saveGState();c.addRect(CGRect(x:screen.minX,y:screen.minY+48,width:screen.width,height:screen.height-48));c.clip()
    let p=paper.offsetBy(dx:0,dy:-scrolling)
    c.saveGState();shadow(c,0.045,12,4);rect(c,p,NSColor.white.cgColor,radius:8);c.restoreGState()
    let x=p.minX+54
    text(c,"FIELD NOTES  /  01",x,p.minY+30,11,.semibold,muted,tracking:2)
    text(c,"Patterns, connected.",x,p.minY+60,33,.semibold)
    text(c,"A space for ideas worth keeping.",x,p.minY+104,16,.regular,muted)
    let widths:[CGFloat]=[0.88,0.95,0.80,0.92,0.73]
    for i in 0..<5 {rect(c,CGRect(x:x,y:p.minY+153+CGFloat(i)*16,width:(p.width-108)*widths[i],height:4),color(0.81,0.83,0.82),radius:2)}
    text(c,"Observe. Connect. Revisit.",x,p.minY+258,20,.medium)
    for i in 0..<4 {rect(c,CGRect(x:x,y:p.minY+302+CGFloat(i)*15,width:(p.width-108)*widths[(i+2)%5],height:4),color(0.85,0.86,0.85),radius:2)}
    if scrolling>0 {
        text(c,"Another perspective.",x,p.minY+paper.height+25,28,.semibold)
        for i in 0..<8{rect(c,CGRect(x:x,y:p.minY+paper.height+85+CGFloat(i)*17,width:(p.width-108)*widths[i%5],height:4),color(0.83,0.85,0.84),radius:2)}
    }
    if t>=16 {
        let stop1=clamp((t-16)/1.9),stop2=clamp((t-18.8)/1.8)
        c.setStrokeColor(teal.cgColor);c.setLineWidth(3.2);c.setLineCap(.round);c.setLineJoin(.round)
        if stop1>0{c.beginPath();for i in 0...max(1,Int(stop1*100)){let uv=firstInk(min(stop1,Double(i)/100));let q=inRect(p,uv);if i==0{c.move(to:q)}else{c.addLine(to:q)}};c.strokePath()}
        if stop2>0{c.beginPath();for i in 0...max(1,Int(stop2*100)){let uv=secondInk(min(stop2,Double(i)/100));let q=inRect(p,uv);if i==0{c.move(to:q)}else{c.addLine(to:q)}};c.strokePath()}
    }
    c.restoreGState()
}
func drawWorkspace(_ c:CGContext,_ t:Double){
    let x=screen.minX,y=screen.minY+48
    rect(c,CGRect(x:x,y:y,width:170,height:screen.height-48),color(0.94,0.95,0.94))
    text(c,"WORKSPACE",x+22,y+27,10,.semibold,muted,tracking:1.5)
    for (i,s) in ["Reading notes","Projects","Recently opened"].enumerated(){
        if i==0{rect(c,CGRect(x:x+12,y:y+58,width:146,height:35),alpha(teal,0.10),radius:7)}
        text(c,s,x+24,y+68+CGFloat(i)*43,13,i==0 ? .medium:.regular,i==0 ? teal:muted)
    }
    text(c,"Ideas, within reach.",x+202,y+28,29,.semibold)
    text(c,"Pick up where you left off.",x+202,y+70,14,.regular,muted)
    let other=CGRect(x:x+520,y:y+124,width:320,height:242)
    rect(c,other,color(0.96,0.97,0.96),radius:12)
    let chart=[CGPoint(x:other.minX+25,y:other.minY+133),CGPoint(x:other.minX+85,y:other.minY+90),CGPoint(x:other.minX+145,y:other.minY+111),CGPoint(x:other.minX+204,y:other.minY+53),CGPoint(x:other.minX+283,y:other.minY+73)]
    c.beginPath();c.move(to:chart[0]);for q in chart.dropFirst(){c.addLine(to:q)};c.setStrokeColor(alpha(teal,0.40));c.setLineWidth(3);c.setLineJoin(.round);c.strokePath()
    text(c,"Connections",other.minX+20,other.minY+181,19,.medium,muted)
    let selected=t>=7.83
    var card=CGRect(x:x+203,y:y+124,width:288,height:242)
    if t>=9.4{let p=dragPoint(t);card=card.offsetBy(dx:(p.x-0.36)*350,dy:(p.y-0.62)*230)}
    c.saveGState();shadow(c,t>10.5 && t<14.1 ? 0.14:0.06,20,7);rect(c,card,NSColor.white.cgColor,radius:12);c.restoreGState()
    if selected{stroke(c,card,alpha(teal,0.72),width:2,radius:12)}
    rect(c,CGRect(x:card.minX+17,y:card.minY+17,width:254,height:145),color(0.95,0.96,0.94),radius:7)
    text(c,"Patterns,",card.minX+33,card.minY+41,24,.medium)
    text(c,"connected.",card.minX+33,card.minY+72,24,.medium)
    for i in 0..<3{rect(c,CGRect(x:card.minX+34,y:card.minY+115+CGFloat(i)*9,width:CGFloat(150-i*25),height:3),color(0.72,0.77,0.75),radius:1.5)}
    text(c,"Reading notes",card.minX+18,card.minY+180,19,.medium)
    text(c,"A few good ideas",card.minX+18,card.minY+210,12,.regular,muted)
}
func drawMac(_ c:CGContext,_ t:Double){
    let outer=CGRect(x:853,y:207,width:924,height:558)
    c.saveGState();shadow(c,0.06,18,10);rect(c,outer,color(0.18,0.20,0.21),radius:22);c.restoreGState()
    rect(c,outer,color(0.14,0.16,0.17),radius:22)
    stroke(c,outer,color(0.44,0.46,0.46,0.60),width:0.8,radius:22)
    c.saveGState();c.addPath(CGPath(roundedRect:screen,cornerWidth:13,cornerHeight:13,transform:nil));c.clip()
    rect(c,screen,color(0.975,0.978,0.973))
    rect(c,CGRect(x:screen.minX,y:screen.minY,width:screen.width,height:48),color(0.985,0.986,0.98))
    for i in 0..<3{circle(c,CGPoint(x:screen.minX+20+CGFloat(i)*18,y:screen.minY+24),4.5,[color(0.88,0.56,0.51),color(0.92,0.77,0.45),color(0.46,0.70,0.56)][i])}
    text(c,t>=15.1 ? "Reading notes" : "Workspace",screen.minX+109,screen.minY+15,14,.medium)
    text(c,t>=15.1 ? "ANNOTATE" : "STYLEUS DEMO",screen.maxX-155,screen.minY+18,9,.medium,muted,tracking:1.4)
    line(c,CGPoint(x:screen.minX,y:screen.minY+48),CGPoint(x:screen.maxX,y:screen.minY+48),color(0.85,0.87,0.85),0.7)
    if t<15.1 {drawWorkspace(c,t)} else {
        let scroll=t<22.5 ? 0.0 : 220*ease((t-22.9)/1.8)+55*ease((t-24.7)/1.1)
        drawPaper(c,t,scrolling:scroll)
    }
    if t<9.4 {
        let p=inRect(CGRect(x:screen.minX+145,y:screen.minY+125,width:380,height:350),remotePoint(t))
        cursor(c,p)
        let click=clamp((t-7.83)/0.45)
        if t>=7.83 && t<8.28{c.setStrokeColor(alpha(teal,1-click));c.setLineWidth(2);c.strokeEllipse(in:CGRect(x:p.x-8-click*17,y:p.y-8-click*17,width:16+click*34,height:16+click*34))}
    }else if t<15.1{
        let p=dragPoint(t);let cardX=screen.minX+203+(p.x-0.36)*350
        let cardY=screen.minY+48+124+(p.y-0.62)*230
        cursor(c,CGPoint(x:cardX+78,y:cardY+27),dragging:t>10.5 && t<14.1)
    }else if t<22.5 {
        let uv=(t>17.9 && t<18.8) ? firstInk(1) : drawingPoint(t)
        let p=inRect(paper,uv);cursor(c,p,scale:0.7)
    }
    c.restoreGState()
    // Neutral laptop chassis; intentionally no manufacturer logos.
    c.saveGState();shadow(c,0.04,14,7)
    poly(c,[CGPoint(x:850,y:766),CGPoint(x:1780,y:766),CGPoint(x:1816,y:779),CGPoint(x:814,y:779)],color(0.73,0.75,0.75));c.restoreGState()
    rect(c,CGRect(x:814,y:778,width:1002,height:4),color(0.60,0.63,0.63),radius:2)
    line(c,CGPoint(x:853,y:766),CGPoint(x:1777,y:766),color(0.85,0.87,0.87),0.8)
    poly(c,[CGPoint(x:1282,y:766),CGPoint(x:1348,y:766),CGPoint(x:1342,y:769),CGPoint(x:1288,y:769)],color(0.54,0.57,0.58))
}
func padTransform(_ c:CGContext){c.translateBy(x:485,y:735);c.rotate(by:-0.055);c.translateBy(x:-360,y:-252)}
func drawPad(_ c:CGContext,_ t:Double){
    c.saveGState();padTransform(c)
    c.saveGState();shadow(c,0.06,18,10);rect(c,CGRect(x:0,y:0,width:720,height:504),color(0.22,0.24,0.25),radius:28);c.restoreGState()
    rect(c,CGRect(x:0,y:0,width:720,height:504),color(0.16,0.18,0.19),radius:28)
    stroke(c,CGRect(x:0.5,y:0.5,width:719,height:503),color(0.55,0.58,0.58,0.35),width:0.7,radius:27.5)
    rect(c,CGRect(x:12,y:12,width:696,height:480),color(0.975,0.98,0.976),radius:22)
    text(c,"Styleus",35,36,24,.bold)
    circle(c,CGPoint(x:137,y:51),3.5,teal.cgColor)
    text(c,"Connected · USB-C",147,43,10,.medium,muted)
    circle(c,CGPoint(x:258,y:51),7,color(0.90,0.94,0.93));text(c,"i",256.7,45,9,.semibold,teal)
    rect(c,CGRect(x:409,y:33,width:134,height:34),color(0.90,0.94,0.93),radius:9)
    text(c,t>=15.1 && t<22.5 ? "Drawing tablet" : "Trackpad",423,44,12,.medium,teal)
    text(c,"⌄",524,39,16,.medium,teal)
    text(c,"⚙",562,39,19,.regular,muted)
    text(c,"Disconnect",597,44,11,.medium,teal)
    // The pressure rail sits outside the movement rectangle, as in the native app.
    rect(c,CGRect(x:32,y:107,width:9,height:327),color(0.86,0.90,0.88),radius:4.5)
    let pr=pressure(t),height=327*pr
    if height>0{rect(c,CGRect(x:32,y:434-height,width:9,height:height),(pr>0.2 ? orange:teal).cgColor,radius:4.5)}
    line(c,CGPoint(x:28,y:369),CGPoint(x:45,y:369),color(0.40,0.50,0.48,0.65),1)
    rect(c,padArea,color(0.925,0.948,0.939),radius:17)
    let drawing=t>=15.1 && t<22.5
    if drawing{stroke(c,padArea,alpha(teal,0.4),width:1.2,radius:17)}
    let held=pr>0.2
    circle(c,CGPoint(x:76,y:126),3,(held ? orange:teal).cgColor)
    text(c,held ? (drawing ? "Drawing" : "Dragging") : (isContact(t) ? "Pointing" : "Pencil ready"),86,119,10,.medium,held ? orange:muted)
    // Subtle corner marks suggest a generous, uninterrupted input surface.
    let dotColor=color(0.55,0.66,0.60,0.17)
    for row in 0..<10 {for col in 0..<19 {circle(c,CGPoint(x:84+CGFloat(col)*30,y:154+CGFloat(row)*25),0.8,dotColor)}}
    rect(c,CGRect(x:286,y:477,width:148,height:4),color(0.15,0.20,0.18,0.7),radius:2)
    if t<22.4{
        let uv=t<9.4 ? trackPoint(t) : (t<15.1 ? dragPoint(t):drawingPoint(t))
        let p=inRect(padArea,uv)
        let penFade=smooth((t-1.0)/0.8)*(1-smooth((t-21.4)/0.8))
        pencil(c,p,isContact(t),t,opacity:penFade)
    } else if t<26 {
        let a=smooth((t-22.4)/0.4)*(1-smooth((t-24.7)/0.2))
        let p=point(CGPoint(x:0.49,y:0.73),CGPoint(x:0.49,y:0.29),ease((t-22.9)/1.8))
        for dx in [-0.055,0.055] {
            let q=inRect(padArea,CGPoint(x:p.x+dx,y:p.y))
            c.saveGState();c.setAlpha(a)
            circle(c,q,21,alpha(teal,0.08));circle(c,q,12,alpha(teal,0.20));stroke(c,CGRect(x:q.x-12,y:q.y-12,width:24,height:24),alpha(teal,0.6),width:1.2,radius:12)
            c.restoreGState()
        }
    }
    c.restoreGState()
}
func backdrop(_ c:CGContext){
    gradient(c,CGRect(x:0,y:0,width:W,height:H),[color(0.98,0.979,0.96),color(0.91,0.947,0.927)],CGPoint(x:200,y:0),CGPoint(x:1600,y:1080))
    c.saveGState();let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color(1,1,1,0.75),color(1,1,1,0)] as CFArray,locations:[0,1])!;c.drawRadialGradient(g,startCenter:CGPoint(x:650,y:300),startRadius:0,endCenter:CGPoint(x:650,y:300),endRadius:1050,options:[]);c.restoreGState()
    // A fine architectural baseline, rather than a busy decorative grid.
    line(c,CGPoint(x:110,y:990),CGPoint(x:1810,y:990),color(0.56,0.66,0.61,0.16),1)
}
struct Title {let start:Double;let end:Double;let number:String;let line1:String;let line2:String;let sub:String}
let titles:[Title]=[
 Title(start:0,end:3.4,number:"STYLEUS",line1:"Your Pencil.",line2:"Your Mac.",sub:"A new connection for the tools you already own."),
 Title(start:3.4,end:9.4,number:"01  /  POINT",line1:"Point.",line2:"Tap. Go.",sub:"A Pencil trackpad for your Mac."),
 Title(start:9.4,end:15.1,number:"02  /  MOVE",line1:"Press. Move.",line2:"Release.",sub:"A firmer touch activates click-drag."),
 Title(start:15.1,end:22.4,number:"03  /  ANNOTATE",line1:"Make",line2:"your mark.",sub:"Basic mouse-based annotation on your Mac."),
 Title(start:22.4,end:26.1,number:"04  /  SCROLL",line1:"Two fingers.",line2:"Keep the flow.",sub:"Scroll vertically and horizontally.")
]
func titlesAt(_ c:CGContext,_ t:Double){
    for title in titles {
        let fi=smooth((t-title.start)/0.55),fo=1-smooth((t-(title.end-0.35))/0.35)
        let a=fi*fo;if a<0.001{continue}
        c.saveGState();c.setAlpha(a);let y=142+12*(1-fi)
        text(c,title.number,132,y,14,.semibold,teal,tracking:2.8)
        text(c,title.line1,126,y+37,68,.semibold,ink,tracking:-2.1)
        text(c,title.line2,126,y+110,68,.semibold,ink,tracking:-2.1)
        text(c,title.sub,132,y+207,18,.regular,muted)
        c.restoreGState()
    }
}
let space=CGColorSpaceCreateDeviceRGB()
let row=W*4
let bytes=UnsafeMutableRawPointer.allocate(byteCount:row*H,alignment:64)
defer {bytes.deallocate()}
let ctx=CGContext(data:bytes,width:W,height:H,bitsPerComponent:8,bytesPerRow:row,space:space,bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue)!
ctx.setShouldAntialias(true);ctx.setAllowsAntialiasing(true);ctx.interpolationQuality = .high
func render(_ t:Double){
    ctx.saveGState();ctx.translateBy(x:0,y:CGFloat(H));ctx.scaleBy(x:1,y:-1)
    backdrop(ctx)
    let end=ease((t-25.7)/1.0)
    let intro=smooth(t/1.1)
    ctx.saveGState();ctx.setAlpha(intro*(1-end));ctx.translateBy(x:0,y:22*(1-intro)-24*end)
    drawMac(ctx,t);drawPad(ctx,t);titlesAt(ctx,t)
    ctx.restoreGState()
    // A tiny disclosure makes the film honest about being an illustrated interaction demo.
    text(ctx,"Illustrated demo",1670,46,13,.medium,muted)
    if end>0 {
        ctx.saveGState();ctx.setAlpha(end);let rise=14*(1-end)
        if let ipadIcon,let macIcon {
            drawImage(ctx,ipadIcon,CGRect(x:848,y:252+rise,width:100,height:100))
            drawImage(ctx,macIcon,CGRect(x:972,y:252+rise,width:100,height:100))
        }
        centerText(ctx,"Styleus",370+rise,104,.semibold)
        centerText(ctx,"Your Pencil. Your Mac.",501+rise,37,.regular)
        centerText(ctx,"Build it yourself. Free and open source.",586+rise,22,.medium,teal)
        centerText(ctx,"Native iPad + Mac apps · Encrypted local connection",633+rise,17,.regular,muted)
        centerText(ctx,"Free iPad signing renews every 7 days.",956,14,.regular,muted)
        ctx.restoreGState()
    }
    ctx.restoreGState()
}
let args=CommandLine.arguments
if let i=args.firstIndex(of:"--still"),args.count>i+2 {
    let t=Double(args[i+1]) ?? 0;render(t)
    let url=URL(fileURLWithPath:args[i+2]);let dst=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(dst,ctx.makeImage()!,nil);CGImageDestinationFinalize(dst)
} else {
    let count=Int(duration*Double(fps))
    for i in 0..<count {
        autoreleasepool {
            render(Double(i)/Double(fps))
            FileHandle.standardOutput.write(Data(bytesNoCopy:bytes,count:row*H,deallocator:.none))
        }
        if i%120==0{fputs("Rendered \(i)/\(count) frames\n",stderr)}
    }
}
