import type { Metadata } from "next";
import "./globals.css";

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
    <html lang="en" className="h-full antialiased" style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', system-ui, sans-serif" }}>
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
