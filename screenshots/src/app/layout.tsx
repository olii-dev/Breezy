import type { Metadata } from "next";
import { Fraunces } from "next/font/google";
import "./globals.css";

const display = Fraunces({
  subsets: ["latin"],
  variable: "--font-display",
  axes: ["SOFT", "WONK"],
});

export const metadata: Metadata = {
  title: "Breezy - App Store Screenshots",
  description: "Generate App Store screenshots for Breezy weather app",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`h-full antialiased ${display.variable}`} style={{ fontFamily: "sans-serif" }}>
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
