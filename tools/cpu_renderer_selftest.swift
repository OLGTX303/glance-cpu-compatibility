import Foundation
import CoreGraphics
import CoreVideo
import Dispatch
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let p = context.data!.assumingMemoryBound(to: UInt8.self).advanced(by: y*context.bytesPerRow+x*4)
    return [p[0],p[1],p[2],p[3]]
}
@main
struct CPURendererSelfTest {
    static func main() {
var buffer: CVPixelBuffer?
assert(CVPixelBufferCreate(kCFAllocatorDefault,64,48,kCVPixelFormatType_32BGRA,nil,&buffer)==kCVReturnSuccess)
let b=buffer!
CVPixelBufferLockBaseAddress(b,[])
let base=CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to:UInt8.self), stride=CVPixelBufferGetBytesPerRow(b)
for y in 0..<48 { for x in 0..<64 {
    let p=base.advanced(by:y*stride+x*4)
    p[0]=y<24 ? 0 : 255; p[1]=0; p[2]=y<24 ? 255 : 0; p[3]=0
} }
CVPixelBufferUnlockBaseAddress(b,[])
let images=CPUFrameRenderer.images(from:b,maxLongEdge:32)!
assert(images.native.width==64 && images.native.height==48)
assert(images.working.width==32 && images.working.height==24)
assert(pixel(images.native,4,4)[2]==255 && pixel(images.native,4,40)[0]==255)
CVPixelBufferLockBaseAddress(b,[]); memset(CVPixelBufferGetBaseAddress(b),0,CVPixelBufferGetDataSize(b));CVPixelBufferUnlockBaseAddress(b,[])
assert(pixel(images.native,4,4)[2]==255,"Copied frame must survive camera-buffer reuse")
let top=CPUFrameRenderer.crop(images.native,workingSize:CGSize(width:32,height:24),imageRect:CGRect(x:2,y:2,width:6,height:4))!
let bottom=CPUFrameRenderer.crop(images.native,workingSize:CGSize(width:32,height:24),imageRect:CGRect(x:2,y:17,width:6,height:4))!
assert(pixel(top,top.width/2,top.height/2)[2]==255,"Top-left crop orientation")
assert(pixel(bottom,bottom.width/2,bottom.height/2)[0]==255,"Bottom crop orientation")
assert(CPUFrameRenderer.crop(images.native,workingSize:.zero,imageRect:CGRect(x:1,y:1,width:3,height:3))==nil)
assert(CPUFrameRenderer.scaled(images.native,maxLongEdge:0)==nil)
DispatchQueue.concurrentPerform(iterations:200) { i in
    autoreleasepool {
        let resized=CPUFrameRenderer.scaled(images.native,maxLongEdge:CGFloat(12+i%20))!
        assert(resized.width>0 && resized.height>0)
        let cropped=CPUFrameRenderer.crop(images.native,workingSize:CGSize(width:32,height:24),imageRect:CGRect(x:-1,y:1,width:8,height:7),maxEdge:12)!
        assert(max(cropped.width,cropped.height)<=12)
    }
}
print("PASS: opaque camera pixels with zero alpha, BGRA ownership, camera-buffer reuse, scale dimensions, top/bottom crop orientation, invalid input, and 200 concurrent resize/crop cycles")

    }
}
