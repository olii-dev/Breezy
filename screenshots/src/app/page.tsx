"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { toPng } from "html-to-image";

const IPHONE_W = 1320;
const IPHONE_H = 2868;

const MK_W = 1022;
const MK_H = 2082;
const SC_L = (52 / MK_W) * 100;
const SC_T = (46 / MK_H) * 100;
const SC_W = (918 / MK_W) * 100;
const SC_H = (1990 / MK_H) * 100;
const SC_RX = (126 / 918) * 100;
const SC_RY = (126 / 1990) * 100;

const IPHONE_SIZES = [
  { label: '6.9"', w: 1320, h: 2868 },
  { label: '6.5"', w: 1284, h: 2778 },
  { label: '6.3"', w: 1206, h: 2622 },
  { label: '6.1"', w: 1125, h: 2436 },
] as const;

const THEMES = {
  "breezy-purple": {
    bg: "#1E1B35",
    bgGradient: "linear-gradient(180deg, #2D1B69 0%, #1E1B35 60%)",
    fg: "#FFFFFF",
    muted: "#A8A3B8",
    accent: "#A8C8E0",
  },
} as const;

type ThemeId = keyof typeof THEMES;

const COPY = {
  en: {
    label: "BREEZY",
    hero: {
      label: "WEATHER",
      headline: (
        <>
          Accurate.<br />Beautiful.<br />Yours.
        </>
      ),
    },
    feature2: {
      label: "DESIGN",
      headline: (
        <>
          Dynamic<br />gradients that
          <br />
          match the sky.
        </>
      ),
    },
    feature3: {
      label: "CUSTOMIZE",
      headline: (
        <>
          Make it yours.<br />Units, icons,
          <br />
          appearance.
        </>
      ),
    },
    feature4: {
      label: "FORECAST",
      headline: (
        <>
          10 days out.<br />Interactive
          <br />
          charts.
        </>
      ),
    },
    feature5: {
      label: "DETAILS",
      headline: (
        <>
          UV. Air quality.<br />Humidity.<br />Wind.
        </>
      ),
    },
  },
} as const;

const imageCache: Record<string, string> = {};

function img(path: string): string {
  return imageCache[path] || path;
}

async function preloadAllImages() {
  const paths = [
    "/mockup.png",
    "/app-icon.png",
    "/screenshots/apple/iphone/en/01-home.png",
    "/screenshots/apple/iphone/en/02-forecast.png",
    "/screenshots/apple/iphone/en/03-charts.png",
    "/screenshots/apple/iphone/en/04-settings.png",
    "/screenshots/apple/iphone/en/05-more.png",
  ];

  await Promise.all(
    paths.map(async (path) => {
      try {
        const resp = await fetch(path);
        const blob = await resp.blob();
        const dataUrl = await new Promise<string>((resolve) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve(reader.result as string);
          reader.readAsDataURL(blob);
        });
        imageCache[path] = dataUrl;
      } catch (e) {
        console.error("Failed to load", path, e);
      }
    })
  );
}

function Phone({ src, alt, style }: { src: string; alt: string; style?: React.CSSProperties }) {
  return (
    <div style={{ position: "relative", aspectRatio: `${MK_W}/${MK_H}`, ...style }}>
      <img
        src={img("/mockup.png")}
        alt=""
        style={{ display: "block", width: "100%", height: "100%" }}
        draggable={false}
      />
      <div
        style={{
          position: "absolute",
          zIndex: 10,
          overflow: "hidden",
          left: `${SC_L}%`,
          top: `${SC_T}%`,
          width: `${SC_W}%`,
          height: `${SC_H}%`,
          borderRadius: `${SC_RX}% / ${SC_RY}%`,
        }}
      >
        <img
          src={src}
          alt={alt}
          style={{
            display: "block",
            width: "100%",
            height: "100%",
            objectFit: "cover",
            objectPosition: "top",
          }}
          draggable={false}
        />
      </div>
    </div>
  );
}

