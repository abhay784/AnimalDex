import AVFoundation
import SwiftUI

/// Live viewfinder. On device this is a real `AVCaptureVideoPreviewLayer`; in the
/// Simulator it renders the current bundled sample, so the framing and overlays
/// are identical in both environments.
struct CameraPreviewView: View {
    let source: any FrameSource

    var body: some View {
        // GeometryReader gives the content a *definite* size. Without it,
        // `.scaledToFill()` propagates the source image's own dimensions as the
        // view's ideal size — and `.clipped()` does not help, because clipping
        // affects drawing, not layout. A 1200px sample photo was stretching the
        // whole chrome past the screen edge and hiding the lens and two tabs.
        GeometryReader { geo in
            preview
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let session = source.previewSession {
                PreviewLayerView(session: session)
            } else if let sample = (source as? SampleFrameSource)?.currentImage {
                Image(uiImage: sample)
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .bottomLeading) { simulatorHint }
            } else {
                Color.black.overlay {
                    Text("NO SIGNAL")
                        .font(Theme.display(20))
                        .outlinedText(Theme.phosphorDim)
                }
            }
        }
    }

    private var simulatorHint: some View {
        Text("SIMULATOR — TAP TO CYCLE SAMPLE")
            .font(Theme.screenText(9))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(.leading, 10)
            .padding(.bottom, 10)
    }
}

private struct PreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

/// Backing the preview layer with `layerClass` avoids manually syncing the
/// layer's frame on every bounds change.
private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
