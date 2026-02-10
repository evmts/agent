import React from "react"
import type { Metadata, Viewport } from 'next'
import { Inter, JetBrains_Mono } from 'next/font/google'

import './globals.css'

const _inter = Inter({ subsets: ['latin'], variable: '--font-inter' })
const _jetbrains = JetBrains_Mono({ subsets: ['latin'], variable: '--font-jetbrains' })

export const metadata: Metadata = {
  title: 'Smithers v2 - Chat-First IDE Prototype',
  description: 'Interactive web prototype of the Smithers v2 dual-window macOS IDE concept',
}

export const viewport: Viewport = {
  themeColor: '#0F111A',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${_inter.variable} ${_jetbrains.variable}`}>
      <body className="font-sans antialiased">{children}</body>
    </html>
  )
}
