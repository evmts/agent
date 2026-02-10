import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import type { MDXContent } from "mdx/types";

export function render(
  Component: MDXContent,
  props: Record<string, any> = {},
): string {
  const html = renderToStaticMarkup(React.createElement(Component, props));
  return html
    .replace(/<\/(p|div|h[1-6]|li|ul|ol|pre|blockquote|section)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, "/")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
