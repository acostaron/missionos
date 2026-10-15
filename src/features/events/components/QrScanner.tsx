// Camera QR reader (Pass 9.12, written by Claude 2026-10-16).
// Uses the browser's built-in BarcodeDetector when available (Chrome / Android) and falls back to jsQR
// (Safari / iPhone). Calls onDetect once per new code; the same code is ignored for a few seconds.
import { useEffect, useRef, useState } from 'react';

type Detector = { detect: (src: CanvasImageSource) => Promise<{ rawValue: string }[]> };
type DetectorCtor = new (opts: { formats: string[] }) => Detector;

export function QrScanner({ paused, onDetect }: { paused: boolean; onDetect: (text: string) => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const onDetectRef = useRef(onDetect);
  const pausedRef = useRef(paused);
  const [status, setStatus] = useState<'starting' | 'running' | 'denied' | 'unavailable'>('starting');

  useEffect(() => {
    onDetectRef.current = onDetect;
  }, [onDetect]);
  useEffect(() => {
    pausedRef.current = paused;
  }, [paused]);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let stopped = false;
    let timer: number | undefined;
    let last = { text: '', at: 0 };
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });

    const start = async () => {
      if (!navigator.mediaDevices?.getUserMedia) {
        setStatus('unavailable');
        return;
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: 'environment' } },
          audio: false,
        });
      } catch {
        setStatus('denied');
        return;
      }
      if (stopped) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      const video = videoRef.current;
      if (!video) return;
      video.srcObject = stream;
      await video.play().catch(() => undefined);
      setStatus('running');

      const Ctor = (window as unknown as { BarcodeDetector?: DetectorCtor }).BarcodeDetector;
      let detector: Detector | null = null;
      if (Ctor) {
        try {
          detector = new Ctor({ formats: ['qr_code'] });
        } catch {
          detector = null;
        }
      }
      const jsQR = detector ? null : (await import('jsqr')).default;

      const tick = async () => {
        if (stopped) return;
        if (!pausedRef.current && video.readyState >= 2 && video.videoWidth > 0) {
          let text: string | null = null;
          try {
            if (detector) {
              const codes = await detector.detect(video);
              text = codes[0]?.rawValue ?? null;
            } else if (jsQR && ctx) {
              const w = Math.min(video.videoWidth, 720);
              const h = Math.round((video.videoHeight * w) / video.videoWidth);
              canvas.width = w;
              canvas.height = h;
              ctx.drawImage(video, 0, 0, w, h);
              const img = ctx.getImageData(0, 0, w, h);
              text = jsQR(img.data, w, h, { inversionAttempts: 'dontInvert' })?.data ?? null;
            }
          } catch {
            text = null;
          }
          const now = Date.now();
          if (text && !(text === last.text && now - last.at < 4000)) {
            last = { text, at: now };
            onDetectRef.current(text);
          }
        }
        timer = window.setTimeout(tick, 200);
      };
      tick();
    };

    start();
    return () => {
      stopped = true;
      if (timer) window.clearTimeout(timer);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  return (
    <div className="relative overflow-hidden rounded-card bg-black">
      <video ref={videoRef} className="aspect-square w-full object-cover sm:aspect-video" muted playsInline />
      <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
        <div className={`h-3/5 w-3/5 rounded-xl border-4 ${paused ? 'border-white/30' : 'border-white/80'}`} />
      </div>
      {status !== 'running' && (
        <div className="absolute inset-0 flex items-center justify-center p-6 text-center text-sm text-white">
          {status === 'starting' && 'Starting camera…'}
          {status === 'denied' && 'Camera access was blocked. Allow the camera for this site in your browser settings, or type the code below.'}
          {status === 'unavailable' && 'This browser cannot use the camera. Use a handheld scanner or type the code below.'}
        </div>
      )}
    </div>
  );
}