function Caption({
  cW,
  label,
  headline,
}: {
  cW: number;
  label: string;
  headline: React.ReactNode;
}) {
  return (
    <div style={{ position: "absolute", top: "8%", left: "6%", right: "6%" }}>
      <div
        style={{
          fontSize: cW * 0.025,
          fontWeight: 600,
          color: THEMES["breezy-purple"].muted,
          letterSpacing: cW * 0.008,
          marginBottom: cW * 0.015,
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontSize: cW * 0.09,
          fontWeight: 700,
          color: THEMES["breezy-purple"].fg,
          lineHeight: 1.05,
        }}
      >
        {headline}
      </div>
    </div>
  );
}

export default function ScreenshotsPage() {
  const [ready, setReady] = useState(false);
  const [sizeIdx, setSizeIdx] = useState(0);
  const [exporting, setExporting] = useState<string | null>(null);
  const exportRefs = useRef<(HTMLDivElement | null)[]>([]);

  const size = IPHONE_SIZES[sizeIdx];
  const theme = THEMES["breezy-purple"];
  const cW = IPHONE_W;
  const cH = IPHONE_H;

  useEffect(() => {
    preloadAllImages().then(() => setReady(true));
  }, []);

  const captureSlide = useCallback(
    async (el: HTMLElement, w: number, h: number): Promise<string> => {
      const clone = el.cloneNode(true) as HTMLElement;
      clone.style.position = "fixed";
      clone.style.left = "0";
      clone.style.top = "0";
      clone.style.zIndex = "-9999";
      clone.removeAttribute("id");
      
      // Replace all font-family with system fonts 
      const allElements = clone.querySelectorAll("*");
      allElements.forEach((el) => {
        const htmlEl = el as HTMLElement;
        if (htmlEl.style.fontFamily) {
          htmlEl.style.fontFamily = "system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";
        }
      });
      
      document.body.appendChild(clone);
      
      const opts = { 
        width: w, 
        height: h, 
        pixelRatio: 1,
        filter: (node) => {
          const tag = node.tagName;
          if (tag === "LINK") return false;
          if (tag === "STYLE") return false;
          if (tag === "SCRIPT") return false;
          return true;
        }
      };

      let dataUrl = "";
      try {
        // First call warms up the renderer
        await toPng(clone, opts);
        // Second call captures the actual content
        dataUrl = await toPng(clone, opts);
      } catch (e) {
        console.warn("toPng failed:", e);
      }

      clone.remove();
      return dataUrl;
    },
    []
  );

  const exportAll = useCallback(async () => {
    let failedCount = 0;
    for (let i = 0; i < 5; i++) {
      setExporting(`${i + 1}/5`);
      const el = exportRefs.current[i];
      if (!el) continue;
      
      let dataUrl = "";
      for (let attempt = 0; attempt < 3 && !dataUrl; attempt++) {
        dataUrl = await captureSlide(el, size.w, size.h);
        if (!dataUrl) await new Promise(r => setTimeout(r, 500));
      }
      
      if (dataUrl) {
        const a = document.createElement("a");
        a.href = dataUrl;
        a.download = `${String(i + 1).padStart(2, "0")}-${["hero", "design", "customize", "forecast", "details"][i]}-en-${size.w}x${size.h}.png`;
        a.click();
        await new Promise((r) => setTimeout(r, 300));
      } else {
        failedCount++;
      }
    }
    if (failedCount > 0) {
      alert(`${failedCount} slides failed to export. Check console for errors.`);
    }
    setExporting(null);
  }, [captureSlide, size]);

  if (!ready) {
    return (
      <div
        style={{
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#f3f4f6",
        }}
      >
        <p style={{ fontSize: 18, color: "#6b7280" }}>Loading images…</p>
      </div>
    );
  }

  const slides = [
    {
      id: "hero",
      copy: COPY.en.hero,
      src: "/screenshots/apple/iphone/en/01-home.png",
    },
    {
      id: "design",
      copy: COPY.en.feature2,
      src: "/screenshots/apple/iphone/en/02-forecast.png",
    },
    {
      id: "customize",
      copy: COPY.en.feature3,
      src: "/screenshots/apple/iphone/en/03-charts.png",
    },
    {
      id: "forecast",
      copy: COPY.en.feature4,
      src: "/screenshots/apple/iphone/en/04-settings.png",
    },
    {
      id: "details",
      copy: COPY.en.feature5,
      src: "/screenshots/apple/iphone/en/05-more.png",
    },
  ];

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f3f4f6",
        position: "relative",
        overflowX: "hidden",
      }}
    >
      <div
        style={{
          position: "sticky",
          top: 0,
          zIndex: 50,
          background: "white",
          borderBottom: "1px solid #e5e7eb",
          display: "flex",
          alignItems: "center",
        }}
      >
        <div
          style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            gap: 12,
            padding: "12px 16px",
            overflowX: "auto",
            minWidth: 0,
          }}
        >
          <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: "nowrap" }}>
            Breezy · Screenshots
          </span>
          <span
            style={{
              fontSize: 12,
              color: "#6b7280",
              padding: "4px 10px",
              background: "#f3f4f6",
              borderRadius: 6,
            }}
          >
            iPhone
          </span>
          <select
            value={sizeIdx}
            onChange={(e) => setSizeIdx(Number(e.target.value))}
            style={{
              fontSize: 12,
              border: "1px solid #e5e7eb",
              borderRadius: 6,
              padding: "4px 10px",
            }}
          >
            {IPHONE_SIZES.map((s, i) => (
              <option key={i} value={i}>
                {s.label} — {s.w}×{s.h}
              </option>
            ))}
          </select>
        </div>
        <div style={{ flexShrink: 0, padding: "12px 16px", borderLeft: "1px solid #e5e7eb" }}>
          <button
            onClick={exportAll}
            disabled={!!exporting}
            style={{
              padding: "7px 20px",
              background: exporting ? "#93c5fd" : "#2563eb",
              color: "white",
              border: "none",
              borderRadius: 8,
              fontSize: 12,
              fontWeight: 600,
              cursor: exporting ? "default" : "pointer",
              whiteSpace: "nowrap",
            }}
          >
            {exporting ? `Exporting… ${exporting}` : "Export All"}
          </button>
        </div>
      </div>

      <div style={{ padding: 24, display: "flex", flexDirection: "column", gap: 32 }}>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
            gap: 24,
          }}
        >
          {slides.map((slide, idx) => (
            <div key={slide.id}>
              <div
                style={{
                  fontSize: 12,
                  fontWeight: 600,
                  color: "#6b7280",
                  marginBottom: 8,
                }}
              >
                {idx + 1}. {slide.id}
              </div>
<div
                  style={{
                    width: "100%",
                    aspectRatio: `${cW}/${cH}`,
                    transformOrigin: "top left",
                    transform: `scale(${Math.min(280 / cW, 200 / cH)})`,
                  }}
                >
                  <div
                    style={{
                      width: cW,
                      height: cH,
                      position: "relative",
                      background: theme.bgGradient,
                      overflow: "hidden",
                    }}
                  >
                    <Caption cW={cW} label={slide.copy.label} headline={slide.copy.headline} />
                    <Phone
                      src={img(slide.src)}
                      alt={slide.id}
                      style={{
                        position: "absolute",
                        bottom: 0,
                        width: "84%",
                        left: "50%",
                        transform: "translateX(-50%) translateY(10%)",
                      }}
                    />
                  </div>
                </div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ position: "absolute", left: -9999, top: 0 }}>
        {slides.map((slide, idx) => (
          <div
            key={`export-${slide.id}`}
            ref={(el) => {
              exportRefs.current[idx] = el;
            }}
            style={{
              width: cW,
              height: cH,
              position: "relative",
              background: theme.bgGradient,
              overflow: "hidden",
            }}
          >
            <Caption cW={cW} label={slide.copy.label} headline={slide.copy.headline} />
            <Phone
              src={img(slide.src)}
              alt={slide.id}
              style={{
                position: "absolute",
                bottom: 0,
                width: "84%",
                left: "50%",
                transform: "translateX(-50%) translateY(10%)",
              }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}